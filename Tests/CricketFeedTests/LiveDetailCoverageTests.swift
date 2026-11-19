import Foundation
import Testing
@testable import CricketFeed

// Extra coverage for LiveDetail.swift: fetch paging, ball kinds, players and figures.

private func item(_ json: String) throws -> PBPItem { try decode(PBPItem.self, json) }

private func page(count: Int, _ balls: [String]) -> String {
    #"{"commentary":{"pageCount":\#(count),"items":[\#(balls.joined(separator: ","))]}}"#
}

private func pageNumber(_ url: URL) -> Int? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value.flatMap(Int.init)
}

extension NetworkTests {
    @Suite struct LiveDetailFetch {
        let base = "https://site.web.api.espn.com/apis/site/v2/sports/cricket/1/playbyplay"

        // Serves page n of a feed that has `count` pages; page n holds over n.
        func serve(count: Int, status: Int = 200, failPage: Int? = nil) {
            StubURLProtocol.on({ $0.absoluteString.hasPrefix(base) }) { req in
                let n = pageNumber(req.url!) ?? 0
                if n == failPage { return (status, Data("{}".utf8)) }
                return (200, Data(page(count: count, [ball(over: n, runs: n)]).utf8))
            }
        }

        var pagesAsked: [Int] { StubURLProtocol.requests.compactMap(pageNumber) }

        @Test func noPagesGivesNil() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: base, json: page(count: 0, []))
            #expect(try await fetchLiveDetail(match("42")) == nil)
            #expect(pagesAsked == [1])
        }

        @Test func onePageIsFetchedOnce() async throws {
            StubURLProtocol.reset()
            serve(count: 1)
            let d = try await fetchLiveDetail(match("42"))
            #expect(pagesAsked == [1])
            #expect(d?.overs.map(\.number) == [1])
            #expect(d?.period == 1)
            let url = try #require(StubURLProtocol.requests.first { $0.absoluteString.hasPrefix(base) })
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(q.contains(URLQueryItem(name: "event", value: "42")))
            #expect(q.contains(URLQueryItem(name: "period", value: "1")))
        }

        // Two pages: page 1 is reused, not fetched again, and nothing is cut off.
        @Test func twoPagesReuseFirst() async throws {
            StubURLProtocol.reset()
            serve(count: 2)
            let d = try await fetchLiveDetail(match("42"))
            #expect(pagesAsked == [1, 2])
            #expect(d?.overs.map(\.number) == [1, 2])
        }

        // Many pages: only the last three, and the oldest over is dropped as cut off.
        @Test func manyPagesTakesLastThree() async throws {
            StubURLProtocol.reset()
            serve(count: 6)
            let d = try await fetchLiveDetail(match("42"))
            #expect(pagesAsked == [1, 4, 5, 6])
            #expect(d?.overs.map(\.number) == [5, 6])
        }

        @Test func badStatusThrows() async throws {
            StubURLProtocol.reset()
            serve(count: 3, status: 503, failPage: 1)
            await #expect {
                try await fetchLiveDetail(match("42"))
            } throws: { error in
                if case FeedError.badStatus(503) = error { return true }
                return false
            }
        }

        @Test func badStatusOnLaterPageThrows() async throws {
            StubURLProtocol.reset()
            serve(count: 3, status: 500, failPage: 3)
            await #expect {
                try await fetchLiveDetail(match("42"))
            } throws: { error in
                if case FeedError.badStatus(500) = error { return true }
                return false
            }
            #expect(pagesAsked == [1, 2, 3])
        }

        @Test func badJSONThrows() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: base, json: "{}")
            await #expect(throws: DecodingError.self) { try await fetchLiveDetail(match("42")) }
        }
    }
}

@Suite struct BallKinds {
    @Test func everyKind() throws {
        let cases: [(String, String, Ball.Kind, Int)] = [
            (#"{"scoreValue":0,"dismissal":{"dismissal":true}}"#, "W", .wicket, 0),
            (#"{"scoreValue":1,"over":{"wide":1}}"#, "1wd", .extra, 1),
            (#"{"scoreValue":1,"over":{"noBall":1}}"#, "1nb", .extra, 1),
            (#"{"scoreValue":2,"over":{"legByes":2}}"#, "2lb", .extra, 2),
            (#"{"scoreValue":4,"over":{"byes":4}}"#, "4b", .extra, 4),
            (#"{"scoreValue":4,"playType":{"description":"four"}}"#, "4", .four, 4),
            (#"{"scoreValue":6,"playType":{"description":"six"}}"#, "6", .six, 6),
            (#"{"scoreValue":3,"playType":{"description":"run"}}"#, "3", .runs, 3),
            // No score, no over, no type: a dot.
            ("{}", "•", .dot, 0),
            (#"{"over":{"wide":0,"noBall":0,"legByes":0,"byes":0}}"#, "•", .dot, 0),
        ]
        for (json, label, kind, runs) in cases {
            let b = ballFor(try item(json))
            #expect(b == Ball(label: label, kind: kind, runs: runs), "\(json)")
        }
    }

    @Test func spoken() {
        #expect(Ball(label: "•", kind: .dot, runs: 0).spoken == "dot")
        #expect(Ball(label: "W", kind: .wicket, runs: 0).spoken == "wicket")
        #expect(Ball(label: "4", kind: .four, runs: 4).spoken == "four")
        #expect(Ball(label: "6", kind: .six, runs: 6).spoken == "six")
        #expect(Ball(label: "1", kind: .runs, runs: 1).spoken == "1 run")
        #expect(Ball(label: "3", kind: .runs, runs: 3).spoken == "3 runs")
        #expect(Ball(label: "2wd", kind: .extra, runs: 2).spoken == "2wd")
    }

    @Test func overRuns() {
        let o = OverSummary(number: 3, balls: [
            Ball(label: "1", kind: .runs, runs: 1), Ball(label: "1wd", kind: .extra, runs: 1),
            Ball(label: "6", kind: .six, runs: 6), Ball(label: "W", kind: .wicket, runs: 0),
        ])
        #expect(o.runs == 8)
        #expect(OverSummary(number: 1, balls: []).runs == 0)
    }
}

@Suite struct FigureLines {
    @Test func ratesListsOnlyWhatIsKnown() {
        var d = LiveDetail(overs: [])
        #expect(d.rates.isEmpty)
        d.crr = 7.456
        #expect(d.rates.map(\.label) == ["CRR"])
        #expect(d.rates.map(\.value) == ["7.46"])
        d.rrr = 9
        d.lastFive = "38/2 (7.60)"
        #expect(d.rates.map(\.label) == ["CRR", "RRR", "Last 5 ov"])
        #expect(d.rates.map(\.value) == ["7.46", "9.00", "38/2 (7.60)"])
        d.crr = nil
        #expect(d.rates.map(\.label) == ["RRR", "Last 5 ov"])
    }

    @Test func truncatesNotRounds() {
        #expect(truncated2(1.999) == "1.99")
        #expect(truncated2(0.29) == "0.29")  // 0.29 * 100 is 28.999..., the nudge keeps it at 0.29
        #expect(truncated2(0) == "0.00")
    }

    @Test func strikeRate() {
        #expect(BatterLine(id: "a", name: "A", runs: 50, balls: 30, fours: 0, sixes: 0).strikeRate == "166.66")
    }

    @Test func bowlerFigures() {
        func b(_ balls: Int, conceded: Int = 0) -> BowlerLine {
            BowlerLine(id: "x", name: "X", balls: balls, maidens: 0, conceded: conceded, wickets: 0)
        }
        #expect(b(0).overs == "0")
        #expect(b(0).economy == "-")
        #expect(b(0).oversSpoken == "0 overs")
        #expect(b(6).oversSpoken == "1 over")
        #expect(b(7).oversSpoken == "1 over 1 ball")
        #expect(b(7).overs == "1.1")
        #expect(b(12).oversSpoken == "2 overs")
        #expect(b(1).oversSpoken == "0 overs 1 ball")
        #expect(b(10, conceded: 7).economy == "4.20")
    }
}

@Suite struct PlayersEdgeCases {
    @Test func noNamedBatterGivesNobody() throws {
        let p = playersFor(try [item("{}"), item(#"{"batsman":{"athlete":{"displayName":"No ID"}}}"#)])
        #expect(p.batters.isEmpty)
        #expect(p.bowlers.isEmpty)
        #expect(playersFor([]).batters.isEmpty)
    }

    // Missing figures default to zero; missing short name to empty.
    @Test func missingFiguresAreZero() throws {
        let p = playersFor([try item("""
            {"batsman":{"athlete":{"id":"A","displayName":"Batter A"}},
             "otherBatsman":{"athlete":{"id":"B","displayName":"Batter B","shortName":"B."},
                             "totalRuns":7,"faced":9,"fours":1,"sixes":2},
             "bowler":{"athlete":{"id":"X","displayName":"Bowler X"}},
             "otherBowler":{"athlete":{"id":"Y","displayName":"Bowler Y","shortName":"Y."},
                            "balls":13,"maidens":1,"conceded":20,"wickets":3}}
            """)])
        #expect(p.batters.contains(BatterLine(id: "A", name: "Batter A", runs: 0, balls: 0, fours: 0, sixes: 0, onStrike: true)))
        #expect(p.batters.contains(BatterLine(id: "B", name: "Batter B", shortName: "B.", runs: 7, balls: 9, fours: 1, sixes: 2)))
        #expect(p.bowlers == [
            BowlerLine(id: "X", name: "Bowler X", balls: 0, maidens: 0, conceded: 0, wickets: 0),
            BowlerLine(id: "Y", name: "Bowler Y", shortName: "Y.", balls: 13, maidens: 1, conceded: 20, wickets: 3),
        ])
    }

    // No over, no score: nobody ran, so the striker keeps strike.
    @Test func noOverInfoKeepsStrike() throws {
        let p = playersFor([try item("""
            {"batsman":{"athlete":{"id":"A","displayName":"Batter A"}},
             "otherBatsman":{"athlete":{"id":"B","displayName":"Batter B"}}}
            """)])
        #expect(p.batters.first(where: \.onStrike)?.id == "A")
    }

    // A no-ball where they ran once still swaps.
    @Test func noBallPenaltyIsNotRunning() throws {
        let p = playersFor(try items([ball(over: 1, runs: 2, noBall: 1)]))
        #expect(p.batters.first(where: \.onStrike)?.id == "B")
    }

    // Unnamed or empty-named players are left out; one batter gets no strike mark.
    @Test func unnamedPlayersDropped() throws {
        let p = playersFor([try item("""
            {"batsman":{"athlete":{"id":"A","displayName":"Batter A"}},
             "otherBatsman":{"athlete":{"id":"B","displayName":""}},
             "bowler":{"athlete":{"id":"X"}},
             "otherBowler":{"athlete":{"id":"Y","displayName":""}}}
            """)])
        #expect(p.batters.map(\.id) == ["A"])
        #expect(!p.batters[0].onStrike)
        #expect(p.bowlers.isEmpty)
    }

    // A wicket on a later item that names no players still removes the batter.
    @Test func laterWicketItemCounts() throws {
        let p = playersFor([
            try item(ball(over: 1)),
            try item(#"{"dismissal":{"dismissal":true,"batsman":{"athlete":{"id":"A"}}}}"#),
        ])
        #expect(p.batters.map(\.id) == ["B"])
        #expect(p.batters.allSatisfy { !$0.onStrike })
    }

    // Wicket with no named batter out: nobody removed, but no strike mark either.
    @Test func wicketWithNoOutBatter() throws {
        let p = playersFor([try item(#"{"dismissal":{"dismissal":true},"batsman":{"athlete":{"id":"A","displayName":"Batter A"}},"otherBatsman":{"athlete":{"id":"B","displayName":"Batter B"}}}"#)])
        #expect(Set(p.batters.map(\.id)) == ["A", "B"])
        #expect(p.batters.allSatisfy { !$0.onStrike })
    }

    // Both first seen on the same ball: more balls faced first, then higher id.
    @Test func sameBallTieBreak() throws {
        func order(_ a: Int, _ b: Int) throws -> [String] {
            playersFor([try item("""
                {"batsman":{"athlete":{"id":"A","displayName":"Batter A"},"faced":\(a)},
                 "otherBatsman":{"athlete":{"id":"B","displayName":"Batter B"},"faced":\(b)}}
                """)]).batters.map(\.id)
        }
        #expect(try order(3, 10) == ["B", "A"])
        #expect(try order(10, 3) == ["A", "B"])
        #expect(try order(5, 5) == ["B", "A"])
    }
}

@Suite struct BuildEdgeCases {
    @Test func nothingUsableGivesNil() throws {
        #expect(buildLiveDetail([], period: 1, startsMidInnings: false) == nil)
        #expect(buildLiveDetail([try item(#"{"team":{"id":"1","displayName":""}}"#)], period: 1, startsMidInnings: false) == nil)
    }

    // A team name alone is enough; items with no over number add no balls.
    @Test func teamOnlyItemAndNoOverNumber() throws {
        let d = buildLiveDetail([try item(#"{"team":{"id":"1","displayName":"India"},"innings":{"runRate":3.5}}"#)],
                                period: 1, startsMidInnings: false)
        #expect(d?.overs.isEmpty == true)
        #expect(d?.crr == 3.5)
        #expect(d?.batters.isEmpty == true)
    }

    // Only one over: kept even when the fetch started mid innings.
    @Test func singleOverNeverDropped() throws {
        let d = buildLiveDetail(try items([ball(over: 9, runs: 1), ball(over: 9, runs: 4, type: "four")]),
                                period: 1, startsMidInnings: true)
        #expect(d?.overs == [OverSummary(number: 9, balls: [
            Ball(label: "1", kind: .runs, runs: 1), Ball(label: "4", kind: .four, runs: 4),
        ])])
    }

    // No ball limit (a Test match): no "in N balls".
    @Test func chaseWithoutBallLimit() throws {
        let inn = #"{"requiredRunRate":3.2,"target":300,"remainingRuns":45,"remainingBalls":0}"#
        let d = buildLiveDetail(try items([ball(over: 60, innings: inn, team: "India")]), period: 4, startsMidInnings: false)
        #expect(d?.chase == "India need 45 runs.")
        #expect(d?.rrr == 3.2)
    }

    @Test func chaseWithoutRemainingBalls() throws {
        let inn = #"{"target":300,"remainingRuns":45,"ballLimit":300}"#
        let d = buildLiveDetail(try items([ball(over: 30, innings: inn, team: "India")]), period: 2, startsMidInnings: false)
        #expect(d?.chase == "India need 45 runs.")
    }

    // No team name on the latest ball: "They".
    @Test func chaseWithNoTeamName() throws {
        let d = buildLiveDetail([try item("""
            {"over":{"number":3},"batsman":{"athlete":{"id":"A","displayName":"Batter A"}},
             "innings":{"target":50,"remainingRuns":10,"remainingBalls":12,"ballLimit":120}}
            """)], period: 2, startsMidInnings: false)
        #expect(d?.chase == "They need 10 runs in 12 balls.")
    }

    // Target reached (or zero target): no chase line.
    @Test func noChaseWhenNothingNeeded() throws {
        let done = buildLiveDetail(try items([ball(over: 19, innings: #"{"target":150,"remainingRuns":0,"requiredRunRate":0}"#)]),
                                   period: 2, startsMidInnings: false)
        #expect(done?.chase == nil)
        #expect(done?.rrr == 0)
        let zero = buildLiveDetail(try items([ball(over: 19, innings: #"{"target":0,"remainingRuns":10,"requiredRunRate":4}"#)]),
                                   period: 2, startsMidInnings: false)
        #expect(zero?.chase == nil)
        #expect(zero?.rrr == nil)
    }

    // Five overs of nothing but wides: no legal balls, so the rate is 0.
    @Test func lastFiveWithNoLegalBalls() throws {
        let i = try items((1...5).map { ball(over: $0, runs: 1, wide: 1) })
        #expect(buildLiveDetail(i, period: 1, startsMidInnings: false)?.lastFive == "5/0 (0.00)")
    }

    // Wides and no-balls are not legal balls; leg byes are.
    @Test func lastFiveCountsLegalBallsOnly() throws {
        let legBye = #"{"scoreValue":1,"over":{"number":5,"legByes":1},"team":{"displayName":"England"}}"#
        let i = try items((1...4).map { ball(over: $0, runs: 1) } + [ball(over: 5, runs: 1, noBall: 1), legBye])
        // 6 runs off 5 legal balls = 7.20 an over.
        #expect(buildLiveDetail(i, period: 1, startsMidInnings: false)?.lastFive == "6/0 (7.20)")
    }
}
