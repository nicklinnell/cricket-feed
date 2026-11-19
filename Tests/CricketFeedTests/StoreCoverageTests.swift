import Foundation
import Testing
@testable import CricketFeed

// MARK: - Helpers for this file

private let panelPrefix = "https://site.api.espn.com/apis/site/v2/sports/cricket/scorepanel"

private func pbpPrefix(_ id: String, period: Int = 1) -> String {
    "https://site.web.api.espn.com/apis/site/v2/sports/cricket/1/playbyplay?event=\(id)&period=\(period)&"
}

// One scorepanel event in league "1".
private func event(_ id: String, state: String = "in", period: Int = 1, teams: [String] = ["10", "20"]) -> String {
    let comps = teams.map { #"{"score":"100/2","team":{"id":"\#($0)","displayName":"Team \#($0)","abbreviation":"\#($0)"}}"# }
    return """
    {"id":"\(id)","name":"\(id)","competitions":[{"status":{"period":\(period),"type":{"state":"\(state)"}},
     "competitors":[\(comps.joined(separator: ","))]}]}
    """
}

private func panel(_ events: [String]) -> String {
    #"{"scores":[{"leagues":[{"id":"1","name":"Test"}],"events":["# + events.joined(separator: ",") + "]}]}"
}

// A play-by-play page with one ball: batters A (12 balls faced) and B, so the
// fetched order is [A, B].
private func pbp(striker: String = "A", nonStriker: String = "B") -> String {
    #"{"commentary":{"pageCount":1,"items":["# + ball(over: 1, runs: 1, striker: striker, nonStriker: nonStriker) + "]}}"
}

private func batter(_ id: String) -> BatterLine {
    BatterLine(id: id, name: "Batter \(id)", runs: 0, balls: 0, fours: 0, sixes: 0)
}

private func seeded(period: Int = 1, batters: [String] = [], chase: String = "old") -> LiveDetail {
    var d = LiveDetail(overs: [])
    d.chase = chase
    d.period = period
    d.batters = batters.map(batter)
    return d
}

private func pbpRequests(_ id: String) -> [URL] {
    StubURLProtocol.requests.filter { $0.absoluteString.contains("playbyplay") && $0.absoluteString.contains("event=\(id)&") }
}

private func panelRequests() -> Int {
    StubURLProtocol.requests.filter { $0.absoluteString.hasPrefix(panelPrefix) }.count
}

@MainActor
private func waitUntil(_ timeout: TimeInterval = 5, _ cond: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !cond() {
        if Date() > end { return false }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return true
}

// MARK: - No network

@MainActor @Suite struct StoreState {
    let temp = TempDefaults()

    @Test func toggleFavouriteAddsThenRemovesByID() {
        let s = ScoreStore(defaults: temp.defaults)
        let eng = TeamOption(id: "1", name: "England")
        s.toggleFavourite(eng)
        #expect(s.favourites == ["1": "England"])
        s.toggleFavourite(TeamOption(id: "2", name: "India"))
        #expect(s.favourites == ["1": "England", "2": "India"])
        // Removal goes by ID, whatever the name now says.
        s.toggleFavourite(TeamOption(id: "1", name: "Renamed"))
        #expect(s.favourites == ["2": "India"])
    }

    @Test func followingAnythingAndAutoWatchingTeams() {
        let s = ScoreStore(defaults: temp.defaults)
        #expect(!s.autoWatchingTeams)
        #expect(!s.followingAnything)
        s.favourites = ["1": "England"]
        #expect(s.autoWatchingTeams)
        #expect(s.followingAnything)
        s.autoWatch = false
        #expect(!s.autoWatchingTeams)
        #expect(!s.followingAnything)
        s.watched = ["m1"]
        #expect(s.followingAnything)
    }

    @Test func toggleStatsOpensAndCloses() {
        let s = ScoreStore(defaults: temp.defaults)
        s.toggleStats(match("m1"))
        #expect(s.statsOpen == ["m1"])
        s.toggleStats(match("m1"))
        #expect(s.statsOpen.isEmpty)
    }
}

// MARK: - Network

extension NetworkTests {
    @MainActor @Suite struct StoreRefresh {
        let temp = TempDefaults()

        @Test func refreshSuccessFillsMatchesAndClearsError() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1"), event("m2", state: "post")]))
            let s = ScoreStore(defaults: temp.defaults)
            s.error = "stale"
            await s.refresh()
            #expect(s.matches.map(\.id) == ["m1", "m2"])
            #expect(s.error == nil)
            #expect(s.lastUpdated != nil)
        }

        @Test func refreshFailureSetsErrorAndKeepsOldData() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1")]))
            let s = ScoreStore(defaults: temp.defaults)
            await s.refresh()
            let when = s.lastUpdated
            #expect(when != nil)

            StubURLProtocol.on(prefix: panelPrefix, status: 500, json: "{}")
            await s.refresh()
            #expect(s.error == "Feed returned HTTP 500")
            #expect(s.matches.map(\.id) == ["m1"])
            #expect(s.lastUpdated == when)

            // Next good refresh clears the error.
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1")]))
            await s.refresh()
            #expect(s.error == nil)
        }

        // Only watched live matches get ball-by-ball. Others' old detail is dropped.
        @Test func detailsOnlyForLiveWatchedMatches() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("live"), event("unwatched"), event("done", state: "post")]))
            for id in ["live", "unwatched", "done"] { StubURLProtocol.on(prefix: pbpPrefix(id), json: pbp()) }
            let s = ScoreStore(defaults: temp.defaults)
            s.watched = ["live", "done"]
            s.details = ["unwatched": seeded(), "done": seeded()]
            await s.refresh()
            #expect(pbpRequests("live").count == 1)
            #expect(pbpRequests("unwatched").isEmpty)
            #expect(pbpRequests("done").isEmpty)
            #expect(Set(s.details.keys) == ["live"])
            #expect(s.details["live"]?.batters.map(\.id) == ["A", "B"])
            #expect(s.details["live"]?.period == 1)
        }

        @Test func failedDetailFetchKeepsOldDetailInSameInnings() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1")]))
            // No play-by-play route, so the fetch fails.
            let s = ScoreStore(defaults: temp.defaults)
            s.watched = ["m1"]
            s.details = ["m1": seeded()]
            await s.refresh()
            #expect(pbpRequests("m1").count == 1)
            #expect(s.details["m1"]?.chase == "old")
            #expect(s.error == nil)
        }

        @Test func newInningsDropsOldDetailEvenIfFetchFails() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1", period: 2)]))
            let s = ScoreStore(defaults: temp.defaults)
            s.watched = ["m1"]
            s.details = ["m1": seeded(period: 1)]
            await s.refresh()
            #expect(pbpRequests("m1").count == 1)
            #expect(s.details["m1"] == nil)
        }

        @Test func freshDetailReplacesOldOne() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1")]))
            StubURLProtocol.on(prefix: pbpPrefix("m1"), json: pbp())
            let s = ScoreStore(defaults: temp.defaults)
            s.watched = ["m1"]
            s.details = ["m1": seeded(batters: ["A", "B"])]
            await s.refresh()
            #expect(s.details["m1"]?.chase == nil)
            #expect(s.details["m1"]?.overs.count == 1)
            #expect(s.details["m1"]?.batters.map(\.id) == ["A", "B"])
        }

        // Fetched order is [A, B]; the old rows win.
        @Test func battersKeepTheirPreviousRows() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1")]))
            StubURLProtocol.on(prefix: pbpPrefix("m1"), json: pbp())
            let s = ScoreStore(defaults: temp.defaults)
            s.watched = ["m1"]
            s.details = ["m1": seeded(batters: ["B", "A"])]
            await s.refresh()
            #expect(s.details["m1"]?.batters.map(\.id) == ["B", "A"])
        }

        // Z is out and A is new: A takes the row after B, who stayed.
        @Test func newBatterGoesAfterTheOneWhoStayed() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1")]))
            StubURLProtocol.on(prefix: pbpPrefix("m1"), json: pbp())
            let s = ScoreStore(defaults: temp.defaults)
            s.watched = ["m1"]
            s.details = ["m1": seeded(batters: ["B", "Z"])]
            await s.refresh()
            #expect(s.details["m1"]?.batters.map(\.id) == ["B", "A"])
        }

        // Two new batters tie on rank, so they keep the fetched order.
        @Test func twoNewBattersKeepFetchedOrder() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1")]))
            StubURLProtocol.on(prefix: pbpPrefix("m1"), json: pbp())
            let s = ScoreStore(defaults: temp.defaults)
            s.watched = ["m1"]
            s.details = ["m1": seeded(batters: ["Y", "Z"])]
            await s.refresh()
            #expect(s.details["m1"]?.batters.map(\.id) == ["A", "B"])
        }

        @Test func startRefreshesAndStopEndsTheLoop() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1")]))
            let s = ScoreStore(defaults: temp.defaults)
            s.start()
            #expect(await waitUntil { s.lastUpdated != nil })
            #expect(s.matches.map(\.id) == ["m1"])
            await s.stop()
            let count = panelRequests()
            #expect(count == 1)
            try? await Task.sleep(nanoseconds: 200_000_000)
            #expect(panelRequests() == count)
        }

        // A second start() cancels the first loop. If it didn't, the first loop
        // would wake after refreshSeconds and fetch again, so wait that long.
        @Test func restartCancelsTheOldLoop() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1")]))
            let s = ScoreStore(defaults: temp.defaults)
            s.refreshSeconds = 1
            s.start()
            #expect(await waitUntil { s.lastUpdated != nil })
            let first = s.lastUpdated
            s.start()
            #expect(await waitUntil { s.lastUpdated != first })
            await s.stop()
            #expect(panelRequests() == 2)
            try? await Task.sleep(nanoseconds: (s.refreshSeconds * 1_000_000_000) + 500_000_000)
            // Keep the store alive through the wait, so an old loop would still fetch.
            withExtendedLifetime(s) {
                #expect(panelRequests() == 2)
            }
        }

        // The loop doesn't keep the store alive, and a freed store fetches nothing.
        @Test func loopDoesNotKeepStoreAlive() async {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: panelPrefix, json: panel([event("m1")]))
            weak var weakStore: ScoreStore?
            do {
                let s = ScoreStore(defaults: temp.defaults)
                weakStore = s
                s.start()
            }
            #expect(weakStore == nil)
            try? await Task.sleep(nanoseconds: 200_000_000)
            #expect(panelRequests() == 0)
        }
    }
}
