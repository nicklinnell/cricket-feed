import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CricketFeed

// ContentView and MatchCard: every state they can show, and their buttons.

// MARK: - Helpers (local to this file)

private final class Sizes {
    var all: [CGSize] = []
    var last: CGSize { all.last ?? .zero }
}

private func card(
    _ id: String = "m1", league: String = "Big Bash", detail: String = "", state: String = "in",
    stateLabel: String = "", summary: String = "", full: String = "", period: Int = 1,
    sides: [Match.Side] = [Match.Side(id: "1", name: "Team A", short: "A", score: "120/3 (15 ov)"),
                           Match.Side(id: "2", name: "Team B", short: "B", score: "")]
) -> Match {
    Match(id: id, leagueID: "1", league: league, title: "A v B", detail: detail, state: state,
          stateLabel: stateLabel, summary: summary, fullDescription: full, period: period, sides: sides)
}

private func liveDetail(period: Int = 1, chase: String? = nil, players: Bool = true, rates: Bool = true, overs: Bool = true) -> LiveDetail {
    LiveDetail(
        chase: chase, crr: rates ? 8.1 : nil, rrr: rates ? 9.2 : nil, lastFive: rates ? "38/2 (7.60)" : nil,
        overs: overs ? [OverSummary(number: 15, balls: [Ball(label: "4", kind: .four, runs: 4)])] : [],
        batters: players ? [BatterLine(id: "A", name: "Batter A", runs: 10, balls: 12, fours: 1, sixes: 0, onStrike: true)] : [],
        bowlers: players ? [BowlerLine(id: "X", name: "Bowler X", balls: 13, maidens: 0, conceded: 20, wickets: 1)] : [],
        period: period
    )
}

// Pins the panel to the top-left of the host so header buttons sit at fixed points:
// panel 300 wide, 12 padding, 24-high header -> y 24, plus at x 276, star 248, refresh 220.
@MainActor
private func hostPanel(_ store: ScoreStore, room: PanelRoom? = nil, sizes: Sizes,
                       reduceMotion: Bool? = nil, height: CGFloat = 900) -> NSHostingView<some View> {
    host(ContentView(store: store, room: room ?? PanelRoom()) { sizes.all.append($0) }
            .environment(\.reduceMotionOverride, reduceMotion)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
         size: CGSize(width: 320, height: height), settle: 0.15)
}

private let refreshPoint = CGPoint(x: 220, y: 24)
private let starPoint = CGPoint(x: 248, y: 24)
private let plusPoint = CGPoint(x: 276, y: 24)
private let donePoint = CGPoint(x: 265, y: 24)

// Clicks down a column until `done` holds. For buttons whose y depends on text wrapping.
@MainActor
@discardableResult
private func clickScan(_ v: NSView, x: CGFloat = 150, from: CGFloat, to: CGFloat, step: CGFloat = 5, until done: () -> Bool) -> Bool {
    var y = from
    while y <= to {
        click(v, at: CGPoint(x: x, y: y), settle: 0.03)
        if done() { return true }
        y += step
    }
    return false
}

@MainActor
private func newStore(_ tmp: TempDefaults) -> ScoreStore { ScoreStore(defaults: tmp.defaults) }

// MARK: - ContentView

@MainActor @Suite struct ContentViewStates {
    @Test func defaultSizeCallbackIsHarmless() {
        let tmp = TempDefaults()
        let v = host(ContentView(store: newStore(tmp), room: PanelRoom()))
        #expect(v.fittingSize.height > 0)
    }

    @Test func emptyStateWithoutFavouritesOpensPicker() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        let sizes = Sizes()
        let v = hostPanel(store, sizes: sizes)
        #expect(!sizes.all.isEmpty)
        let before = sizes.last
        let moved = clickScan(v, from: 60, to: 300) { sizes.last != before }
        #expect(moved)
        // Now in matches mode: Done is showing, and it goes back to the empty state.
        click(v, at: donePoint, settle: 0.15)
        #expect(sizes.last == before)
    }

    @Test func emptyStateWithFavouritesButAutoWatchOff() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        store.favourites = ["1": "Team A"]
        store.autoWatch = false
        let sizes = Sizes()
        _ = hostPanel(store, sizes: sizes)
        let withFavs = sizes.last
        store.favourites = [:]
        pump(0.15)
        // The longer no-favourites message wraps to more lines.
        #expect(sizes.last.height != withFavs.height)
    }

    @Test func skeletonWhileLoading() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        store.watched = ["a"]
        let sizes = Sizes()
        _ = hostPanel(store, sizes: sizes)
        let one = sizes.last.height
        store.watched = ["a", "b", "c"]
        pump(0.15)
        let two = sizes.last.height
        #expect(two > one)
        // Auto-watch alone still shows one placeholder.
        store.watched = []
        store.favourites = ["1": "Team A"]
        pump(0.15)
        #expect(sizes.last.height == one)
    }

    @Test func cantReachFeedThenNothingOn() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        store.watched = ["gone"]
        store.error = "The Internet connection appears to be offline."
        let sizes = Sizes()
        let v = hostPanel(store, sizes: sizes)
        let offline = sizes.last
        // No action button on the offline state: clicking down the panel changes nothing.
        clickScan(v, from: 60, to: Double(offline.height) - 10, step: 10) { false }
        #expect(sizes.last == offline)

        // Offline with an old update: footer shows the time.
        store.lastUpdated = Date()
        pump(0.15)
        #expect(sizes.last != offline)
    }

    @Test func nothingOnMessages() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        store.lastUpdated = Date()
        store.watched = ["gone"]
        let sizes = Sizes()
        let v = hostPanel(store, sizes: sizes)
        let picked = sizes.last.height

        // Auto-watching, a favourite's match is in the feed but hidden.
        store.watched = []
        store.favourites = ["1": "Team A"]
        store.matches = [card(state: "post")]
        store.hidden = ["m1"]
        pump(0.15)
        let stopped = sizes.last.height

        // Auto-watching, none of the teams playing.
        store.matches = [card(state: "post", sides: [Match.Side(id: "9", name: "Other", short: "O", score: "")])]
        pump(0.15)
        let none = sizes.last.height
        #expect(picked > 0 && stopped > 0 && none > 0)

        // Its button opens the match picker.
        let before = sizes.last
        #expect(clickScan(v, from: 60, to: 300) { sizes.last != before })
    }

    @Test func footerWhileFetching() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        let sizes = Sizes()
        let v = hostPanel(store, sizes: sizes)
        let scores = sizes.last
        // Star: teams mode shows the footer ("Fetching scores") with no update yet.
        click(v, at: starPoint, settle: 0.15)
        let teams = sizes.last
        #expect(teams != scores)
        click(v, at: donePoint, settle: 0.15)
        #expect(sizes.last == scores)
        click(v, at: plusPoint, settle: 0.15)
        let matches = sizes.last
        #expect(matches != scores && matches != teams)
        click(v, at: donePoint, settle: 0.15)
        #expect(sizes.last == scores)
    }

    @Test func errorFooterWithNothingFollowed() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        let sizes = Sizes()
        _ = hostPanel(store, sizes: sizes)
        let plain = sizes.last.height
        store.error = "Offline"
        pump(0.15)
        #expect(sizes.last.height > plain)
    }

    @Test func listOfCardsWithStatsToggle() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        let m = card(stateLabel: "Live", summary: "A chose to bat")
        store.matches = [m, card("m2", state: "post", summary: "A won by 3 runs")]
        store.watched = ["m1", "m2"]
        store.details = ["m1": liveDetail()]
        store.lastUpdated = Date()
        let sizes = Sizes()
        let v = hostPanel(store, sizes: sizes)
        let closed = sizes.last.height
        #expect(clickScan(v, x: 100, from: 60, to: closed - 20, step: 4) { store.statsOpen.contains("m1") })
        pump(0.15)
        #expect(sizes.last.height > closed)
    }

    @Test func longListScrollsAndCapsHeight() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        let ids = (1...6).map { "m\($0)" }
        store.matches = ids.map { card($0, state: "post", summary: "A won by 3 runs") }
        store.watched = Set(ids)
        store.lastUpdated = Date()
        let room = PanelRoom()
        room.height = 100 // list capped at 160
        let sizes = Sizes()
        _ = hostPanel(store, room: room, sizes: sizes)
        pump(0.2)
        let capped = sizes.last.height
        #expect(capped <= room.maxListHeight + Theme.panelChrome + 1)

        room.height = 2000
        pump(0.2)
        #expect(sizes.last.height > capped)
    }
}

// MARK: - Context menu

@MainActor @Suite struct MatchCardMenuTests {
    @Test func openAndStopWatching() {
        final class Opened { var urls: [URL] = [] }
        let opened = Opened()
        let tmp = TempDefaults()
        let store = newStore(tmp)
        let m = card()
        store.matches = [m]
        store.watched = ["m1"]
        let v = host(VStack(spacing: 0) {
            MatchCardMenu(match: m, store: store).frame(width: 200, height: 30)
        }
        .frame(width: 200, height: 60, alignment: .top)
        .environment(\.openURL, OpenURLAction { opened.urls.append($0); return .handled }),
        size: CGSize(width: 200, height: 60))
        click(v, at: CGPoint(x: 100, y: 15))
        #expect(opened.urls == [m.cricinfoURL])
        click(v, at: CGPoint(x: 100, y: 45))
        #expect(!store.watched.contains("m1"))
        #expect(store.hidden.contains("m1"))
    }
}

// MARK: - MatchCard

@MainActor @Suite struct MatchCardVariants {
    private func height(_ c: MatchCard) -> CGFloat {
        host(c.frame(width: 276), size: CGSize(width: 276, height: 600)).fittingSize.height
    }

    @Test func detailAndStatsChangeHeight() {
        let m = card(detail: "1st T20", stateLabel: "Live", summary: "A chose to bat",
                     full: "1st T20 (N), Big Bash at Perth, Nov 18 2026")
        let bare = height(MatchCard(match: m))
        let withDetail = height(MatchCard(match: m, detail: liveDetail()))
        let open = height(MatchCard(match: m, detail: liveDetail(), statsOpen: true))
        #expect(withDetail > bare)
        #expect(open > withDetail)
        // A detail from the last innings isn't shown.
        #expect(height(MatchCard(match: m, detail: liveDetail(period: 2))) == bare)
    }

    @Test func toggleClick() {
        final class Count { var n = 0 }
        let count = Count()
        let m = card(stateLabel: "Live", summary: "A chose to bat")
        let v = host(MatchCard(match: m, detail: liveDetail(rates: false, overs: false), toggleStats: { count.n += 1 })
            .frame(width: 276).frame(maxHeight: .infinity, alignment: .top),
                     size: CGSize(width: 276, height: 400))
        #expect(clickScan(v, x: 120, from: 40, to: 300, step: 4) { count.n == 1 })
    }

    @Test func defaultToggleIsHarmless() {
        let m = card(stateLabel: "Live")
        let c = MatchCard(match: m, detail: liveDetail(rates: false, overs: false))
        c.toggleStats()
        let v = host(c.frame(width: 276).frame(maxHeight: .infinity, alignment: .top), size: CGSize(width: 276, height: 400))
        clickScan(v, x: 120, from: 40, to: 200, step: 8) { false }
        #expect(v.fittingSize.height > 0)
    }

    @Test func phasesAndHeaderVariants() {
        let variants: [Match] = [
            // Upcoming with a date: date goes on the second line.
            card(detail: "2nd ODI", state: "pre", summary: "Starts 10:00", full: "2nd ODI, Tour at Hobart, Nov 18 2026"),
            // Upcoming, venue with no comma, no date.
            card(detail: "2nd ODI", state: "pre", full: "2nd ODI, Tour at Hobart"),
            // Finished: summary is strong.
            card(state: "post", summary: "A won by 3 runs", full: "Final"),
            // Paused between innings: no batting side.
            card(stateLabel: "Innings break", summary: "B won toss"),
            // Paused at stumps, one side with overs: that side bats.
            card(stateLabel: "Stumps", summary: "B won toss"),
            // Live, both sides with overs: no batting guess.
            card(stateLabel: "Live", sides: [Match.Side(id: "1", name: "A", short: "A", score: "100 (20 ov)"),
                                             Match.Side(id: "2", name: "B", short: "B", score: "50/1 (8 ov)")]),
            // No sides: title shows instead, empty league title with a city.
            card(league: "", detail: "", stateLabel: "Live", full: "x at Perth", sides: []),
            // Detail text that full description doesn't start with.
            card(detail: "3rd Test", full: "Other text"),
            // Prefix matches but no bracket after it.
            card(detail: "3rd Test", full: "3rd Test, at Lord's, Jun 1"),
        ]
        var heights: [CGFloat] = []
        for m in variants { heights.append(height(MatchCard(match: m))) }
        #expect(heights.allSatisfy { $0 > 0 })
        // No sides is shorter than two team rows.
        #expect(heights[6] < heights[5])
    }

    @Test func chaseBeatsSummary() {
        let m = card(stateLabel: "Live", summary: "B won toss")
        let plain = height(MatchCard(match: m, detail: liveDetail(chase: nil, players: false, rates: false, overs: false)))
        let chase = height(MatchCard(match: m, detail: liveDetail(chase: "Team A need 126 runs in 63 balls to win the match today.",
                                                              players: false, rates: false, overs: false)))
        #expect(chase > plain)
        // No summary and nothing live: no lower section.
        let empty = height(MatchCard(match: card(state: "post")))
        #expect(empty < plain)
    }
}

// MARK: - Refresh (network)

extension NetworkTests {
    @MainActor @Suite struct ContentViewRefresh {
        private let feed = """
        {"scores":[{"leagues":[{"id":"8048","name":"Big Bash"}],
          "events":[{"id":"77","name":"A v B","status":{"summary":"A won","type":{"state":"post","description":"Result"}},
            "competitions":[{"competitors":[{"team":{"id":"1","displayName":"Team A"},"score":"150"}]}]}]}]}
        """

        private func run(reduceMotion: Bool?) async throws {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: scorePanelURL.absoluteString, json: feed)
            let tmp = TempDefaults()
            let store = ScoreStore(defaults: tmp.defaults)
            store.watched = ["77"]
            let sizes = Sizes()
            let v = hostPanel(store, sizes: sizes, reduceMotion: reduceMotion)
            let skeleton = sizes.last
            click(v, at: refreshPoint)
            // The refresh task runs on the main actor, so yield to it rather than spin the run loop.
            for _ in 0..<100 where store.lastUpdated == nil { try await Task.sleep(for: .milliseconds(50)) }
            #expect(StubURLProtocol.requests.contains(scorePanelURL))
            #expect(store.matches.map(\.id) == ["77"])
            #expect(store.lastUpdated != nil)
            try await Task.sleep(for: .milliseconds(200))
            pump(0.1)
            // The skeleton has given way to the card.
            #expect(sizes.last != skeleton)
        }

        @Test func refreshWithSystemSetting() async throws { try await run(reduceMotion: nil) }
        @Test func refreshWithMotion() async throws { try await run(reduceMotion: false) }
        @Test func refreshWithReduceMotion() async throws { try await run(reduceMotion: true) }
    }
}
