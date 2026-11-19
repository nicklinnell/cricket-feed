import Foundation
import Testing
@testable import CricketFeed

// A match with scored sides: [(team ID, score text)].
private func scored(_ sides: [(String, String)], id: String = "m1", state: String = "in", summary: String = "") -> Match {
    Match(id: id, leagueID: "1", league: "Test", title: "England v Australia", detail: "",
          state: state, stateLabel: "", summary: summary, fullDescription: "", period: 1,
          sides: sides.map { Match.Side(id: $0.0, name: $0.0 == "1" ? "England" : "Australia", short: "", score: $0.1) })
}

private func detail(period: Int = 1, _ batters: [(String, Int)]) -> LiveDetail {
    var d = LiveDetail(overs: [])
    d.period = period
    d.battingTeam = "England"
    d.batters = batters.map { BatterLine(id: $0.0, name: "Batter \($0.0)", runs: $0.1, balls: 60, fours: 0, sixes: 0) }
    return d
}

@Suite struct ScoreTextParsing {
    @Test(arguments: [
        ("", []),
        ("137", [InningsScore(runs: 137, wickets: 10)]),
        ("64/5 (25 ov)", [InningsScore(runs: 64, wickets: 5)]),
        ("98 & 309/9 (93 ov)", [InningsScore(runs: 98, wickets: 10), InningsScore(runs: 309, wickets: 9)]),
        ("120 (17.3/20 ov, target 149)", [InningsScore(runs: 120, wickets: 10)]),
        ("11/0 (0.5/10 ov, target 97)", [InningsScore(runs: 11, wickets: 0)]),
        ("450/8d & 12/1", [InningsScore(runs: 450, wickets: 8), InningsScore(runs: 12, wickets: 1)]),
        ("450/8 dec", [InningsScore(runs: 450, wickets: 8)]),
    ])
    func readsFeedScores(text: String, expected: [InningsScore]) {
        #expect(parseInnings(text) == expected)
    }

    @Test(arguments: ["Yet to bat", "12/11", "1/2/3", "/4"])
    func oddTextReadsAsNil(text: String) {
        #expect(parseInnings(text) == nil)
    }
}

@Suite struct MilestoneTracking {
    var tracker = MilestoneTracker()

    mutating func step(_ m: Match, _ details: [String: LiveDetail] = [:], allowed: Bool = true) -> [String] {
        tracker.update(matches: [m], details: details) { _ in allowed }.map(\.body)
    }

    @Test mutating func firstSightIsSilent() {
        #expect(step(scored([("1", "245/6 (60 ov)")]), ["m1": detail([("A", 120)])]) == [])
    }

    @Test mutating func wicketFiresOnce() {
        _ = step(scored([("1", "40/0")]))
        #expect(step(scored([("1", "42/1")])) == ["Wicket: England 42/1"])
        #expect(step(scored([("1", "44/1")])) == [])
    }

    @Test mutating func flickerDoesNotRepeat() {
        _ = step(scored([("1", "40/0")]))
        _ = step(scored([("1", "42/1")]))
        // Feed blanks out, then a correction takes the wicket back, then it returns.
        #expect(step(scored([("1", "")])) == [])
        #expect(step(scored([("1", "42/0")])) == [])
        #expect(step(scored([("1", "42/1")])) == [])
    }

    @Test mutating func gapGroupsWicketsIntoOneAlert() {
        _ = step(scored([("1", "40/0")]))
        #expect(step(scored([("1", "230/3")])) == ["3 wickets: England 230/3"])
    }

    @Test mutating func hundredsWithoutWicket() {
        _ = step(scored([("1", "95/2")]))
        #expect(step(scored([("1", "101/2")])) == ["England pass 100: 101/2"])
        _ = step(scored([("1", "180/2")]))
        // Jumping two landmarks names the highest.
        #expect(step(scored([("1", "310/2")])) == ["England pass 300: 310/2"])
    }

    @Test mutating func allOut() {
        _ = step(scored([("1", "130/9 (40 ov)")]))
        #expect(step(scored([("1", "137")])) == ["England all out for 137"])
    }

    @Test mutating func secondInningsCountsAfresh() {
        _ = step(scored([("1", "98")]))
        #expect(step(scored([("1", "98 & 5/1 (3 ov)")])) == ["Wicket: England 5/1"])
    }

    @Test mutating func bothSidesInOneAlert() {
        _ = step(scored([("1", "300"), ("2", "99/0")]))
        let alerts = tracker.update(matches: [scored([("1", "300"), ("2", "104/1")])], details: [:]) { _ in true }
        #expect(alerts == [MilestoneAlert(matchID: "m1", title: "England v Australia", body: "Wicket: Australia 104/1")])
    }

    @Test mutating func batterFiftyAndHundred() {
        _ = step(scored([("1", "100/1")]), ["m1": detail([("A", 48), ("B", 30)])])
        #expect(step(scored([("1", "104/1")]), ["m1": detail([("A", 52), ("B", 30)])]) == ["Batter A (England) reaches 50"])
        #expect(step(scored([("1", "104/1")]), ["m1": detail([("A", 52), ("B", 30)])]) == [])
        #expect(step(scored([("1", "160/1")]), ["m1": detail([("A", 101), ("B", 33)])]) == ["Batter A (England) reaches 100"])
    }

    @Test mutating func firstDetailIsSilent() {
        // Details only arrive once the match is watched; the scores below were seen already.
        _ = step(scored([("1", "100/1")]))
        #expect(step(scored([("1", "100/1")]), ["m1": detail([("A", 75)])]) == [])
        #expect(step(scored([("1", "100/1")]), ["m1": detail(period: 2, [("A", 60)])]) == [])
    }

    @Test mutating func resultOnlyWhenSeenFinishing() {
        #expect(step(scored([("1", "137")], state: "post", summary: "Australia won by 9 wkts")) == [])
        var t = MilestoneTracker()
        _ = t.update(matches: [scored([("1", "137")])], details: [:]) { _ in true }
        let done = t.update(matches: [scored([("1", "137")], state: "post", summary: "England won by 28 runs")], details: [:]) { _ in true }
        #expect(done.map(\.body) == ["England won by 28 runs"])
    }

    @Test mutating func blockedMatchesStayTracked() {
        _ = step(scored([("1", "40/0")]))
        #expect(step(scored([("1", "42/1")]), allowed: false) == [])
        // Turning alerts on later doesn't send old news.
        #expect(step(scored([("1", "42/1")])) == [])
    }
}

@MainActor
final class RecordingNotifier: MilestoneNotifier {
    var sent: [MilestoneAlert] = []
    var permissionRequests = 0
    func requestPermission() { permissionRequests += 1 }
    func send(_ alert: MilestoneAlert) { sent.append(alert) }
}

@MainActor @Suite struct MilestoneStore {
    let temp = TempDefaults()

    @Test func onByDefaultAndRemembered() {
        let s = ScoreStore(defaults: temp.defaults)
        #expect(s.notifyMilestones)
        s.notifyMilestones = false
        #expect(!ScoreStore(defaults: temp.defaults).notifyMilestones)
    }

    @Test func turningOnAsksPermission() {
        let s = ScoreStore(defaults: temp.defaults)
        let n = RecordingNotifier()
        s.notifier = n
        s.notifyMilestones = false
        #expect(n.permissionRequests == 0)
        s.notifyMilestones = true
        #expect(n.permissionRequests == 1)
    }

    @Test func onlyFavouriteUnstoppedMatchesWithSettingOn() {
        let s = ScoreStore(defaults: temp.defaults)
        let fav = scored([("1", "")])
        let other = scored([("9", "")], id: "m2")
        #expect(!s.alertsAllowed(for: fav))
        s.favourites = ["1": "England"]
        #expect(s.alertsAllowed(for: fav))
        #expect(!s.alertsAllowed(for: other))
        s.hidden = ["m1"]
        #expect(!s.alertsAllowed(for: fav))
        s.hidden = []
        s.notifyMilestones = false
        #expect(!s.alertsAllowed(for: fav))
    }
}

extension NetworkTests {
    @MainActor @Suite struct MilestoneRefresh {
        let temp = TempDefaults()

        private func feed(_ score: String) -> String {
            """
            {"scores":[{"leagues":[{"id":"1","name":"Test"}],"events":[{"id":"m1","name":"England v Australia",
             "competitions":[{"status":{"type":{"state":"post"}},"competitors":[
               {"score":"\(score)","team":{"id":"1","displayName":"England"}},
               {"score":"","team":{"id":"2","displayName":"Australia"}}]}]}]}]}
            """
        }

        @Test func refreshSendsAlerts() async {
            StubURLProtocol.reset()
            let s = ScoreStore(defaults: temp.defaults)
            let n = RecordingNotifier()
            s.notifier = n
            s.favourites = ["1": "England"]
            StubURLProtocol.on(prefix: scorePanelURL.absoluteString, json: feed("40/0"))
            await s.refresh()
            #expect(n.sent.isEmpty)
            StubURLProtocol.on(prefix: scorePanelURL.absoluteString, json: feed("42/1"))
            await s.refresh()
            #expect(n.sent == [MilestoneAlert(matchID: "m1", title: "England v Australia", body: "Wicket: England 42/1")])
        }
    }
}
