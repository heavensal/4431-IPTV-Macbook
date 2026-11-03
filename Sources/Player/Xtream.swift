import Foundation

struct Profile: Codable {
    var name = "", server = "", username = "", password = ""
    func provider() throws -> Provider {
        let address = server.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !address.isEmpty, var c = URLComponents(string:address.contains("://") ? address : "https://" + address),
              ["https","http"].contains(c.scheme?.lowercased() ?? ""), let host = c.host, !host.isEmpty,
              c.query == nil, c.fragment == nil, c.user == nil, c.password == nil, !username.isEmpty, !password.isEmpty else { throw XtreamError.fields }
        if !c.path.hasSuffix("/") { c.path += "/" }
        c.path += "get.php"
        c.queryItems = [.init(name:"username",value:username),.init(name:"password",value:password)]
        guard let raw = c.string else { throw XtreamError.fields }
        return try Provider(raw)
    }
}
enum XtreamError: LocalizedError {
    case fields, denied, response
    var errorDescription: String? {
        switch self {
        case .fields: return "Vérifiez le serveur (avec son port éventuel), le nom d’utilisateur et le mot de passe."
        case .denied: return "Le serveur Xtream a refusé la connexion ou le compte est inactif."
        case .response: return "Réponse Xtream inattendue. Vérifiez l’adresse du serveur utilisée dans Smarters."
        }
    }
}
func authenticate(_ p: Provider, fetch: (URL) async throws -> Any = json) async throws -> String {
    guard let reply = try await fetch(p.api(nil)) as? [String:Any], let info = reply["user_info"] as? [String:Any] else { throw XtreamError.response }
    guard number(info["auth"]) == 1, (info["status"] as? String ?? "Active").lowercased() == "active" else { throw XtreamError.denied }
    let formats = info["allowed_output_formats"] as? [String] ?? []
    let liveExt = formats.isEmpty || formats.contains("m3u8") ? "m3u8" : "ts"
    return liveExt
}

struct Category: Identifiable {
    let id: String
    let name: String
}

func categories(_ p: Provider, kind: Kind, fetch: (URL) async throws -> Any = json) async throws -> [Category] {
    let action: String
    switch kind {
    case .tv: action = "get_live_categories"
    case .film: action = "get_vod_categories"
    case .series: action = "get_series_categories"
    }
    guard let rows = try await fetch(p.api(action)) as? [[String:Any]] else { throw XtreamError.response }
    var seen = Set<String>()
    return rows.compactMap { row -> Category? in
        guard let id = number(row["category_id"]).map(String.init), seen.insert(id).inserted,
              let name = row["category_name"] as? String else { return nil }
        return Category(id:id,name:name)
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

func mediaRows(_ p: Provider, kind: Kind, category: Category?, liveExt: String, matching term: String = "", offset: Int = 0, fetch: (URL) async throws -> Any = json) async throws -> [Entry] {
    let action: String
    switch kind {
    case .tv: action = "get_live_streams"
    case .film: action = "get_vod_streams"
    case .series: action = "get_series"
    }
    guard let rows = try await fetch(p.api(action,category:category?.id)) as? [[String:Any]] else { throw XtreamError.response }
    var entries = [Entry]()
    for row in rows {
        try Task.checkCancellation()
        if let category, let actual = number(row["category_id"]), String(actual) != category.id { continue }
        guard let title = row["name"] as? String, let id = number(row[kind == .series ? "series_id" : "stream_id"]) else { continue }
        if !term.isEmpty, title.range(of:term, options:[.caseInsensitive,.diacriticInsensitive]) == nil { continue }
        let ext = kind == .tv ? liveExt : row["container_extension"] as? String ?? "mp4"
        let url = kind == .series ? nil : p.stream(kind == .tv ? "live" : "movie", id:id, ext:ext)
        entries.append(Entry(id:offset + entries.count,title:title,kind:kind,url:url,remote:kind == .series ? id : nil,artwork:artwork(row,["cover","stream_icon","movie_image"]),group:category?.name ?? ""))
    }
    return entries.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}
