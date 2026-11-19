import Testing
@testable import CricketFeed

@Suite struct Figures {
    // Cricinfo cuts rates down rather than rounding.
    @Test func ratesTruncate() {
        #expect(truncated2(10.0 / 7) == "1.42")
        #expect(BatterLine(id: "a", name: "A", runs: 2, balls: 3, fours: 0, sixes: 0).strikeRate == "66.66")
        #expect(BatterLine(id: "a", name: "A", runs: 0, balls: 0, fours: 0, sixes: 0).strikeRate == "-")
    }

    @Test func bowlerOvers() {
        let b = BowlerLine(id: "x", name: "X", balls: 44, maidens: 0, conceded: 31, wickets: 0)
        #expect(b.overs == "7.2")
        #expect(b.oversSpoken == "7 overs 2 balls")
        #expect(b.economy == "4.22")
        #expect(BowlerLine(id: "x", name: "X", balls: 42, maidens: 0, conceded: 0, wickets: 0).overs == "7")
    }
}

@Suite struct Balls {
    func label(_ json: String) throws -> String { ballFor(try items([json])[0]).label }

    @Test func labels() throws {
        #expect(try label(ball(over: 1)) == "•")
        #expect(try label(ball(over: 1, runs: 3)) == "3")
        #expect(try label(ball(over: 1, runs: 4, type: "four")) == "4")
        #expect(try label(ball(over: 1, runs: 2, wide: 1)) == "2wd")
        #expect(try label(ball(over: 1, runs: 1, noBall: 1)) == "1nb")
    }

    @Test func wicketBeatsExtras() throws {
        #expect(try label(ball(over: 1, runs: 1, wide: 1, out: "A")) == "W")
    }
}

@Suite struct Strike {
    func onStrike(_ json: String) throws -> String? {
        playersFor(try items([json])).batters.first(where: \.onStrike)?.id
    }

    @Test func evenRunsKeepStrike() throws { #expect(try onStrike(ball(over: 1, runs: 2)) == "A") }
    @Test func oddRunsSwap() throws { #expect(try onStrike(ball(over: 1, runs: 1)) == "B") }
    @Test func endOfOverSwaps() throws { #expect(try onStrike(ball(over: 1, complete: true)) == "B") }
    @Test func oddRunsAtEndOfOverCancelOut() throws { #expect(try onStrike(ball(over: 1, runs: 1, complete: true)) == "A") }

    // scoreValue 2 on a wide is the 1-run penalty plus 1 run, so they crossed once.
    @Test func widePenaltyIsNotRunning() throws {
        #expect(try onStrike(ball(over: 1, runs: 2, wide: 1)) == "B")
        #expect(try onStrike(ball(over: 1, runs: 1, wide: 1)) == "A")
    }

    @Test func outBatterLeavesWithNoStrikeMark() throws {
        let p = playersFor(try items([ball(over: 1, out: "B")]))
        #expect(p.batters.map(\.id) == ["A"])
        #expect(!p.batters[0].onStrike)
    }

    @Test func battersKeepArrivalOrder() throws {
        let p = playersFor(try items([
            ball(over: 1, striker: "A", nonStriker: "B"),
            ball(over: 1, out: "B"),
            // C comes in and has faced more balls than A on this ball, but A was here first.
            ball(over: 1, striker: "C", nonStriker: "A"),
        ]))
        #expect(p.batters.map(\.id) == ["A", "C"])
        #expect(p.bowlers.map(\.id) == ["X"])
    }
}

@Suite struct Detail {
    func overs(_ n: ClosedRange<Int>, runs: Int = 1) -> [String] {
        n.map { ball(over: $0, runs: runs) }
    }

    @Test func dropsCutOffOldestOver() throws {
        let i = try items(overs(3...5))
        #expect(buildLiveDetail(i, period: 1, startsMidInnings: true)?.overs.map(\.number) == [4, 5])
        #expect(buildLiveDetail(i, period: 1, startsMidInnings: false)?.overs.map(\.number) == [3, 4, 5])
    }

    @Test func lastFiveOvers() throws {
        let i = try items(overs(1...6, runs: 2) + [ball(over: 6, out: "A")])
        // Overs 2-6: five 2s plus a wicket ball, 6 legal balls in total.
        #expect(buildLiveDetail(i, period: 1, startsMidInnings: false)?.lastFive == "10/1 (10.00)")
        #expect(buildLiveDetail(try items(overs(1...4)), period: 1, startsMidInnings: false)?.lastFive == nil)
    }

    @Test func chaseLine() throws {
        let inn = #"{"runRate":7.5,"requiredRunRate":9.1,"target":180,"remainingRuns":30,"remainingBalls":20,"ballLimit":120}"#
        let d = buildLiveDetail(try items([ball(over: 17, innings: inn, team: "Australia")]), period: 2, startsMidInnings: false)
        #expect(d?.chase == "Australia need 30 runs in 20 balls.")
        #expect(d?.rrr == 9.1)
        #expect(d?.period == 2)
    }

    @Test func noTargetNoChase() throws {
        let d = buildLiveDetail(try items([ball(over: 1, innings: #"{"runRate":4.0}"#)]), period: 1, startsMidInnings: false)
        #expect(d?.chase == nil)
        #expect(d?.rrr == nil)
        #expect(d?.crr == 4.0)
    }

    // The feed sometimes ends on an empty item; rates come from the last real ball.
    @Test func skipsFillerItem() throws {
        let i = try items([ball(over: 1, innings: #"{"runRate":6.0}"#), #"{"innings":{"runRate":0}}"#])
        #expect(buildLiveDetail(i, period: 1, startsMidInnings: false)?.crr == 6.0)
    }
}
