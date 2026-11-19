import AppKit
import SwiftUI
import Testing
@testable import CricketFeed

// The match picker and the live-detail pieces in Views.swift (everything from
// `MatchPicker` down). What each piece shows is worked out in plain functions,
// tested first. Hosted tests at the bottom check real clicks.

// MARK: - Helpers

private func upcoming(_ id: String, teams: [String] = []) -> Match {
    Match(id: id, leagueID: "1", league: "Test", title: id, detail: "Tomorrow",
          state: "pre", stateLabel: "", summary: "", fullDescription: "",
          period: 0, sides: teams.map { Match.Side(id: $0, name: "Team \($0)", short: $0, score: "") })
}

private func over(_ n: Int, _ balls: [Ball]) -> OverSummary { OverSummary(number: n, balls: balls) }
private let dot = Ball(label: "•", kind: .dot, runs: 0)
private let one = Ball(label: "1", kind: .runs, runs: 1)
private let four = Ball(label: "4", kind: .four, runs: 4)
private let six = Ball(label: "6", kind: .six, runs: 6)
private let wkt = Ball(label: "W", kind: .wicket, runs: 0)
private let wide = Ball(label: "1wd", kind: .extra, runs: 1)

private func batter(_ name: String, short: String = "", runs: Int, balls: Int, strike: Bool = false) -> BatterLine {
    BatterLine(id: name, name: name, shortName: short, runs: runs, balls: balls, fours: 1, sixes: 0, onStrike: strike)
}

private func bowler(_ name: String, balls: Int) -> BowlerLine {
    BowlerLine(id: name, name: name, balls: balls, maidens: 0, conceded: 12, wickets: 1)
}

// MARK: - Match picker

@Suite struct MatchPickerContent {
    private func titles(_ s: [(title: String, matches: [Match])]) -> [String] { s.map(\.title) }
    private func ids(_ s: [(title: String, matches: [Match])]) -> [[String]] { s.map { $0.matches.map(\.id) } }

    @Test func liveThenUpcomingThenFinishedEachByTitle() {
        let s = MatchPicker.sections([match("B", live: false), upcoming("U"), match("C"), match("A")],
                                     search: "", favourite: { _ in false })
        #expect(titles(s) == ["Live", "Upcoming", "Finished"])
        #expect(ids(s) == [["A", "C"], ["U"], ["B"]])
    }

    @Test func favouriteTeamsComeFirstWhateverTheirState() {
        let s = MatchPicker.sections([upcoming("D"), match("Z", teams: ["9", "8"], live: false)],
                                     search: "", favourite: { $0.sides.contains { $0.id == "9" } })
        #expect(titles(s) == ["Your teams", "Upcoming"])
        #expect(ids(s) == [["Z"], ["D"]])
    }

    @Test func searchMatchesTitleOrLeagueIgnoringCase() {
        let all = [match("C"), match("A")]
        #expect(ids(MatchPicker.sections(all, search: "c", favourite: { _ in false })) == [["C"]])
        #expect(ids(MatchPicker.sections(all, search: "TEST", favourite: { _ in false })) == [["A", "C"]])
        #expect(MatchPicker.sections(all, search: "zzz", favourite: { _ in false }).isEmpty)
    }

    @Test func emptyStateSaysWhyThereAreNoRows() {
        let fetching = MatchPicker.emptyState(hasMatches: false, loaded: false, error: nil, search: "")
        #expect(fetching.title == "Fetching matches")
        #expect(fetching.symbol == "hourglass")

        let down = MatchPicker.emptyState(hasMatches: false, loaded: false, error: "offline", search: "")
        #expect(down.title == "Can't reach the score feed")
        #expect(down.symbol == "wifi.slash")

        let empty = MatchPicker.emptyState(hasMatches: false, loaded: true, error: nil, search: "")
        #expect(empty.title == "No matches in the feed")

        let noHits = MatchPicker.emptyState(hasMatches: true, loaded: true, error: nil, search: "zzz")
        #expect(noHits.title == "No results")
        #expect(noHits.message == "Nothing matches \u{201C}zzz\u{201D}.")
    }
}

// MARK: - Players table

@Suite struct PlayersTableContent {
    @Test func shortensNames() {
        let t = PlayersTable(batters: [], bowlers: [])
        #expect(t.initialled("Mahfijul Islam") == "M Islam")
        #expect(t.initialled("Najmul Hossain Shanto") == "N Hossain Shanto")
        #expect(t.initialled("Shanto") == "Shanto")
        #expect(t.initialled("") == "")
        // The feed's short name only when it's shorter than the initialled one.
        #expect(t.shortest("Najmul Hossain Shanto", short: "Shanto") == "Shanto")
        #expect(t.shortest("Mahfijul Islam", short: "") == "M Islam")
        #expect(t.shortest("Mahfijul Islam", short: "Mahfijul Islam") == "M Islam")
    }

    @Test func batterRowShowsFiguresWithRunsInBold() {
        let cells = PlayersTable.cells(batter("Mahfijul Islam", runs: 30, balls: 80, strike: true))
        #expect(cells == [.init("30", bold: true), .init("80"), .init("1"), .init("0"), .init("37.50")])
        // Not faced a ball: no strike rate.
        #expect(PlayersTable.cells(batter("New Batter", runs: 0, balls: 0)).last == .init("-"))
    }

    @Test func bowlerRowShowsFiguresWithWicketsInBold() {
        let cells = PlayersTable.cells(bowler("Kagiso Rabada", balls: 44))
        #expect(cells == [.init("7.2"), .init("0"), .init("12"), .init("1", bold: true), .init("1.63")])
        #expect(PlayersTable.cells(bowler("Keshav Maharaj", balls: 0)).first == .init("0"))
    }

    @Test func voiceOverReadsEachRowAsASentence() {
        #expect(PlayersTable.spoken(batter("Mahfijul Islam", runs: 30, balls: 80, strike: true))
                == "Mahfijul Islam, on strike, 30 off 80 balls, 1 fours, 0 sixes, strike rate 37.50")
        #expect(PlayersTable.spoken(batter("New Batter", runs: 0, balls: 0))
                == "New Batter, 0 off 0 balls, 1 fours, 0 sixes")
        #expect(PlayersTable.spoken(bowler("Kagiso Rabada", balls: 44))
                == "Kagiso Rabada, 7 overs 2 balls, 0 maidens, 12 runs, 1 wickets, economy 1.63")
        #expect(PlayersTable.spoken(bowler("Keshav Maharaj", balls: 0))
                == "Keshav Maharaj, 0 overs, 0 maidens, 12 runs, 1 wickets")
    }
}

// MARK: - Overs

@Suite struct OverGroupContent {
    @Test func ordinals() {
        let g = OverGroup(over: over(1, []))
        let cases: [Int: String] = [
            1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 10: "10th",
            11: "11th", 12: "12th", 13: "13th", 14: "14th",
            21: "21st", 22: "22nd", 23: "23rd",
            101: "101st", 111: "111th", 112: "112th", 113: "113th",
        ]
        for (n, s) in cases { #expect(g.ordinal(n) == s) }
    }

    @Test func runCaptionIsSingularOnlyForOne() {
        #expect(OverGroup(over: over(1, [one, dot])).runsCaption == "RUN")
        #expect(OverGroup(over: over(1, [dot])).runsCaption == "RUNS")
        #expect(OverGroup(over: over(1, [four, six, wkt, wide])).runsCaption == "RUNS")
    }

    @Test func voiceOverReadsTheOverOldestBallFirst() {
        #expect(OverGroup(over: over(1, [one, dot])).spoken == "1st over, 1 run: 1 run, dot")
        #expect(OverGroup(over: over(22, [four, six, wkt, wide])).spoken == "22nd over, 11 runs: four, six, wicket, 1wd")
    }
}

// Click engages the line, a second click or the pointer leaving lets go.
// The wheel is only redirected while engaged and hovered.
@Suite struct OversLineScrollState {
    @Test func clickEngagesAndLeavingLetsGo() {
        let s = OversLineScroll()
        #expect(!s.engaged && !s.wheel.active)

        s.hover(true)
        s.tap()
        #expect(s.engaged && s.wheel.active && s.wheel.hovering)

        s.tap()
        #expect(!s.engaged && !s.wheel.active)

        s.tap()
        s.hover(false)
        #expect(!s.engaged && !s.wheel.active && !s.wheel.hovering)
    }
}

// MARK: - Hosted views

// Types into the picker's search box. The box takes focus when the picker appears.
@MainActor
private func type(_ text: String, into hosting: NSView) {
    var fields: [NSTextField] = []
    func find(_ v: NSView) { if let t = v as? NSTextField { fields.append(t) }; v.subviews.forEach(find) }
    find(hosting)
    let field = fields[0]
    hosting.window!.makeFirstResponder(field)
    if let editor = field.currentEditor() as? NSTextView {
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }
    pump(0.1)
}

extension UITests {
    @MainActor @Suite struct MatchPickerClicks {
        // Live A (two teams), live C (title only), finished B. Rows sit at these heights.
        static let rowA = CGPoint(x: 150, y: 80)
        static let rowC = CGPoint(x: 150, y: 140)
        static let rowB = CGPoint(x: 150, y: 220)

        @Test func clickTogglesWatchingInSectionOrder() {
            let tmp = TempDefaults()
            let store = ScoreStore(defaults: tmp.defaults)
            store.autoWatch = false
            store.matches = [match("B", teams: ["1", "2"], live: false), match("C"), match("A", teams: ["3", "4"])]
            store.lastUpdated = Date()
            let v = host(MatchPicker(store: store), size: CGSize(width: 320, height: 400))

            // Live matches by title, then the finished one.
            click(v, at: Self.rowA)
            #expect(store.watched == ["A"])
            click(v, at: Self.rowC)
            #expect(store.watched == ["A", "C"])
            click(v, at: Self.rowB)
            #expect(store.watched == ["A", "B", "C"])

            // Clicking a ticked row stops watching it and remembers it was stopped.
            click(v, at: Self.rowA)
            #expect(store.watched == ["B", "C"])
            #expect(store.hidden == ["A"])
        }

        @Test func typingInTheSearchBoxFiltersTheRows() {
            let tmp = TempDefaults()
            let store = ScoreStore(defaults: tmp.defaults)
            store.autoWatch = false
            store.matches = [match("C"), match("A", teams: ["3", "4"])]
            store.lastUpdated = Date()
            let v = host(MatchPicker(store: store), size: CGSize(width: 320, height: 400))

            // Only C is left, in the first row's spot.
            type("c", into: v)
            click(v, at: CGPoint(x: 150, y: 60))
            #expect(store.watched == ["C"])

            // No results: nothing left to click.
            type("zzz", into: v)
            click(v, at: Self.rowA)
            #expect(store.watched == ["C"])
        }
    }

    @MainActor @Suite struct LiveDetailViews {
        @Test func ratesRowDropsRatesWhenTight() {
            let rates: [(label: String, value: String)] = [("CRR", "5.14"), ("RRR", "11.47"), ("Last 5 ov", "38/2 (7.60)")]
            func width(_ r: [(label: String, value: String)], in space: CGFloat) -> CGFloat {
                NSHostingController(rootView: RatesRow(rates: r)).sizeThatFits(in: CGSize(width: space, height: 30)).width
            }
            let all = width(rates, in: 400)
            let squeezed = width(rates, in: 120)
            #expect(all > 120)
            #expect(squeezed <= 120)
            #expect(squeezed > 0)
            #expect(width([], in: 200) == 0)
        }

        @Test func bottomFadeOnlyFadesTheBottomWhenOn() {
            // Bottom edge: see-through with the fade on, solid with it off. Top: solid either way.
            func alpha(_ on: Bool, y: Int) -> CGFloat {
                let v = host(Color.red.frame(width: 100, height: 100).bottomFade(on), size: CGSize(width: 100, height: 100))
                let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
                v.cacheDisplay(in: v.bounds, to: rep)
                let scale = rep.pixelsHigh / 100
                return rep.colorAt(x: 50 * scale, y: y * scale)!.alphaComponent // y down from the top
            }
            #expect(alpha(true, y: 99) < 0.2)
            #expect(alpha(false, y: 99) > 0.9)
            #expect(alpha(true, y: 10) > 0.9)
        }
    }
}
