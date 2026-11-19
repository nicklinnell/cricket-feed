import Foundation
@testable import CricketFeed

// Inline fixtures only. Tests never call ESPN.

func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

func match(_ id: String, teams: [String] = [], live: Bool = true) -> Match {
    Match(
        id: id, leagueID: "1", league: "Test", title: id, detail: "",
        state: live ? "in" : "post", stateLabel: "", summary: "", fullDescription: "",
        period: 1, sides: teams.map { Match.Side(id: $0, name: "Team \($0)", short: $0, score: "") }
    )
}

// One play-by-play ball. Batter and bowler figures are optional.
func ball(
    over: Int, runs: Int = 0, type: String? = nil, wide: Int = 0, noBall: Int = 0,
    complete: Bool = false, out: String? = nil,
    striker: String = "A", nonStriker: String = "B",
    innings: String = "null", team: String = "England"
) -> String {
    let dismissal = out.map { #"{"dismissal":true,"batsman":{"athlete":{"id":"\#($0)"}}}"# } ?? "null"
    return """
    {"scoreValue":\(runs),"playType":{"description":"\(type ?? "run")"},
     "over":{"number":\(over),"wide":\(wide),"noBall":\(noBall),"complete":\(complete)},
     "innings":\(innings),"dismissal":\(dismissal),"team":{"id":"1","displayName":"\(team)"},
     "batsman":{"athlete":{"id":"\(striker)","displayName":"Batter \(striker)"},"totalRuns":10,"faced":12},
     "otherBatsman":{"athlete":{"id":"\(nonStriker)","displayName":"Batter \(nonStriker)"},"totalRuns":5,"faced":8},
     "bowler":{"athlete":{"id":"X","displayName":"Bowler X"},"balls":13,"conceded":20,"wickets":1}}
    """
}

func items(_ balls: [String]) throws -> [PBPItem] {
    try decode([PBPItem].self, "[" + balls.joined(separator: ",") + "]")
}

// A UserDefaults suite thrown away after use, so tests never touch the user's settings.
final class TempDefaults {
    let name = "CricketFeedTests-\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: name)!
    deinit { UserDefaults().removePersistentDomain(forName: name) }
}
