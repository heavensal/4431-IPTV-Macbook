import SwiftUI
import AppKit
import Security

enum Vault {
    static let key: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"local.heavensal.4431iptv",kSecAttrAccount as String:"playlist"]
    static func read() throws -> String? {
        var q = key; q[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let d = result as? Data else { throw Failure.secrets }
        return String(data:d,encoding:.utf8)
    }
    static func save(_ s: String) throws {
        let data = Data(s.utf8)
        var q = key; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary,nil)
        if status == errSecDuplicateItem {
            guard SecItemUpdate(key as CFDictionary,[kSecValueData as String:data] as CFDictionary) == errSecSuccess else { throw Failure.secrets }
        } else if status != errSecSuccess { throw Failure.secrets }
    }
    static func clear() throws {
        let status = SecItemDelete(key as CFDictionary)
        guard [errSecSuccess,errSecItemNotFound].contains(status) else { throw Failure.secrets }
    }
}
@MainActor final class Model: ObservableObject {
    @Published var profile = Profile()
    @Published var useProfile = true
    @Published var raw = ""
    @Published var error = ""
    @Published var loading = false
    @Published var connected = false
    @Published var saved = false
    @Published var kind = Kind.tv
    @Published var query = ""
    @Published var results = [Entry]()
    @Published var children = [Entry]()
    private var seasonRows = [Int:[Entry]]()
    @Published var seasons = [Int]()
    @Published var season = 0
    @Published var embeddedURL: URL?
    func changeSeason(_ value: Int) { season = value; children = seasonRows[value] ?? [] }
    func clearEpisodes() { seasonRows = [:]; seasons = []; children = [] }
    @Published var seriesCover: URL?
    @Published var heading = ""
    @Published var media = ""
    @Published var fetching = false
    @Published var groups = [Category]()
    @Published var selected: Category?
    @Published var browsing = false
    @Published var searching = false
    private var liveExt = "m3u8"
    private var provider: Provider?, index = [(Entry,String)]()
    private var session: Task<Void,Never>?, search: Task<Void,Never>?, detail: Task<Void,Never>?
    func restore() {
        do { if let s = try Vault.read() { saved = true; if let stored = try? JSONDecoder().decode(Profile.self,from:Data(s.utf8)) { profile = stored; useProfile = true; submit() } else { useProfile = false; raw = s; submit() } } }
        catch { self.error = error.localizedDescription }
    }
    func submit() {
        let p: Provider, s: String
        do {
            if useProfile { p = try profile.provider(); s = String(decoding:try JSONEncoder().encode(profile),as:UTF8.self) }
            else { p = try Provider(raw); s = raw }
        } catch { self.error = connectionMessage(error); return }
        session?.cancel(); error = ""
        let apiMode = useProfile
        loading = true
        session = Task {
            do {
                var items = [Entry]()
                if apiMode { liveExt = try await authenticate(p) }
                else { items = try await playlist(p); if let extra = try? await shows(p) { items += extra } }
                try Task.checkCancellation()
                guard apiMode || !items.isEmpty else { throw Failure.empty }
                let snapshot = items
                let indexed = await Task.detached { snapshot.map { ($0,$0.needle) } }.value
                try Task.checkCancellation()
                try Vault.save(s); profile.password = ""; raw = ""; saved = true; provider = p; index = indexed; connected = true; filter()
            } catch { if !Task.isCancelled { self.error = connectionMessage(error) } }
            if !Task.isCancelled { loading = false }
        }
    }
    func filter() {
        search?.cancel()
        guard connected else { return }
        if useProfile { browse(); return }
        let all = index, k = kind, term = query.trimmingCharacters(in:.whitespaces).folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current)
        search = Task.detached { [weak self] in
            var hits = [Entry]()
            for (item,name) in all {
                if Task.isCancelled { return }
                if term.isEmpty ? item.kind == k : name.contains(term) { hits.append(item) }
            }
            let found = hits
            await MainActor.run { if !Task.isCancelled { self?.results = found } }
        }
    }
    func browse(global: Bool = false) {
        search?.cancel()
        guard let p = provider else { return }
        let k = kind, group = selected, ext = liveExt
        let term = query.trimmingCharacters(in:.whitespacesAndNewlines)
        searching = global && !term.isEmpty
        let runSearch = searching
        results = []; browsing = true; error = ""
        search = Task {
            defer { if !Task.isCancelled { browsing = false } }
            do {
                if runSearch {
                    var hits = [Entry]()
                    var failures = [String]()
                    for section in Kind.allCases {
                        try Task.checkCancellation()
                        do { hits += try await mediaRows(p,kind:section,category:nil,liveExt:ext,matching:term,offset:hits.count) }
                        catch { failures.append(section.rawValue + " · " + connectionMessage(error)) }
                    }
                    try Task.checkCancellation(); results = hits; error = failures.joined(separator:" · ")
                } else if let group {
                    let rows = try await mediaRows(p,kind:k,category:group,liveExt:ext)
                    try Task.checkCancellation(); results = rows
                } else {
                    groups = []
                    let rows = try await categories(p,kind:k)
                    try Task.checkCancellation(); groups = rows
                }
            } catch { if !Task.isCancelled { self.error = connectionMessage(error) } }
        }
    }
    func resetSection() {
        selected = nil; groups = []; detail?.cancel(); fetching = false; heading = ""; clearEpisodes()
        filter()
    }
    func stop() { embeddedURL = nil; media = "" }
    func select(_ item: Entry) {
        detail?.cancel(); fetching = false; error = ""
        if let id = item.remote, let provider {
            heading = item.title; seriesCover = item.artwork; clearEpisodes(); fetching = true
            detail = Task {
                do { let rows = try await episodes(provider,id); try Task.checkCancellation(); seasonRows = Dictionary(grouping:rows) { $0.season ?? 0 }; seasons = seasonRows.keys.sorted(); changeSeason(seasons.first ?? 0) }
                catch { if !Task.isCancelled { self.error = Failure.episodes.localizedDescription } }
                if !Task.isCancelled { fetching = false }
            }
        } else if let url = item.url {
            if !children.contains(where: { $0.url == url }) { clearEpisodes(); heading = "" }
            media = item.title; embeddedURL = url
        }
    }
    func logout() {
        session?.cancel(); detail?.cancel(); search?.cancel(); stop()
        groups = []; selected = nil; searching = false; browsing = false; profile = Profile(); index = []; provider = nil; results = []; clearEpisodes(); heading = ""; raw = ""; query = ""; connected = false; loading = false; fetching = false; error = ""
        do { try Vault.clear(); saved = false } catch { saved = true; self.error = error.localizedDescription }
    }
}
@main struct IPTVApp: App {
    @StateObject private var m = Model()
    var body: some Scene { Window("4431 IPTV", id:"main") { Screen(m:m).task { m.restore() } } }
}
struct Screen: View {
    @State private var full = false
    @ObservedObject var m: Model
    private var cinema: Bool { full && m.embeddedURL != nil }
    private func toggleScreen() { NSApp.keyWindow?.toggleFullScreen(nil) }
    var body: some View {
        GeometryReader { bounds in
        ZStack(alignment:.topTrailing) {
        VStack {
            if m.connected {
                if !cinema { HStack {
                    Picker("Catalogue",selection:$m.kind) { ForEach(Kind.allCases,id:\.self) { Text($0.rawValue) } }.pickerStyle(.segmented)
                    TextField(m.useProfile ? "Recherche globale · Entrée" : "Recherche globale",text:$m.query).onSubmit { if m.useProfile { m.browse(global:true) } }
                    Button { m.logout() } label: { Label("Déconnexion",systemImage:"rectangle.portrait.and.arrow.right") }
                }
                }
                if !cinema { HStack(spacing:16) {
                    VStack(alignment:.leading) {
                    if m.useProfile {
                        if m.searching || m.selected != nil {
                            Button { m.query = ""; m.resetSection() } label: { Label("Catégories",systemImage:"chevron.left") }
                            Text(m.searching ? "Résultats de recherche" : m.selected?.name ?? "").font(.headline)
                        } else { Text("Catégories · " + m.kind.rawValue).font(.headline) }
                    }
                    if m.browsing { ProgressView("Chargement…") }
                    else if m.useProfile && m.selected == nil && !m.searching {
                        if m.groups.isEmpty { Text("Aucune catégorie disponible") }
                        List(m.groups) { group in Button(group.name) { m.selected = group; m.browse() }.buttonStyle(.plain).padding(.vertical,4) }
                    } else {
                    List(m.results) { row in Button { m.select(row) } label: {
                        HStack { if row.kind != .tv { Poster(url:row.artwork) }; VStack(alignment:.leading) { Text(row.title); Text(row.kind.rawValue + " · " + row.group).font(.caption).foregroundStyle(.secondary) } }
                    }.buttonStyle(.plain).padding(.vertical,4) }
                    }
                    }.scrollContentBackground(.hidden).frame(width:bounds.size.width / 2 - 32)
                    VStack {
                        if m.embeddedURL != nil { Color.clear.frame(height:bounds.size.height / 2 + 16) }
                        if !m.heading.isEmpty { Text(m.heading).font(.headline) }
                        if m.fetching { ProgressView("Chargement des épisodes…") }
                        if !m.seasons.isEmpty { HStack { Poster(url:m.children.first?.seasonArt ?? m.seriesCover); Picker("Saison",selection:Binding(get:{ m.season },set:{ m.changeSeason($0) })) { ForEach(m.seasons,id:\.self) { Text("Saison " + String($0)).tag($0) } } } }
                        if !m.children.isEmpty { List(m.children) { e in Button { m.select(e) } label: { HStack { Poster(url:e.artwork ?? m.seriesCover); Text(e.title) } }.buttonStyle(.plain).padding(.vertical,4) }.frame(maxHeight:180) }
                        if m.embeddedURL == nil && !m.fetching && m.heading.isEmpty { Text("Sélectionnez un média").foregroundStyle(.secondary) }
                        Spacer(minLength:0)
                    }.frame(minWidth:310,maxWidth:.infinity,maxHeight:.infinity)
                } }
            } else {
                Spacer(); Text("4431 IPTV").font(.largeTitle.bold())
                if m.loading { ProgressView("Chargement du catalogue…") }
                else {
                    VStack {
                        Picker("Mode",selection:$m.useProfile) {
                            Text("Compte Xtream").tag(true)
                            Text("Playlist M3U").tag(false)
                        }.pickerStyle(.segmented)
                        if m.useProfile {
                            TextField("Nom du profil (facultatif)",text:$m.profile.name)
                            TextField("Adresse du serveur, port éventuel inclus",text:$m.profile.server)
                            TextField("Nom d’utilisateur",text:$m.profile.username)
                            SecureField("Mot de passe",text:$m.profile.password)
                        } else { SecureField("URL get.php complète",text:$m.raw) }
                        Button { m.submit() } label: { Label("Connexion",systemImage:"arrow.right.circle.fill") }
                            .disabled(m.useProfile ? m.profile.server.isEmpty || m.profile.username.isEmpty || m.profile.password.isEmpty : m.raw.isEmpty)
                    }.frame(width:390)

                }
                if m.saved || m.loading { Button("Déconnexion et effacement") { m.logout() } }
                Spacer()
            }
            if !m.error.isEmpty { Text(m.error).foregroundStyle(.red) }
        }.padding(cinema ? 0 : 16).frame(maxWidth:.infinity,maxHeight:.infinity)
        if let url = m.embeddedURL {
            EmbeddedVideo(url:url,full:cinema,toggleScreen:toggleScreen).id(url)
                .frame(width:cinema ? bounds.size.width : bounds.size.width / 2,
                       height:cinema ? bounds.size.height : bounds.size.height / 2)
                .background(Color.black).clipShape(RoundedRectangle(cornerRadius:cinema ? 0 : 12))
                .padding(.top,cinema ? 0 : 70).padding(.trailing,cinema ? 0 : 16)
        }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(red:0.045,green:0.063,blue:0.14))
        }.ignoresSafeArea(edges:cinema ? .all : []).preferredColorScheme(.dark)
        .tint(Color(red:0.67,green:0.42,blue:1)).controlSize(.large).frame(minWidth:880,minHeight:560)
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didEnterFullScreenNotification)) { _ in
            full = true
        }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didExitFullScreenNotification)) { _ in full = false }
        .onChange(of:m.kind) { _ in m.query = ""; m.resetSection() }.onChange(of:m.query) { value in
            if !m.useProfile || (value.isEmpty && m.searching) { m.filter() }
        }
    }
}


private struct Poster: View {
    let url: URL?
    var body: some View {
        AsyncImage(url:url) { image in image.resizable().scaledToFit() } placeholder: {
            Image(systemName:"film").foregroundStyle(.secondary)
        }.frame(width:52,height:54)
    }
}
