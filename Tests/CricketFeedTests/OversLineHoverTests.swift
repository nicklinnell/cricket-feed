import AppKit
import SwiftUI
import Testing
@testable import CricketFeed

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
        hover(v, at: CGPoint(x: 150, y: 20))
        click(v, at: CGPoint(x: 150, y: 20), settle: 0.3)
        #expect(borderAlpha(v) > 0)
        hover(v, at: CGPoint(x: 400, y: 20), inside: false)
        #expect(borderAlpha(v) == 0)
    }
}
