import AppKit
import SwiftUI
import Testing
@testable import CricketFeed

// Covers the match picker and the live-detail pieces in Views.swift
// (everything from `MatchPicker` down).

// MARK: - Helpers

private func upcoming(_ id: String, teams: [String] = []) -> Match {
    Match(id: id, leagueID: "1", league: "Test", title: id, detail: "Tomorrow",
          state: "pre", stateLabel: "", summary: "", fullDescription: "",
          period: 0, sides: teams.map { Match.Side(id: $0, name: "Team \($0)", short: $0, score: "") })
}

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

// Finds the first AppKit scroll view under a hosting view (SwiftUI's ScrollView uses one).
private func scrollView(in view: NSView) -> NSScrollView? {
    if let s = view as? NSScrollView { return s }
    for sub in view.subviews { if let s = scrollView(in: sub) { return s } }
    return nil
}

// Sends a vertical mouse-wheel event aimed at a window. Without the window fields
// set, AppKit has no window to deliver the event to.
@MainActor
private func wheel(_ window: NSWindow, at pointInWindow: NSPoint? = nil, lines: Int32 = -3, points: Int64 = -30) {
    let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: lines, wheel2: 0, wheel3: 0)!
    cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: points)
    cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(lines))
    cg.flags = [] // a nil source picks up keys held on the real keyboard; Shift turns scrolls sideways
    if let p = pointInWindow {
        // CG screen coordinates have y down from the top of the main screen.
        let screen = window.convertPoint(toScreen: p)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        cg.location = CGPoint(x: screen.x, y: top - screen.y)
    }
    for raw: UInt32 in [51, 91, 92] { // window under the pointer
        cg.setIntegerValueField(CGEventField(rawValue: raw)!, value: Int64(window.windowNumber))
    }
    NSApp.sendEvent(NSEvent(cgEvent: cg)!)
    pump(0.1)
}

// Records the scroll deltas that reach it.
private final class WheelSink: NSView {
    var got: [(x: CGFloat, y: CGFloat)] = []
    override func scrollWheel(with event: NSEvent) { got.append((event.scrollingDeltaX, event.scrollingDeltaY)) }
}

@MainActor
private func sinkWindow() -> (NSWindow, WheelSink) {
    let sink = WheelSink(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 200, height: 200),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = sink
    window.orderFrontRegardless()
    return (window, sink)
}

// A window that records every scroll-wheel event it gets, after local monitors ran.
private final class RecordingWindow: NSWindow {
    var wheels: [(x: CGFloat, y: CGFloat)] = []
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel { wheels.append((event.scrollingDeltaX, event.scrollingDeltaY)) }
        super.sendEvent(event)
    }
}

// Like `host`, but in a RecordingWindow.
@MainActor
private func hostRecording<V: View>(_ view: V, size: CGSize) -> (NSHostingView<V>, RecordingWindow) {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    let window = RecordingWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.orderFrontRegardless()
    hosting.layoutSubtreeIfNeeded()
    pump(0.2)
    keptWindows.append(window)
    return (hosting, window)
}

@MainActor private var keptWindows: [NSWindow] = []

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

@MainActor @Suite struct MatchPickerViewTests {
    // Live A (two teams), live C (title only), finished B. Rows sit at these heights.
    static let rowA = CGPoint(x: 150, y: 80)
    static let rowC = CGPoint(x: 150, y: 140)
    static let rowB = CGPoint(x: 150, y: 220)

    @Test func liveFirstThenFinishedAndClickTogglesWatching() {
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
        #expect(!store.isWatched(store.matches[2]))
    }

    @Test func favouriteTeamsGetTheirOwnSectionAtTheTop() {
        let tmp = TempDefaults()
        let store = ScoreStore(defaults: tmp.defaults)
        store.autoWatch = false
        store.favourites = ["9": "Team 9"]
        store.matches = [upcoming("D"), match("Z", teams: ["9", "8"], live: false)]
        store.lastUpdated = Date()
        let v = host(MatchPicker(store: store), size: CGSize(width: 320, height: 400))

        // The finished favourite match comes before the upcoming one.
        click(v, at: Self.rowA)
        #expect(store.watched == ["Z"])
    }

    @Test func searchFiltersByTitleOrLeague() {
        let tmp = TempDefaults()
        let store = ScoreStore(defaults: tmp.defaults)
        store.autoWatch = false
        store.matches = [match("C"), match("A", teams: ["3", "4"])]
        store.lastUpdated = Date()
        let v = host(MatchPicker(store: store), size: CGSize(width: 320, height: 400))

        // Title match: only C is left, in the first row's spot.
        type("c", into: v)
        click(v, at: CGPoint(x: 150, y: 60))
        #expect(store.watched == ["C"])

        // League match ("Test") keeps both.
        type("test", into: v)
        click(v, at: Self.rowA)
        #expect(store.watched == ["A", "C"])

        // No results: nothing to click.
        type("zzz", into: v)
        click(v, at: Self.rowA)
        click(v, at: Self.rowC)
        #expect(store.watched == ["A", "C"])
        #expect(store.hidden.isEmpty)
    }

    @Test func emptyStatesHaveNoRows() {
        for setup in [
            { (s: ScoreStore) in },                                  // still fetching
            { (s: ScoreStore) in s.error = "offline" },              // feed down
            { (s: ScoreStore) in s.lastUpdated = Date() },           // feed empty
        ] {
            let tmp = TempDefaults()
            let store = ScoreStore(defaults: tmp.defaults)
            setup(store)
            let v = host(MatchPicker(store: store, maxHeight: 200), size: CGSize(width: 320, height: 300))
            click(v, at: Self.rowA)
            #expect(store.watched.isEmpty)
            #expect(store.hidden.isEmpty)
        }
    }

    @Test func pickerRowRunsItsAction() {
        final class Box { var n = 0 }
        let box = Box()
        let m = Match(id: "x", leagueID: "1", league: "IPL", title: "A v B", detail: "Day 2",
                      state: "in", stateLabel: "", summary: "", fullDescription: "Full", period: 1, sides: [])
        for selected in [true, false] {
            let v = host(PickerRow(match: m, selected: selected) { box.n += 1 }.frame(width: 300).fixedSize(),
                         size: CGSize(width: 300, height: 60))
            click(v, at: CGPoint(x: 150, y: 20))
        }
        #expect(box.n == 2)
    }
}

// MARK: - Live detail pieces

@MainActor @Suite struct LiveDetailViewTests {
    @Test func playersSectionButtonToggles() {
        final class Box { var n = 0 }
        let box = Box()
        let detail = LiveDetail(overs: [], batters: [batter("Mahfijul Islam", runs: 30, balls: 80, strike: true)],
                                bowlers: [bowler("Kagiso Rabada", balls: 44)])
        for open in [false, true] {
            let v = host(VStack(spacing: 0) {
                PlayersSection(detail: detail, open: open) { box.n += 1 }
                Spacer()
            }.padding(.horizontal, 10), size: CGSize(width: 320, height: 200))
            click(v, at: CGPoint(x: 150, y: 13))
        }
        #expect(box.n == 2)
    }

    @Test func playersTableShortensNames() {
        let t = PlayersTable(batters: [], bowlers: [])
        #expect(t.initialled("Mahfijul Islam") == "M Islam")
        #expect(t.initialled("Najmul Hossain Shanto") == "N Hossain Shanto")
        #expect(t.initialled("Shanto") == "Shanto")
        #expect(t.initialled("") == "")
    }

    @Test func playersTableLaysOutEveryShape() {
        let batters = [
            batter("Mahfijul Islam", runs: 30, balls: 80, strike: true),
            batter("Najmul Hossain Shanto", short: "Shanto", runs: 0, balls: 0),
        ]
        let bowlers = [bowler("Kagiso Rabada", balls: 44), bowler("Keshav Maharaj", balls: 0)]
        // Header 20pt, each row 22pt, 6pt gap before bowling when batters are shown.
        // Same heights wide (full names) and narrow (short names).
        for width in [400.0, 200.0] {
            for (b, w, height) in [(batters, bowlers, 134.0), ([], bowlers, 64), (batters, [], 64), ([], [], 0)] {
                let v = host(PlayersTable(batters: b, bowlers: w).frame(width: width), size: CGSize(width: width, height: 200))
                #expect(abs(v.fittingSize.height - height) < 0.5)
            }
        }
        #expect(batters[1].strikeRate == "-")
        #expect(bowlers[0].economy == "1.63")
    }

    @Test func ratesRowDropsRatesWhenTight() {
        let rates: [(label: String, value: String)] = [("CRR", "5.14"), ("RRR", "11.47"), ("Last 5 ov", "38/2 (7.60)")]
        func width(_ r: [(label: String, value: String)], in space: CGFloat) -> CGFloat {
            host(RatesRow(rates: r), size: CGSize(width: space, height: 30))
            return NSHostingController(rootView: RatesRow(rates: r)).sizeThatFits(in: CGSize(width: space, height: 30)).width
        }
        let all = width(rates, in: 400)
        let squeezed = width(rates, in: 120)
        #expect(all > 120)
        #expect(squeezed <= 120)
        #expect(squeezed > 0)
        #expect(width([], in: 200) == 0)
    }

    @Test func overGroupOrdinals() {
        let g = OverGroup(over: over(1, []))
        let cases: [Int: String] = [
            1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 10: "10th",
            11: "11th", 12: "12th", 13: "13th", 14: "14th",
            21: "21st", 22: "22nd", 23: "23rd",
            101: "101st", 111: "111th", 112: "112th", 113: "113th",
        ]
        for (n, s) in cases { #expect(g.ordinal(n) == s) }
    }

    @Test func overGroupRendersOneAndManyRuns() {
        let small = host(OverGroup(over: over(1, [one, dot])).fixedSize(), size: CGSize(width: 400, height: 40))
        let big = host(OverGroup(over: over(2, [four, six, wkt, wide])).fixedSize(), size: CGSize(width: 400, height: 40))
        // Four chips take more room than two.
        #expect(big.fittingSize.width > small.fittingSize.width)
        #expect(over(1, [one, dot]).runs == 1)
        #expect(over(2, [four, six, wkt, wide]).runs == 11)
    }

    @Test func ballChipColoursEveryKind() {
        #expect(BallChip(ball: four).bg == Theme.four)
        #expect(BallChip(ball: six).bg == Theme.six)
        #expect(BallChip(ball: wkt).bg == Theme.wicket)
        #expect(BallChip(ball: wide).bg == Theme.paused.opacity(0.15))
        #expect(BallChip(ball: dot).bg == Color.primary.opacity(0.07))
        #expect(BallChip(ball: one).bg == Color.primary.opacity(0.07))

        for b in [four, six, wkt] { #expect(BallChip(ball: b).fg == .white) }
        #expect(BallChip(ball: wide).fg == Theme.pausedInk)
        #expect(BallChip(ball: dot).fg == Theme.meta)
        #expect(BallChip(ball: one).fg == .primary)

        // Long labels ("1wd") get side padding, so the chip is wider than a short one.
        let short = host(BallChip(ball: one).fixedSize(), size: CGSize(width: 60, height: 30)).fittingSize.width
        let long = host(BallChip(ball: wide).fixedSize(), size: CGSize(width: 60, height: 30)).fittingSize.width
        #expect(long > short)
    }

    @Test func hairlineAndBottomFade() {
        let line = host(Hairline().frame(width: 100), size: CGSize(width: 100, height: 10))
        #expect(line.fittingSize.height == 0.5)
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

// MARK: - Overs line and wheel redirect

// Serialized: wheel monitors are app-wide, so these mustn't overlap.
@MainActor @Suite(.serialized) struct OversLineViewTests {
    final class Model: ObservableObject {
        @Published var overs: [OverSummary]
        @Published var shown = true
        init(_ overs: [OverSummary]) { self.overs = overs }
    }

    struct Holder: View {
        @ObservedObject var model: Model
        var body: some View {
            VStack(spacing: 0) {
                if model.shown { OversLine(overs: model.overs).frame(width: 300) }
                Spacer()
            }
            .frame(width: 300, height: 120)
        }
    }

    static func manyOvers(_ count: Int) -> [OverSummary] {
        (1...count).map { over($0, [one, four, dot, six, wkt, wide]) }
    }

    // SwiftUI's onHover ignores synthetic mouse events, so the pointer is never
    // "over" the line here. WheelRedirect's hover path is tested directly below.
    @Test func wheelStaysVerticalUntilThePointerIsOverTheLine() {
        let model = Model(Self.manyOvers(12))
        let (v, window) = hostRecording(Holder(model: model), size: CGSize(width: 300, height: 120))
        let lineCentre = CGPoint(x: 150, y: 18)
        let inWindow = v.convert(NSPoint(x: lineCentre.x, y: v.isFlipped ? lineCentre.y : v.bounds.height - lineCentre.y), to: nil)
        let scroller = scrollView(in: v)!
        func lastWheel() -> (x: CGFloat, y: CGFloat) { window.wheels.last! }

        // Current over at the left edge, older overs scrolled off to the right.
        #expect(scroller.contentView.bounds.origin.x == 0)
        #expect(scroller.documentView!.frame.width > 300)

        // Not clicked: vertical stays vertical.
        wheel(window, at: inWindow)
        #expect(lastWheel() == (0, -3))

        // Clicked, but no hover: still vertical.
        click(v, at: lineCentre)
        wheel(window, at: inWindow)
        #expect(lastWheel() == (0, -3))

        // A new ball while engaged (no jump), then another after disengaging (jumps to
        // the current over). The offset can't be moved by hand here, so this only
        // checks the line stays at the current over.
        model.overs[11] = over(12, [one, four, dot, six, wkt, wide, one])
        pump(0.3)
        click(v, at: lineCentre)
        model.overs.append(over(13, [one]))
        pump(0.5)
        #expect(scroller.contentView.bounds.origin.x == 0)

        // Every over gone: nothing to jump to.
        model.overs = []
        pump(0.2)

        #expect(window.wheels.count == 2)

        // Taken off screen: onDisappear stops the monitor (stop itself is tested below).
        model.shown = false
        pump(0.2)
        #expect(scrollView(in: v) == nil)
    }

    @Test func redirectTurnsVerticalIntoHorizontal() {
        let (window, sink) = sinkWindow()
        let w = WheelRedirect()
        w.start()
        w.start() // second start is a no-op, so events aren't flipped twice

        // Off by default.
        wheel(window)
        // Hovering but not clicked.
        w.hovering = true
        wheel(window)
        // Clicked and hovering: vertical becomes horizontal.
        w.active = true
        wheel(window)
        // Clicked but pointer elsewhere.
        w.hovering = false
        wheel(window)
        // Mostly sideways already: left alone.
        w.hovering = true
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: -3, wheel3: 0)!
        cg.flags = []
        for raw: UInt32 in [51, 91, 92] { cg.setIntegerValueField(CGEventField(rawValue: raw)!, value: Int64(window.windowNumber)) }
        NSApp.sendEvent(NSEvent(cgEvent: cg)!)
        pump(0.05)

        #expect(sink.got.count == 5)
        #expect(sink.got[0].x == 0 && sink.got[0].y == -3)
        #expect(sink.got[1].x == 0 && sink.got[1].y == -3)
        #expect(sink.got[2].x == -3 && sink.got[2].y == 0)
        #expect(sink.got[3].x == 0 && sink.got[3].y == -3)
        #expect(sink.got[4].x == -3 && sink.got[4].y == 0)

        // Stopped: events pass through untouched.
        w.stop()
        wheel(window)
        #expect(sink.got.last!.x == 0 && sink.got.last!.y == -3)
        window.close()
    }

    @Test func redirectStopsWhenReleased() {
        let (window, sink) = sinkWindow()
        weak var gone: WheelRedirect?
        // Own pool, so the redirect is really freed before the next event.
        autoreleasepool {
            let w = WheelRedirect()
            gone = w
            w.start()
            w.active = true
            w.hovering = true
            withExtendedLifetime(w) { wheel(window) }
        }
        #expect(gone == nil)
        gone?.stop() // if it somehow lived on, don't let it flip other tests' events
        // Released: deinit removed the monitor.
        wheel(window)
        #expect(sink.got.count == 2)
        #expect(sink.got[0].x == -3 && sink.got[0].y == 0)
        #expect(sink.got[1].x == 0 && sink.got[1].y == -3)
        window.close()
    }
}
