import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CricketFeed

// ContentView and MatchCard: what each state shows, and the buttons that change it.

// MARK: - Helpers (local to this file)

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

private final class Sizes {
    var all: [CGSize] = []
    var last: CGSize { all.last ?? .zero }
}

// Pins the panel to the top-left of the host so header buttons sit at fixed points:
// panel 300 wide, 12 padding, 24-high header -> y 24, plus at x 276, star 248, refresh 220.
@MainActor
private func hostPanel(_ store: ScoreStore, room: PanelRoom? = nil, sizes: Sizes = Sizes(), height: CGFloat = 900) -> NSHostingView<some View> {
    host(ContentView(store: store, room: room ?? PanelRoom()) { sizes.all.append($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
         size: CGSize(width: 320, height: height), settle: 0.15)
}

private let refreshPoint = CGPoint(x: 220, y: 24)
private let starPoint = CGPoint(x: 248, y: 24)
private let plusPoint = CGPoint(x: 276, y: 24)
private let donePoint = CGPoint(x: 265, y: 24)
// Picker rows start below the search box (y 46 to 74). Never click the box:
// a text field waits for a real mouse-up and the test hangs.
private let belowSearch: CGFloat = 100

// Clicks down a column until `done` holds. Returns the y that worked, or nil.
// For buttons and rows whose y depends on text wrapping.
@MainActor
@discardableResult
private func clickScan(_ v: NSView, x: CGFloat = 150, from: CGFloat, to: CGFloat, step: CGFloat = 5, until done: () -> Bool) -> CGFloat? {
    var y = from
    while y <= to {
        click(v, at: CGPoint(x: x, y: y), settle: 0.03)
        if done() { return y }
        y += step
    }
    return nil
}

@MainActor
private func newStore(_ tmp: TempDefaults) -> ScoreStore { ScoreStore(defaults: tmp.defaults) }

// Enough upcoming matches that picker rows fill the panel's column.
private let pickable = (1...10).map { card("p\($0)", state: "pre", summary: "Starts 10:00") }

// MARK: - ContentView: what the scores list shows

@MainActor @Suite struct ContentViewListContent {
    private func empty(_ store: ScoreStore) -> ContentView.EmptyState? {
        if case .empty(let e) = ContentView.listContent(store) { return e }
        return nil
    }

    @Test func modeTitles() {
        #expect(ContentView.Mode.scores.title == "Cricket")
        #expect(ContentView.Mode.matches.title == "Pick matches")
        #expect(ContentView.Mode.teams.title == "Favourite teams")
    }

    @Test func nothingFollowedWithoutFavourites() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        #expect(empty(store) == ContentView.EmptyState(
            symbol: "figure.cricket", title: "No matches yet",
            message: "Pick the games you want to follow, or star your favourite teams, and their scores will show here.",
            offersPicker: true))
    }

    @Test func favouritesWithAutoWatchOffStillCountAsNothingFollowed() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        store.favourites = ["1": "Team A"]
        store.autoWatch = false
        #expect(empty(store) == ContentView.EmptyState(
            symbol: "figure.cricket", title: "No matches yet",
            message: "Pick the games you want to follow. Your teams' games are at the top of the list.",
            offersPicker: true))
    }

    @Test func placeholdersWhileFirstFetchRuns() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        store.watched = ["a"]
        #expect(ContentView.listContent(store) == .loading(placeholders: 1))
        // Capped at two, however many are picked.
        store.watched = ["a", "b", "c"]
        #expect(ContentView.listContent(store) == .loading(placeholders: 2))
        // Auto-watch alone still shows one.
        store.watched = []
        store.favourites = ["1": "Team A"]
        #expect(ContentView.listContent(store) == .loading(placeholders: 1))
    }

    @Test func cantReachFeedOffersNoPicker() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        store.watched = ["gone"]
        store.error = "The Internet connection appears to be offline."
        #expect(empty(store) == ContentView.EmptyState(
            symbol: "wifi.slash", title: "Can't reach the score feed",
            message: "Will keep trying every few seconds.", offersPicker: false))
    }

    @Test func nothingOnVariants() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        store.lastUpdated = Date()
        func nothingOn(_ message: String) -> ContentView.EmptyState {
            .init(symbol: "calendar.badge.clock", title: "Nothing on right now", message: message, offersPicker: true)
        }

        // Picked by hand, but not in the feed.
        store.watched = ["gone"]
        #expect(empty(store) == nothingOn("Your picked matches aren't in the feed at the moment."))

        // Auto-watching, a favourite's match is in the feed but stopped.
        store.watched = []
        store.favourites = ["1": "Team A"]
        store.matches = [card(state: "post")]
        store.hidden = ["m1"]
        #expect(empty(store) == nothingOn("You've stopped watching your teams' matches."))

        // Auto-watching, none of the teams playing.
        store.matches = [card(state: "post", sides: [Match.Side(id: "9", name: "Other", short: "O", score: "")])]
        #expect(empty(store) == nothingOn("None of your teams are playing right now."))
    }

    @Test func cardsOnceAWatchedMatchIsInTheFeed() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        store.watched = ["m1"]
        store.matches = [card()]
        store.lastUpdated = Date()
        #expect(ContentView.listContent(store) == .cards)
        // Cards stay up while offline, rather than switching to "can't reach".
        store.error = "Offline"
        #expect(ContentView.listContent(store) == .cards)
    }
}

// MARK: - ContentView: footer

@MainActor @Suite struct ContentViewFooter {
    @Test func footerText() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let time = t.formatted(date: .omitted, time: .shortened)
        #expect(ContentView.footerText(error: nil, lastUpdated: nil) == "Fetching scores")
        #expect(ContentView.footerText(error: nil, lastUpdated: t) == "Updated \(time)")
        #expect(ContentView.footerText(error: "x", lastUpdated: t) == "Offline · last update \(time)")
        #expect(ContentView.footerText(error: "x", lastUpdated: nil) == "Offline")
    }

    @Test func footerHiddenOnlyWhenScoresHaveNothingToTime() {
        let tmp = TempDefaults()
        let store = newStore(tmp)
        #expect(!ContentView.showsFooter(store, mode: .scores))
        #expect(ContentView.showsFooter(store, mode: .matches))
        #expect(ContentView.showsFooter(store, mode: .teams))
        store.error = "Offline"
        #expect(ContentView.showsFooter(store, mode: .scores))
        store.error = nil
        store.watched = ["a"]
        #expect(ContentView.showsFooter(store, mode: .scores))
    }
}

// MARK: - ContentView: clicks (hosted)

extension UITests {
    @MainActor @Suite struct ContentViewClicks {
        // Placeholder cards have no buttons, so any toggle below came from the picker
        // the header button opened, not from the scores list.
        private func loadingStore(_ tmp: TempDefaults) -> ScoreStore {
            let store = newStore(tmp)
            store.watched = ["x"]
            store.matches = pickable
            return store
        }

        @Test func plusOpensMatchPickerAndDoneLeavesIt() {
            let tmp = TempDefaults()
            let store = loadingStore(tmp)
            let v = hostPanel(store)
            click(v, at: plusPoint, settle: 0.15)
            let rowY = clickScan(v, from: belowSearch, to: 400) { store.watched.count == 2 }
            #expect(rowY != nil)
            let picked = store.watched
            click(v, at: donePoint, settle: 0.15)
            // Back on scores: the same spot no longer hits a picker row.
            if let rowY { click(v, at: CGPoint(x: 150, y: rowY), settle: 0.1) }
            #expect(store.watched == picked)
        }

        @Test func starOpensTeamPicker() {
            let tmp = TempDefaults()
            let store = loadingStore(tmp)
            let v = hostPanel(store)
            click(v, at: starPoint, settle: 0.15)
            #expect(clickScan(v, from: belowSearch, to: 400) { !store.favourites.isEmpty } != nil)
        }

        @Test func emptyStateButtonOpensMatchPicker() {
            let tmp = TempDefaults()
            let store = newStore(tmp)
            store.matches = pickable
            let v = hostPanel(store)
            // First hits "Pick matches" (below the search box's spot); later clicks land on picker rows.
            #expect(clickScan(v, from: 60, to: 400) { !store.watched.isEmpty } != nil)
        }

        @Test func cantReachStateHasNoButton() {
            let tmp = TempDefaults()
            let store = newStore(tmp)
            store.watched = ["gone"]
            store.error = "Offline"
            store.matches = pickable
            let v = hostPanel(store)
            #expect(clickScan(v, from: 60, to: 400, step: 10) { store.watched != ["gone"] } == nil)
        }

        @Test func statsToggleOnACard() {
            let tmp = TempDefaults()
            let store = newStore(tmp)
            // Real cards: a match detail as the title, the league on line two.
            store.matches = [card(detail: "1st T20", stateLabel: "Live", summary: "A chose to bat",
                                  full: "1st T20 (N), Big Bash at Perth, Nov 18 2026"),
                             card("m2", state: "post", summary: "A won by 3 runs")]
            store.watched = ["m1", "m2"]
            store.details = ["m1": liveDetail()]
            store.lastUpdated = Date()
            let v = hostPanel(store)
            #expect(clickScan(v, x: 100, from: 60, to: 600, step: 4) { store.statsOpen.contains("m1") } != nil)
        }

        @Test func longListCapsHeightToRoom() {
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
}

// MARK: - Context menu

extension UITests {
    @MainActor @Suite struct MatchCardMenuTests {
        @Test func openOnCricinfoAndStopWatching() {
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
            #expect(opened.urls == [URL(string: "https://www.espncricinfo.com/ci/engine/match/m1.html")!])
            click(v, at: CGPoint(x: 100, y: 45))
            #expect(!store.isWatched(m))
            #expect(store.hidden.contains("m1"))
        }
    }
}

// MARK: - MatchCard: what the header and summary say

@Suite struct MatchCardText {
    @Test func headerFromFullDescription() {
        let c = MatchCard(match: card(detail: "3rd ODI", state: "post",
                                      full: "3rd ODI (D/N), England tour of Australia at Hobart, Nov 18 2026"))
        #expect(c.dayNight == " (D/N)")
        #expect(c.title == "3rd ODI (D/N)")
        #expect(c.city == "Hobart")
        #expect(c.date == "Nov 18 2026")
        // Finished: the date stays off line two; the league moves there under the detail.
        #expect(c.secondLine == "Big Bash")
    }

    @Test func dayNightNeedsDetailThenBracket() {
        #expect(MatchCard(match: card(detail: "3rd Test", full: "Other text")).dayNight == "")
        #expect(MatchCard(match: card(detail: "3rd Test", full: "3rd Test, at Lord's, Jun 1")).dayNight == "")
        #expect(MatchCard(match: card(detail: "3rd Test", full: "3rd Test (D/N)")).dayNight == " (D/N)")
    }

    @Test func venueWithoutCommaIsAllCity() {
        let c = MatchCard(match: card(state: "pre", full: "x at Hobart"))
        #expect(c.city == "Hobart")
        #expect(c.date == "")
        // No venue at all.
        #expect(MatchCard(match: card(full: "Final")).city == "")
    }

    @Test func noDetailUsesLeagueAsTitle() {
        let c = MatchCard(match: card(state: "post"))
        #expect(c.title == "Big Bash")
        #expect(c.secondLine == "")
    }

    @Test func upcomingPutsDateOnLineTwo() {
        #expect(MatchCard(match: card(state: "pre", full: "x at Hobart, Nov 18 2026")).secondLine == "Nov 18 2026")
        #expect(MatchCard(match: card(detail: "2nd ODI", state: "pre", full: "2nd ODI, Tour at Hobart, Nov 18 2026")).secondLine
                == "Nov 18 2026  ·  Big Bash")
        #expect(MatchCard(match: card(state: "pre", full: "x at Hobart")).secondLine == "")
    }

    @Test func summaryStrongByPhase() {
        #expect(MatchCard(match: card(state: "post", summary: "A won by 3 runs")).summaryStrong)
        #expect(!MatchCard(match: card(state: "pre", summary: "Starts 10:00")).summaryStrong)
        #expect(MatchCard(match: card(stateLabel: "Live", summary: "A need 40 runs")).summaryStrong)
        // Toss news stays quiet, live or paused...
        #expect(!MatchCard(match: card(stateLabel: "Live", summary: "B won toss")).summaryStrong)
        #expect(!MatchCard(match: card(stateLabel: "Stumps", summary: "B won toss")).summaryStrong)
        // ...unless a chase line replaces it.
        let chasing = MatchCard(match: card(stateLabel: "Live", summary: "B won toss"),
                                detail: liveDetail(chase: "Team A need 126 runs in 63 balls."))
        #expect(chasing.summaryStrong)
    }

    @Test func chaseLineBeatsFeedSummary() {
        let m = card(stateLabel: "Live", summary: "B won toss")
        #expect(MatchCard(match: m, detail: liveDetail(chase: "Team A need 126 runs in 63 balls.")).summaryText
                == "Team A need 126 runs in 63 balls.")
        #expect(MatchCard(match: m, detail: liveDetail(chase: nil)).summaryText == "B won toss")
        #expect(MatchCard(match: m).summaryText == "B won toss")
    }

    @Test func liveDetailOnlyForCurrentInningsOfALiveMatch() {
        let d = liveDetail()
        #expect(MatchCard(match: card(stateLabel: "Live"), detail: d).liveDetail == d)
        // Last innings' players never sit under the new score.
        #expect(MatchCard(match: card(stateLabel: "Live", period: 2), detail: d).liveDetail == nil)
        // A finished match drops stale ball-by-ball detail, chase line included.
        let done = MatchCard(match: card(state: "post", summary: "A won by 3 runs"), detail: liveDetail(chase: "A need 1 run"))
        #expect(done.liveDetail == nil)
        #expect(done.summaryText == "A won by 3 runs")
    }

    @Test func battingSideGuess() {
        let a = Match.Side(id: "1", name: "Team A", short: "A", score: "120/3 (15 ov)")
        // Live, only one side has overs: that side bats.
        #expect(MatchCard(match: card(stateLabel: "Live")).battingSide == a)
        // Paused at stumps still guesses.
        #expect(MatchCard(match: card(stateLabel: "Stumps")).battingSide == a)
        // Innings break: nobody is batting.
        #expect(MatchCard(match: card(stateLabel: "Innings break")).battingSide == nil)
        // Both sides with overs: no guess.
        let both = card(stateLabel: "Live", sides: [Match.Side(id: "1", name: "A", short: "A", score: "100 (20 ov)"),
                                                    Match.Side(id: "2", name: "B", short: "B", score: "50/1 (8 ov)")])
        #expect(MatchCard(match: both).battingSide == nil)
        // Not in play: no guess.
        #expect(MatchCard(match: card(state: "post")).battingSide == nil)
    }
}

// MARK: - MatchCard: clicks (hosted)

extension UITests {
    @MainActor @Suite struct MatchCardClicks {
        @Test func playersHeaderTogglesStats() {
            final class Count { var n = 0 }
            let count = Count()
            let m = card(stateLabel: "Live", summary: "A chose to bat")
            let v = host(MatchCard(match: m, detail: liveDetail(rates: false, overs: false), toggleStats: { count.n += 1 })
                .frame(width: 276).frame(maxHeight: .infinity, alignment: .top),
                         size: CGSize(width: 276, height: 400))
            #expect(clickScan(v, x: 120, from: 40, to: 300, step: 4) { count.n == 1 } != nil)
        }

        @Test func noSidesShowsMatchTitle() {
            // Rendered height is the only signal here: no sides means one title line, not two team rows.
            func height(_ m: Match) -> CGFloat {
                host(MatchCard(match: m).frame(width: 276), size: CGSize(width: 276, height: 600)).fittingSize.height
            }
            #expect(height(card(stateLabel: "Live", sides: [])) < height(card(stateLabel: "Live")))
        }
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

        @Test func refreshButtonFetchesScores() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.on(prefix: scorePanelURL.absoluteString, json: feed)
            let tmp = TempDefaults()
            let store = ScoreStore(defaults: tmp.defaults)
            store.watched = ["77"]
            let v = hostPanel(store)
            #expect(ContentView.listContent(store) == .loading(placeholders: 1))
            click(v, at: refreshPoint)
            // The refresh task runs on the main actor, so yield to it rather than spin the run loop.
            for _ in 0..<100 where store.lastUpdated == nil { try await Task.sleep(for: .milliseconds(50)) }
            #expect(StubURLProtocol.requests.contains(scorePanelURL))
            #expect(store.matches.map(\.id) == ["77"])
            #expect(ContentView.listContent(store) == .cards)
        }
    }
}
