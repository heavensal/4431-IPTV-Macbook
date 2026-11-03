import XCTest
@testable import Player
final class CatalogTests: XCTestCase {
    func testCatalog() throws {
        let p = try Provider("https://example.invalid/service/get.php?username=user&password=x%26y")
        XCTAssertEqual(p.pass,"x&y")
        XCTAssertEqual(p.api("get_series").path,"/service/player_api.php")
        var parser = Parser()
        _ = parser.line("#EXTINF:-1 group-title=\"Films, Europe\",Un été",base:p.source,id:0)
        let row = parser.line("/movie/a/b/1.mp4",base:p.source,id:0)
        XCTAssertEqual(row?.kind,.film); XCTAssertEqual(row?.title,"Un été")
        XCTAssertTrue(row?.needle.contains("ete") == true)
        XCTAssertThrowsError(try Provider("https://example.invalid/get.php"))
    }
}

extension CatalogTests {
    func testProfileAPI() async throws {
        let p = try Profile(name:"Salon",server:"http://example.invalid:8080/base/",username:"u",password:"x+/&").provider()
        var actions = [String]()
        let fetch: (URL) async throws -> Any = { url in
            XCTAssertEqual(url.path,"/base/player_api.php")
            XCTAssertEqual(url.port,8080)
            let query = URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "password" }?.value,"x+/&")
            let action = query.first { $0.name == "action" }?.value ?? "login"
            actions.append(action)
            switch action {
            case "login": return ["user_info":["auth":"1","allowed_output_formats":["m3u8"]]]
            case "get_live_categories": return [["category_id":"5","category_name":"Zone"],["category_id":2,"category_name":"Actu"]]
            case "get_live_streams": XCTAssertEqual(query.first { $0.name == "category_id" }?.value,"2"); return [["stream_id":7,"name":"Titre"]]
            case "get_series": return [["series_id":9,"name":"S"]]
            default: return [["stream_id":7,"name":"Titre"]]
            }
        }
        let ext = try await authenticate(p,fetch:fetch)
        let groups = try await categories(p,kind:.tv,fetch:fetch)
        XCTAssertEqual(groups.map(\.name),["Actu","Zone"])
        XCTAssertEqual(actions,["login","get_live_categories"])
        var entries = try await mediaRows(p,kind:.tv,category:groups[0],liveExt:ext,fetch:fetch)
        entries += try await mediaRows(p,kind:.film,category:nil,liveExt:ext,fetch:fetch)
        entries += try await mediaRows(p,kind:.series,category:nil,liveExt:ext,fetch:fetch)
        XCTAssertEqual(entries.map(\.kind),[.tv,.film,.series])
        XCTAssertTrue(entries[0].url!.absoluteString.contains("/base/live/u/x%2B%2F%26/7.m3u8"))
        XCTAssertEqual(entries[2].remote,9)
    }
}
extension CatalogTests {
    func testEpisodeURLs() async throws {
        let p = try Provider("https://example.invalid/get.php?username=u&password=p")
        let rows = try await episodes(p,1) { _ in
            ["episodes":["25":[["episode_num":1,"id":2,"direct_source":"https://media.invalid/file.mkv"],["episode_num":2,"id":3,"container_extension":"mkv","direct_source":""]]]]
        }
        XCTAssertEqual(rows.map(\.season),[25,25])
        XCTAssertEqual(rows[0].url?.host,"media.invalid")
        XCTAssertEqual(rows[1].url?.path,"/series/u/p/3.mkv")
    }
}
extension CatalogTests {
    func testTrackIDsAndSeasonArtwork() async throws {
        XCTAssertEqual(MediaTrack.list([-1,7,9],["Off","FR","EN"]).map(\.id),[-1,7,9])
        let provider = try Provider("https://example.invalid/get.php?username=u&password=p")
        let items = try await episodes(provider,1) { _ in
            ["seasons":[["season_number":2,"cover":"https://art.invalid/season.jpg"]],
             "episodes":["2":[["id":7,"info":["movie_image":"https://art.invalid/still.jpg"]]]]]
        }
        XCTAssertEqual(items.first?.seasonArt?.lastPathComponent,"season.jpg")
        XCTAssertEqual(items.first?.artwork?.lastPathComponent,"still.jpg")
    }
}
