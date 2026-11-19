import AppKit
import SwiftUI
import Testing
@testable import CricketFeed

// SwiftUI's onHover ignores synthetic mouseMoved events, but enter/exit events
// sent straight to the hosting view (which owns the tracking area) reach it.
@MainActor
private func enterExit(_ type: NSEvent.EventType, _ hosting: NSView, at point: CGPoint) {
    let loc = hosting.convert(NSPoint(x: point.x, y: hosting.bounds.height - point.y), to: nil)
    let e = NSEvent.enterExitEvent(with: type, location: loc, modifierFlags: [],
                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hosting.window!.windowNumber,
                                   context: nil, eventNumber: 0, trackingNumber: hosting.trackingAreas.first!.hash, userData: nil)!
    if type == .mouseEntered { hosting.mouseEntered(with: e) } else { hosting.mouseExited(with: e) }
    pump(0.3)
}

// Highest alpha along the line's left edge, where the "engaged" border is drawn.
@MainActor
private func borderAlpha(_ hosting: NSView) -> CGFloat {
    let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / hosting.bounds.width
    let x = Int(0.5 * scale)
    return (0..<rep.pixelsHigh).map { rep.colorAt(x: x, y: $0)?.alphaComponent ?? 0 }.max() ?? 0
}

@MainActor @Suite struct OversLineHover {
    // Clicking the line engages it (accent border). Moving the pointer away disengages it.
    @Test func leavingTheLineDisengagesIt() {
        let overs = [OverSummary(number: 1, balls: [Ball(label: "1", kind: .runs, runs: 1)])]
        let v = host(OversLine(overs: overs).frame(width: 300), size: CGSize(width: 300, height: 40))
        #expect(borderAlpha(v) == 0)
        enterExit(.mouseEntered, v, at: CGPoint(x: 150, y: 20))
        click(v, at: CGPoint(x: 150, y: 20), settle: 0.3)
        #expect(borderAlpha(v) > 0)
        enterExit(.mouseExited, v, at: CGPoint(x: 400, y: 20))
        #expect(borderAlpha(v) == 0)
    }
}
