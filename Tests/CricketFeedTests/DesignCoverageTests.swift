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

// Synthetic mouseMoved doesn't reach SwiftUI's hover tracking, but a mouseEntered
// sent straight to the hosting view (the tracking area owner), tagged with its
// tracking area's number, does.
@MainActor
private func enter(_ hosting: NSView, at point: CGPoint) {
    let loc = hosting.convert(NSPoint(x: point.x, y: hosting.isFlipped ? point.y : hosting.bounds.height - point.y), to: nil)
    let e = NSEvent.enterExitEvent(with: .mouseEntered, location: loc, modifierFlags: [],
                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosting.window!.windowNumber,
                                   context: nil, eventNumber: 0, trackingNumber: hosting.trackingAreas.first!.hash, userData: nil)!
    hosting.mouseEntered(with: e)
    pump(0.3)
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

@MainActor @Suite struct DesignThemeTests {
    @Test func dynamicColoursDifferBetweenLightAndDark() {
        let dynamicColours: [Color] = [Theme.meta, Theme.live, Theme.paused, Theme.liveInk, Theme.pausedInk,
                                       Theme.cardFill, Theme.cardFillLive, Theme.cardStroke, Theme.hairline, Theme.band]
        for c in dynamicColours {
            #expect(!close(resolved(c, .aqua), resolved(c, .darkAqua)))
        }
        // Meta grey: darker in light mode, lighter in dark mode.
        #expect(close(resolved(Theme.meta, .aqua), [0.37, 0.37, 0.37, 1]) || resolved(Theme.meta, .aqua)[0] < 0.5)
        #expect(resolved(Theme.meta, .darkAqua)[0] > 0.7)
    }

    @Test func fixedColoursMatchInBothModes() {
        for c in [Theme.four, Theme.six, Theme.wicket] {
            #expect(close(resolved(c, .aqua), resolved(c, .darkAqua)))
        }
        #expect(Theme.panelWidth == 300)
        #expect(Theme.scoreSize > Theme.teamSize && Theme.teamSize > Theme.bodySize && Theme.bodySize > Theme.metaSize)
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

    @Test func matchPhaseFromState() {
        #expect(MatchPhase(phaseMatch(state: "in", label: "Live")) == .live)
        #expect(MatchPhase(phaseMatch(state: "in", label: "Stumps - Day 1")) == .paused)
        #expect(MatchPhase(phaseMatch(state: "in", label: "Innings Break")) == .paused)
        #expect(MatchPhase(phaseMatch(state: "pre", label: "Scheduled")) == .upcoming)
        #expect(MatchPhase(phaseMatch(state: "post", label: "Result")) == .finished)
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

@MainActor @Suite struct DesignViewTests {
    // Reduce Motion is read-only in SwiftUI's macOS environment, so only the default path is hosted.
    @Test func liveDotHasFixedSize() {
        let a = host(LiveDot(), size: CGSize(width: 20, height: 20))
        #expect(a.fittingSize == CGSize(width: 5, height: 5))
    }

    @Test func statusPillEveryPhase() {
        let labels = [("in", "Live"), ("in", "Lunch"), ("pre", "Scheduled"), ("post", "Result"), ("post", "")]
        var widths: [CGFloat] = []
        for (state, label) in labels {
            let v = host(StatusPill(match: phaseMatch(state: state, label: label)), size: CGSize(width: 200, height: 30))
            widths.append(v.fittingSize.width)
        }
        #expect(widths.allSatisfy { $0 > 0 })
        // Tinted pills carry horizontal padding, so "Live" (with dot) is wider than an untinted label of the same text.
        let live = host(StatusPill(match: phaseMatch(state: "in", label: "Live"))).fittingSize.width
        let done = host(StatusPill(match: phaseMatch(state: "post", label: "Live"))).fittingSize.width
        #expect(live > done)
    }

    @Test func sideRowVariants() {
        let rows: [SideRow] = [
            SideRow(side: side(score: "98 & 34/2 (12.3 ov, target 259)"), batting: true),
            SideRow(side: side(score: "245/6"), quiet: true),
            SideRow(side: side(score: "1234567890 something long")),
            SideRow(side: side(short: "?", score: "")),
            SideRow(side: side(name: "IND", short: "IND")),
            SideRow(side: side(name: "A very very long team name that cannot fit", short: "LNG", score: "100")),
        ]
        for r in rows {
            let v = host(r.frame(width: 140), size: CGSize(width: 140, height: 60))
            #expect(v.fittingSize.height > 0)
        }
    }

    @Test func buttonStylesAndHoverPlate() {
        final class Box { var n = 0 }
        let box = Box()
        host(Button("x") {}.buttonStyle(IconButtonStyle()), size: CGSize(width: 40, height: 40))
        host(Button("x") {}.buttonStyle(IconButtonStyle()).disabled(true), size: CGSize(width: 40, height: 40))
        host(HoverPlate(pressed: true) { Text("p") }, size: CGSize(width: 40, height: 40))
        host(HoverPlate(selected: true) { Text("s") }, size: CGSize(width: 40, height: 40))

        let v = host(VStack(spacing: 0) {
            Button("Go") { box.n += 1 }.buttonStyle(PillButtonStyle()).frame(width: 100, height: 40)
            HoverPlate { Text("hover me").frame(width: 100, height: 40) }
            Spacer()
        }.frame(width: 100, height: 200), size: CGSize(width: 100, height: 200))
        click(v, at: CGPoint(x: 50, y: 20))
        #expect(box.n == 1)
    }

    @Test func hoverPlateFillsOnHover() {
        let v = host(HoverPlate { Color.clear.frame(width: 60, height: 40) }, size: CGSize(width: 60, height: 40))
        #expect(alpha(v, at: CGPoint(x: 30, y: 20)) == 0)
        enter(v, at: CGPoint(x: 30, y: 20))
        let hovered = alpha(v, at: CGPoint(x: 30, y: 20))
        #expect(hovered > 0)
        // Press deepens the plate beyond hover.
        let pressed = host(HoverPlate(pressed: true) { Color.clear.frame(width: 60, height: 40) }, size: CGSize(width: 60, height: 40))
        #expect(alpha(pressed, at: CGPoint(x: 30, y: 20)) > hovered)
    }

    @Test func skeletonCardAndCardBackground() {
        let s = host(SkeletonCard().frame(width: 280), size: CGSize(width: 300, height: 200))
        #expect(s.fittingSize.height > 100)
        host(Text("x").cardBackground(prominent: true), size: CGSize(width: 40, height: 40))
        host(Text("x").cardBackground(), size: CGSize(width: 40, height: 40))
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

        @Test func teamFlagAndSideRowLoadLogo() async throws {
            StubURLProtocol.reset()
            let name = unique("flag")
            let url = URL(string: "https://example.com/\(name).png")!
            StubURLProtocol.on(prefix: url.absoluteString, body: png(width: 6, height: 4, opaque: (x: 0, y: 0, w: 6, h: 4)))
            let flag = host(TeamFlag(url: url), size: CGSize(width: 20, height: 14))
            host(SideRow(side: side(score: "120/3", logo: url)).frame(width: 200), size: CGSize(width: 200, height: 40))
            // Yield the main actor (not pump) so the views' .task can run, until the flag is drawn.
            for _ in 0..<60 where alpha(flag, at: CGPoint(x: 10, y: 7)) == 0 { try await Task.sleep(for: .milliseconds(50)) }
            #expect(alpha(flag, at: CGPoint(x: 10, y: 7)) > 0)
            // Both views may fetch at once before either caches; after that it's a cache hit.
            let fetched = hits(name).count
            #expect(fetched >= 1)
            #expect(await FlagCache.shared.image(for: url)?.size == NSSize(width: 6, height: 4))
            #expect(hits(name).count == fetched)
        }
    }
}
