import Foundation

enum Kind: String, CaseIterable { case tv = "TV", film = "Films", series = "Séries" }
struct Entry: Identifiable {
    let id: Int
    let title: String
    let kind: Kind
    let url: URL?
    var remote: Int? = nil
    var season: Int? = nil
    var artwork: URL? = nil
    var seasonArt: URL? = nil
    var group = ""
    var needle: String { (title + " " + group).folding(options: [.caseInsensitive,.diacriticInsensitive], locale: .current) }
}
func artwork(_ row: [String:Any]?, _ keys: [String]) -> URL? {
    for key in keys {
        if let raw = row?[key] as? String, let url = URL(string:raw), url.host != nil,
           ["http","https"].contains(url.scheme?.lowercased() ?? "") { return url }
    }
    return nil
}
enum Failure: LocalizedError {
    case address, network, empty, secrets, episodes
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .address: return "Saisissez une URL HTTP ou HTTPS get.php avec username et password."
        case .http(let status):
            if [401,403].contains(status) { return "Le fournisseur a refusé la demande (HTTP \(status)). Vérifiez l’URL et les droits de votre abonnement." }
            return "Le fournisseur a répondu HTTP \(status). Vérifiez l’adresse du serveur."
        case .network: return "Serveur inaccessible ou accès refusé. Vérifiez l’adresse et réessayez."
        case .empty: return "La playlist ne contient aucun média lisible."
        case .secrets: return "Le trousseau est inaccessible. Vérifiez son déverrouillage."
        case .episodes: return "Impossible de récupérer les épisodes de cette série."
        }
    }
}
struct Provider {
    let source: URL
    let user: String, pass: String
    init(_ raw: String) throws {
        guard let c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http","https"].contains(c.scheme?.lowercased() ?? ""), c.host != nil, let url = c.url,
              url.lastPathComponent == "get.php",
              let u = c.queryItems?.first(where: {$0.name == "username"})?.value, !u.isEmpty,
              let p = c.queryItems?.first(where: {$0.name == "password"})?.value, !p.isEmpty else { throw Failure.address }
        source = url; user = u; pass = p
    }
    func stream(_ folder: String, id: Int, ext: String) -> URL? {
            var c = URLComponents(url:source.deletingLastPathComponent(),resolvingAgainstBaseURL:false)!
            c.query = nil
            let parts = [folder,user,pass,"\(id).\(ext)"]
            c.percentEncodedPath = c.percentEncodedPath.trimmingCharacters(in:CharacterSet(charactersIn:"/")).isEmpty ? "/" : c.percentEncodedPath.trimmingTrailingSlash + "/"
            c.percentEncodedPath += parts.map { $0.addingPercentEncoding(withAllowedCharacters:.alphanumerics.union(CharacterSet(charactersIn:"-._~"))) ?? "" }.joined(separator:"/")
        return c.url
    }
    func api(_ action: String?, id: Int? = nil, category: String? = nil) -> URL {
        var c = URLComponents(url: source.deletingLastPathComponent().appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name:"username",value:user),URLQueryItem(name:"password",value:pass)]
        if let action { c.queryItems?.append(.init(name:"action",value:action)) }
        if let category { c.queryItems?.append(.init(name:"category_id",value:category)) }
        if let id { c.queryItems?.append(URLQueryItem(name:"series_id",value:String(id))) }
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%2B")
        return c.url!
    }
}
let network: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
    config.timeoutIntervalForRequest = 25
    return URLSession(configuration: config)
}()
func checked(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { throw Failure.network }
    guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
}
struct Parser {
    var title = "", group = ""
    var logo: URL?
    mutating func line(_ s: String, base: URL, id: Int) -> Entry? {
        if s.hasPrefix("#EXTINF:") {
            var quoted = false
            title = ""
            for i in s.indices {
                if s[i] == "\"" { quoted.toggle() }
                if s[i] == ",", !quoted { title = String(s[s.index(after:i)...]); break }
            }
            logo = artwork(["logo":s.components(separatedBy:"tvg-logo=\"").dropFirst().first?.components(separatedBy:"\"").first ?? ""],["logo"])
            group = s.components(separatedBy:"group-title=\"").dropFirst().first?.components(separatedBy:"\"").first ?? ""
            return nil
        }
        guard !s.isEmpty, !s.hasPrefix("#"), (!title.isEmpty || s.hasPrefix("http://") || s.hasPrefix("https://")), let url = URL(string:s,relativeTo:base)?.absoluteURL, ["http","https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        defer { title = ""; group = ""; logo = nil }
        let path = url.path.lowercased(), g = group.lowercased()
        let kind: Kind = path.contains("/series/") || g.contains("série") || g.contains("series") ? .series :
            path.contains("/movie/") || g.contains("film") || g.contains("vod") ? .film : .tv
        return Entry(id:id,title:title.isEmpty ? "Média \(id+1)" : title,kind:kind,url:url,artwork:logo,group:group)
    }
}
func playlist(_ p: Provider) async throws -> [Entry] {
    let (bytes,response) = try await network.bytes(from:p.source)
    try checked(response)
    var items = [Entry](), parser = Parser()
    for try await line in bytes.lines {
        try Task.checkCancellation()
        if let item = parser.line(line.trimmingCharacters(in:.whitespacesAndNewlines),base:p.source,id:items.count) { items.append(item) }
    }
    return items
}
func json(_ url: URL) async throws -> Any {
    let (data,r) = try await network.data(from:url); try checked(r)
    guard let value = try? JSONSerialization.jsonObject(with:data) else { throw XtreamError.response }; return value
}
func number(_ x: Any?) -> Int? { if let n = x as? Int { return n }; return (x as? String).flatMap(Int.init) }
func shows(_ p: Provider) async throws -> [Entry] {
    guard let rows = try await json(p.api("get_series")) as? [[String:Any]] else { throw Failure.episodes }
    return rows.compactMap { row in
        guard let id = number(row["series_id"]), id >= 0, let name = row["name"] as? String else { return nil }
        return Entry(id: -1-id,title:name,kind:.series,url:nil,remote:id,artwork:artwork(row,["cover","stream_icon"]))
    }
}
func episodes(_ p: Provider, _ id: Int, fetch: (URL) async throws -> Any = json) async throws -> [Entry] {
    guard let obj = try await fetch(p.api("get_series_info",id:id)) as? [String:Any] else { throw Failure.episodes }
    let seasons: [String:[[String:Any]]]
    if let dict = obj["episodes"] as? [String:[[String:Any]]] { seasons = dict }
    else if let list = obj["episodes"] as? [[[String:Any]]] { seasons = Dictionary(uniqueKeysWithValues:list.enumerated().map { (String($0.offset),$0.element) }) }
    else { throw Failure.episodes }
    var covers = [Int:URL]()
    let seriesCover = artwork(obj["info"] as? [String:Any], ["cover","cover_big"])
    for row in obj["seasons"] as? [[String:Any]] ?? [] {
        if let n = number(row["season_number"]) { covers[n] = artwork(row,["cover_big","cover"]) }
    }
    var items = [Entry]()
    for season in seasons.keys.sorted(by:{ $0.localizedStandardCompare($1) == .orderedAscending }) {
        for row in (seasons[season] ?? []).sorted(by:{ (number($0["episode_num"]) ?? 0) < (number($1["episode_num"]) ?? 0) }) {
            guard let eid = number(row["id"]) else { continue }
            let ext = row["container_extension"] as? String ?? "mp4"
            let direct = (row["direct_source"] as? String).flatMap(URL.init(string:))
            let url = ["http","https"].contains(direct?.scheme?.lowercased() ?? "") && direct?.host != nil ? direct : p.stream("series",id:eid,ext:ext.isEmpty ? "mp4" : ext)
            let n = number(row["season"]) ?? Int(season) ?? 0
            let cover = covers[n] ?? seriesCover
            let still = artwork(row["info"] as? [String:Any],["movie_image","cover_big","cover"]) ?? artwork(row,["movie_image","cover"])
            items.append(Entry(id:eid,title:"S\(number(row["season"]) ?? Int(season) ?? 0) E\(number(row["episode_num"]) ?? 0) · \(row["title"] as? String ?? "Épisode")",kind:.series,url:url,season:n,artwork:still ?? cover,seasonArt:cover))
        }
    }
    guard !items.isEmpty else { throw Failure.episodes }; return items
}
private extension String { var trimmingTrailingSlash: String { hasSuffix("/") ? String(dropLast()) : self } }

func connectionMessage(_ error: Error) -> String {
    if let failure = error as? XtreamError { return failure.localizedDescription }
    if let failure = error as? Failure { return failure.localizedDescription }
    guard let urlError = error as? URLError else { return Failure.network.localizedDescription }
    switch urlError.code {
    case .cannotFindHost, .dnsLookupFailed: return "Adresse du serveur introuvable (DNS). Vérifiez le nom de domaine dans l’URL."
    case .timedOut: return "Le serveur n’a pas répondu à temps. Réessayez la connexion."
    case .cannotConnectToHost: return "Connexion au serveur impossible. Vérifiez l’adresse, le port et la disponibilité du service."
    case .notConnectedToInternet: return "Le Mac n’est pas connecté à Internet."
    case .secureConnectionFailed, .serverCertificateUntrusted: return "La connexion sécurisée au fournisseur a échoué. Vérifiez son certificat et l’adresse HTTPS."
    default: return "Échec réseau (code \(urlError.errorCode))."
    }
}
