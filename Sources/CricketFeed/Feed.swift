import Foundation

// Unofficial ESPN feed (ESPN owns Cricinfo). No key needed. May change without notice.
let scorePanelURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/cricket/scorepanel")!

// MARK: - Raw JSON shapes (only the fields we use)

struct ScorePanel: Decodable {
    let scores: [LeagueBlock]
}

struct LeagueBlock: Decodable {
    let leagues: [League]?
    let events: [Event]?
}

struct League: Decodable {
    let id: String
    let name: String?
}

struct Event: Decodable {
    let id: String
    let name: String?
    let description: String?
    let status: Status?
    let competitions: [Competition]?
}

struct Competition: Decodable {
    let description: String?
    let status: Status?
    let competitors: [Competitor]?
}

struct Status: Decodable {
    let summary: String?
    let period: Int?
    let type: StatusType?
}

struct StatusType: Decodable {
    let state: String?       // "pre", "in", "post"
    let description: String? // e.g. "Live", "Result", "Stumps"
}

struct Competitor: Decodable {
    let score: String?
    let team: Team?
}

struct Team: Decodable {
    let id: String?
    let displayName: String?
    let abbreviation: String?
    let logo: String?        // flag for national sides, crest for clubs

    private enum CodingKeys: String, CodingKey { case id, displayName, abbreviation, logo }

    // The ID comes as text today. Accept a number too, and never let an odd ID
    // fail the whole feed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .id)).flatMap { $0.map(String.init) }
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        abbreviation = try c.decodeIfPresent(String.self, forKey: .abbreviation)
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
    }
}

// MARK: - What the UI shows

struct Match: Identifiable, Hashable {
    struct Side: Hashable {
        var id: String = ""      // ESPN team ID, same in every competition
        let name: String
        let short: String
        let score: String
        var logo: URL? = nil
    }

    let id: String
    let leagueID: String
    let league: String
    let title: String
    let detail: String
    let state: String
    let stateLabel: String
    let summary: String
    let fullDescription: String
    let period: Int
    let sides: [Side]

    var isLive: Bool { state == "in" }

    var cricinfoURL: URL {
        URL(string: "https://www.espncricinfo.com/ci/engine/match/\(id).html")!
    }
}

enum FeedError: LocalizedError {
    case badStatus(Int)
    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "Feed returned HTTP \(code)"
        }
    }
}

func fetchMatches() async throws -> [Match] {
    var request = URLRequest(url: scorePanelURL)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 20
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        throw FeedError.badStatus(http.statusCode)
    }
    return try parseMatches(data)
}

// Feed JSON -> matches. Kept apart from the network call so tests can feed it fixtures.
func parseMatches(_ data: Data) throws -> [Match] {
    let panel = try JSONDecoder().decode(ScorePanel.self, from: data)

    var result: [Match] = []
    for block in panel.scores {
        let leagueName = block.leagues?.first?.name ?? ""
        let leagueID = block.leagues?.first?.id ?? ""
        for event in block.events ?? [] {
            let comp = event.competitions?.first
            let status = comp?.status ?? event.status
            let sides = (comp?.competitors ?? []).map { c in
                Match.Side(
                    id: c.team?.id ?? "",
                    name: c.team?.displayName ?? "?",
                    short: c.team?.abbreviation ?? "?",
                    score: c.score ?? "",
                    logo: c.team?.logo.flatMap(URL.init(string:))
                )
            }
            result.append(Match(
                id: event.id,
                leagueID: leagueID,
                league: leagueName,
                title: event.name ?? sides.map(\.name).joined(separator: " v "),
                detail: comp?.description ?? "",
                state: status?.type?.state ?? "",
                stateLabel: status?.type?.description ?? "",
                summary: status?.summary ?? "",
                fullDescription: event.description ?? "",
                period: status?.period ?? 1,
                sides: sides
            ))
        }
    }
    return result
}
