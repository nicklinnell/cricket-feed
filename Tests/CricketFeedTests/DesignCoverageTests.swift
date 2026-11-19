import AppKit
import SwiftUI
import Testing
@testable import CricketFeed

// MARK: - Helpers (local to this file)

// Resolves a Theme colour to sRGB components under a given appearance.
private func resolved(_ color: Color, _ name: NSAppearance.Name) -> [CGFloat] {
    var out: [CGFloat] = []
    NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        out = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }
    return out
}

private func close(_ a: [CGFloat], _ b: [CGFloat]) -> Bool {
    zip(a, b).allSatisfy { abs($0 - $1) < 0.01 }
}

// PNG of `size` pixels, opaque red inside `opaque` (pixel rect, origin top-left), clear elsewhere.
private func png(width: Int, height: Int, opaque: (x: Int, y: Int, w: Int, h: Int)?) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for y in 0..<height {
        for x in 0..<width {
            var on = false
            if let o = opaque { on = x >= o.x && x < o.x + o.w && y >= o.y && y < o.y + o.h }
            rep.setColor(on ? NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1) : NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y)
        }
    }
    return rep.representation(using: .png, properties: [:])!
}

// Alpha of the rendered pixel at a point (SwiftUI coords).
@MainActor
private func alpha(_ hosting: NSView, at point: CGPoint) -> CGFloat {
    let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / hosting.bounds.width
    return rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.alphaComponent ?? 0
}

private func side(name: String = "India", short: String = "IND", score: String = "", logo: URL? = nil) -> Match.Side {
    Match.Side(id: "6", name: name, short: short, score: score, logo: logo)
}

private func phaseMatch(state: String, label: String) -> Match {
    Match(id: "1", leagueID: "1", league: "L", title: "T", detail: "", state: state, stateLabel: label,
          summary: "", fullDescription: "", period: 1, sides: [])
}

// MARK: - Theme and plain types

// WCAG 2 contrast. Colours are sRGB [r, g, b, a]; `over` composites a translucent
// colour on an opaque one the way AppKit does (in sRGB, not linear light).
private func over(_ top: [CGFloat], _ bottom: [CGFloat]) -> [CGFloat] {
    let a = top[3]
    return (0..<3).map { top[$0] * a + bottom[$0] * (1 - a) } + [1]
}

private func luminance(_ c: [CGFloat]) -> CGFloat {
    func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])
}

private func contrast(_ a: [CGFloat], _ b: [CGFloat]) -> CGFloat {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

private func withAlpha(_ c: [CGFloat], _ a: CGFloat) -> [CGFloat] { [c[0], c[1], c[2], c[3] * a] }

// The panel is .regularMaterial, so it has no fixed colour. These opaque stand-ins
// are roughly what the material shows over a neutral desktop. Picked before
// computing any ratio; results depend on them.
private let panelBackdrop: [NSAppearance.Name: [CGFloat]] = [
    .aqua: [0.93, 0.93, 0.93, 1],
    .darkAqua: [0.18, 0.18, 0.18, 1],
]

@MainActor @Suite struct DesignThemeTests {
    @Test func dynamicColoursDifferBetweenLightAndDark() {
        let dynamicColours: [Color] = [Theme.meta, Theme.live, Theme.paused, Theme.liveInk, Theme.pausedInk,
                                       Theme.cardFill, Theme.cardFillLive, Theme.cardStroke, Theme.hairline, Theme.band]
        for c in dynamicColours {
            #expect(!close(resolved(c, .aqua), resolved(c, .darkAqua)))
        }
        // Meta grey: dark text in light mode, light text in dark mode.
        #expect(close(resolved(Theme.meta, .aqua), [0.37, 0.37, 0.37, 1]))
        #expect(close(resolved(Theme.meta, .darkAqua), [0.78, 0.78, 0.78, 1]))
    }

    // Theme comments claim AA (4.5:1) for: meta grey on cards and the panel, pill ink
    // on its tinted pill (live/paused cards are the prominent fill), white on ball chips.
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func textColoursPassAAContrast(_ mode: NSAppearance.Name) {
        let panel = panelBackdrop[mode]!
        let card = over(resolved(Theme.cardFill, mode), panel)
        let liveCard = over(resolved(Theme.cardFillLive, mode), panel)
        let tint = CGFloat(StatusPill.tintOpacity)
        let livePill = over(withAlpha(resolved(Theme.live, mode), tint), liveCard)
        let pausedPill = over(withAlpha(resolved(Theme.paused, mode), tint), liveCard)
        let meta = resolved(Theme.meta, mode)
        let white: [CGFloat] = [1, 1, 1, 1]

        let pairs: [(String, [CGFloat], [CGFloat])] = [
            ("meta on panel", meta, panel),
            ("meta on card", meta, card),
            ("meta on live card", meta, liveCard),
            ("liveInk on live pill", resolved(Theme.liveInk, mode), livePill),
            ("pausedInk on paused pill", resolved(Theme.pausedInk, mode), pausedPill),
            ("white on four", white, resolved(Theme.four, mode)),
            ("white on six", white, resolved(Theme.six, mode)),
            ("white on wicket", white, resolved(Theme.wicket, mode)),
        ]
        for (name, text, background) in pairs {
            let ratio = contrast(text, background)
            #expect(ratio >= 4.5, "\(name) is \(ratio):1 in \(mode.rawValue)")
        }
    }

    @Test func panelRoomFloorsListHeight() {
        let room = PanelRoom()
        #expect(room.maxListHeight == 800 - Theme.panelChrome)
        room.height = 100
        #expect(room.maxListHeight == 160)
    }

    @Test func scorePartsSplitsScores() {
        #expect(ScoreParts("98 & 34/2 (12.3 ov, target 259)") ==
                { var p = ScoreParts(""); p.earlier = "98 &"; p.main = "34/2"; p.detail = "12.3 ov · target 259"; return p }())
        let plain = ScoreParts("  245/6  ")
        #expect(plain.main == "245/6" && plain.earlier.isEmpty && plain.detail.isEmpty)
        let odd = ScoreParts("Yet to bat")
        #expect(odd.main == "Yet to bat")
    }

    // Every known break pauses play, whatever the case or extra words around it.
    @Test(arguments: ["Lunch", "Tea", "Dinner", "Stumps", "Drinks", "Timeout", "Innings Break",
                      "Rain", "Delayed", "Bad Light", "Wet Outfield", "Interrupted"])
    func breakLabelsArePaused(_ label: String) {
        #expect(MatchPhase(phaseMatch(state: "in", label: label)) == .paused)
        #expect(MatchPhase(phaseMatch(state: "in", label: label.uppercased())) == .paused)
        #expect(MatchPhase(phaseMatch(state: "in", label: "Day 2 - \(label) taken")) == .paused)
    }

    @Test func matchPhaseFromState() {
        // Any in-play label that is not a known break counts as live, including none.
        for label in ["Live", "1st innings", "Day 3", "Strategic review", ""] {
            #expect(MatchPhase(phaseMatch(state: "in", label: label)) == .live)
        }
        #expect(MatchPhase(phaseMatch(state: "pre", label: "Scheduled")) == .upcoming)
        // Before start, a break word in the label does not make it paused.
        #expect(MatchPhase(phaseMatch(state: "pre", label: "Delayed")) == .upcoming)
        #expect(MatchPhase(phaseMatch(state: "post", label: "Result")) == .finished)
        // Unknown states are treated as over.
        #expect(MatchPhase(phaseMatch(state: "", label: "Live")) == .finished)
    }

    @Test func statusPillLabel() {
        #expect(StatusPill.label("Live") == "Live")
        #expect(StatusPill.label("Stumps - Day 1") == "Stumps - Day 1")
        #expect(StatusPill.label("") == "Unknown")
    }

    @Test func sideRowShortName() {
        #expect(SideRow.shortName(side(name: "India", short: "IND")) == "IND")
        #expect(SideRow.shortName(side(name: "India", short: "  IND ")) == "IND")
        // Missing code from the feed: no short form, the row falls back to the name.
        #expect(SideRow.shortName(side(name: "India", short: "?")) == "")
        #expect(SideRow.shortName(side(name: "India", short: "")) == "")
        // Same as the name: nothing extra to offer.
        #expect(SideRow.shortName(side(name: "IND", short: "IND")) == "")
    }

    @Test func sideRowAccessibilityLabel() {
        #expect(SideRow.accessibilityLabel(side(score: "245/6"), batting: false) == "India, 245/6")
        #expect(SideRow.accessibilityLabel(side(score: "245/6"), batting: true) == "India, 245/6, batting")
        #expect(SideRow.accessibilityLabel(side(score: ""), batting: false) == "India")
        // No score yet: just the name, even when batting.
        #expect(SideRow.accessibilityLabel(side(score: ""), batting: true) == "India")
    }

    @Test func hoverFillPrecedence() {
        // (pressed, hovering, selected) -> fill. Press beats hover, hover beats selected.
        let table: [(Bool, Bool, Bool, HoverFill)] = [
            (false, false, false, .none),
            (false, false, true, .selected),
            (false, true, false, .hovering),
            (false, true, true, .hovering),
            (true, false, false, .pressed),
            (true, false, true, .pressed),
            (true, true, false, .pressed),
            (true, true, true, .pressed),
        ]
        for (pressed, hovering, selected, want) in table {
            #expect(HoverFill(pressed: pressed, hovering: hovering, selected: selected) == want,
                    "pressed \(pressed) hovering \(hovering) selected \(selected)")
        }
        // Each state looks different from the others.
        let colours = [HoverFill.pressed, .hovering, .selected, .none].map(\.colour)
        #expect(Set(colours).count == 4)
    }
}

// MARK: - Image trimming

@Suite struct TrimTransparentEdgesTests {
    @Test func cropsTransparentPadding() {
        let img = NSImage(data: png(width: 10, height: 10, opaque: (x: 2, y: 3, w: 6, h: 4)))!
        let out = trimTransparentEdges(img)
        #expect(out.size == NSSize(width: 6, height: 4))
    }

    @Test func fullyTransparentImageIsReturnedUnchanged() {
        let img = NSImage(data: png(width: 8, height: 8, opaque: nil))!
        #expect(trimTransparentEdges(img) === img)
    }

    @Test func imageWithoutBitmapIsReturnedUnchanged() {
        let img = NSImage(size: NSSize(width: 5, height: 5))
        #expect(trimTransparentEdges(img) === img)
    }
}

// MARK: - Views

extension UITests {
    @MainActor @Suite struct DesignViewTests {
        // Smoke tests: the views lay out with real content. What they show is tested above.
        @Test func statusPillAndSideRowRender() {
            #expect(host(StatusPill(match: phaseMatch(state: "in", label: "Live"))).fittingSize.width > 0)
            // Logo has no stub route, so it fails fast and the row shows no flag.
            let logo = URL(string: "https://example.com/side-row-smoke.png")
            let row = host(SideRow(side: side(score: "98 & 34/2 (12.3 ov, target 259)", logo: logo)).frame(width: 240),
                           size: CGSize(width: 240, height: 60))
            #expect(row.fittingSize.height > 0)
        }

        @Test func emptyStateWithAndWithoutAction() {
            final class Box { var n = 0 }
            let box = Box()
            let plain = host(EmptyStateView(symbol: "wifi.slash", title: "Offline", message: "Check connection", tint: .gray),
                             size: CGSize(width: 300, height: 300))
            let withAction = EmptyStateView(symbol: "star", title: "No favourites", message: "Pick some",
                                            action: (title: "Pick teams", run: { box.n += 1 }))
            let v = host(VStack(spacing: 0) { withAction; Spacer() }.frame(width: 300, height: 300),
                         size: CGSize(width: 300, height: 300))
            #expect(v.fittingSize.height > plain.fittingSize.height)
            // Button sits at the bottom of the content: find it by scanning down the centre line.
            for y in stride(from: 100, through: 220, by: 4) where box.n == 0 {
                click(v, at: CGPoint(x: 150, y: CGFloat(y)), settle: 0.01)
            }
            #expect(box.n == 1)
        }
    }
}

// MARK: - Flags (network stub)

extension NetworkTests {
    @MainActor @Suite struct FlagCacheTests {
        private func unique(_ tag: String) -> String { "\(tag)-\(UUID().uuidString)" }
        // Only this test's requests, so a late fetch from another hosted view can't skew counts.
        private func hits(_ name: String) -> [URL] { StubURLProtocol.requests.filter { $0.absoluteString.contains(name) } }

        @Test func smallCombinerHitAndCacheHit() async {
            StubURLProtocol.reset()
            let name = unique("small")
            let url = URL(string: "https://a.espncdn.com/i/teamlogos/\(name).png")!
            StubURLProtocol.on(prefix: "https://a.espncdn.com/combiner/i?img=/i/teamlogos/\(name).png",
                               body: png(width: 10, height: 10, opaque: (x: 1, y: 1, w: 8, h: 5)))
            let first = await FlagCache.shared.image(for: url)
            #expect(first?.size == NSSize(width: 8, height: 5))
            #expect(hits(name).count == 1)
            #expect(hits(name).first?.absoluteString.contains("w=80") == true)
            let again = await FlagCache.shared.image(for: url)
            #expect(again === first)
            #expect(hits(name).count == 1)
        }

        @Test func smallFailsThenOriginalSucceeds() async {
            StubURLProtocol.reset()
            let name = unique("orig")
            let url = URL(string: "https://a.espncdn.com/i/teamlogos/\(name).png")!
            StubURLProtocol.on(prefix: "https://a.espncdn.com/combiner/", status: 404, body: Data())
            StubURLProtocol.on(prefix: url.absoluteString, body: png(width: 4, height: 4, opaque: (x: 0, y: 0, w: 4, h: 4)))
            let img = await FlagCache.shared.image(for: url)
            #expect(img?.size == NSSize(width: 4, height: 4))
            #expect(hits(name).count == 2)
            #expect(hits(name).last == url)
        }

        @Test func bothFailCachesMiss() async {
            StubURLProtocol.reset()
            let name = unique("miss")
            let url = URL(string: "https://a.espncdn.com/i/teamlogos/\(name).png")!
            #expect(await FlagCache.shared.image(for: url) == nil)
            #expect(hits(name).count == 2)
            #expect(await FlagCache.shared.image(for: url) == nil)
            #expect(hits(name).count == 2)
        }

        @Test func nonEspnHostFetchesOriginalOnce() async {
            StubURLProtocol.reset()
            let name = unique("other")
            let url = URL(string: "https://example.com/\(name).png")!
            // Not image data: decoding fails, and the loop stops after the single candidate.
            StubURLProtocol.on(prefix: url.absoluteString, body: Data("nope".utf8))
            #expect(await FlagCache.shared.image(for: url) == nil)
            #expect(hits(name) == [url])
        }

        // FlagCache tests cover fetching; this checks the view actually draws what it loaded.
        @Test func teamFlagDrawsLoadedLogo() async throws {
            StubURLProtocol.reset()
            let url = URL(string: "https://example.com/\(unique("flag")).png")!
            StubURLProtocol.on(prefix: url.absoluteString, body: png(width: 6, height: 4, opaque: (x: 0, y: 0, w: 6, h: 4)))
            let flag = host(TeamFlag(url: url), size: CGSize(width: 20, height: 14))
            // Yield the main actor (not pump) so the view's .task can run, until the flag is drawn.
            for _ in 0..<60 where alpha(flag, at: CGPoint(x: 10, y: 7)) == 0 { try await Task.sleep(for: .milliseconds(50)) }
            #expect(alpha(flag, at: CGPoint(x: 10, y: 7)) > 0)
        }
    }
}
