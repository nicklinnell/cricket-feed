import AppKit
import SwiftUI
import Testing
@testable import CricketFeed

// The overs line's click-then-scroll: a normal mouse wheel moves the line sideways
// only after a click and while the pointer is over it. WheelRedirect's monitor is
// app-wide, so these run in UITests, one at a time.

// Sends a mouse-wheel event to a window, as AppKit would. `lines` is the wheel's
// up/down movement (negative = down); `sideways` its left/right movement.
@MainActor
private func wheel(_ window: NSWindow, lines: Int32 = -3, sideways: Int32 = 0) {
    let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: lines, wheel2: sideways, wheel3: 0)!
    cg.flags = [] // a nil source picks up keys held on the real keyboard; Shift turns scrolls sideways
    // Aim it at our window, or AppKit has nowhere to deliver it. CGEventField has no
    // name for this one: raw field 51 is the window number NSEvent.windowNumber reads.
    cg.setIntegerValueField(CGEventField(rawValue: 51)!, value: Int64(window.windowNumber))
    let e = NSEvent(cgEvent: cg)!
    precondition(e.windowNumber == window.windowNumber, "wheel event not aimed at the test window")
    NSApp.sendEvent(e)
    pump(0.1)
}

// A window that records every scroll-wheel event it gets, after local monitors ran.
private final class RecordingWindow: NSWindow {
    var wheels: [(x: CGFloat, y: CGFloat)] = []
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel { wheels.append((event.scrollingDeltaX, event.scrollingDeltaY)) }
        super.sendEvent(event)
    }
}

@MainActor
private func recordingWindow<V: View>(_ view: V, size: CGSize) -> (NSHostingView<V>, RecordingWindow) {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    let window = RecordingWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.orderFrontRegardless()
    hosting.layoutSubtreeIfNeeded()
    hosting.display()
    pump(0.2)
    return (hosting, window)
}

// The AppKit scroll view under a hosting view (SwiftUI's ScrollView uses one).
private func scrollView(in view: NSView) -> NSScrollView? {
    if let s = view as? NSScrollView { return s }
    for sub in view.subviews { if let s = scrollView(in: sub) { return s } }
    return nil
}

private func last(_ w: RecordingWindow) -> (x: CGFloat, y: CGFloat)? { w.wheels.last }

extension UITests {
    @MainActor @Suite struct OversLineWheel {
        static let overs = (1...12).map { OverSummary(number: $0, balls: [
            Ball(label: "1", kind: .runs, runs: 1), Ball(label: "4", kind: .four, runs: 4),
            Ball(label: "•", kind: .dot, runs: 0), Ball(label: "6", kind: .six, runs: 6),
            Ball(label: "W", kind: .wicket, runs: 0), Ball(label: "1wd", kind: .extra, runs: 1),
        ]) }

        // The real OversLine, end to end: hover + click turns the wheel sideways,
        // leaving the line turns it back, taking the line off screen stops the monitor.
        @Test func clickThenHoverTurnsTheWheelSideways() {
            let (v, window) = recordingWindow(OversLine(overs: Self.overs), size: CGSize(width: 300, height: 40))
            defer { window.contentView = nil; pump(0.2); window.close() }
            let line = CGPoint(x: 150, y: 20)

            // Not clicked: vertical stays vertical.
            hover(v, at: line)
            wheel(window)
            #expect(last(window)! == (0, -3))

            // Clicked while over it: vertical becomes horizontal.
            click(v, at: line)
            wheel(window)
            #expect(last(window)! == (-3, 0))

            // Pointer leaves: let go, vertical again. Coming back needs a fresh click.
            hover(v, at: CGPoint(x: 400, y: 20), inside: false)
            wheel(window)
            #expect(last(window)! == (0, -3))
            hover(v, at: line)
            wheel(window)
            #expect(last(window)! == (0, -3))

            // Engaged again, then the line is removed: onDisappear stops the monitor.
            click(v, at: line)
            v.removeFromSuperview()
            pump(0.2)
            wheel(window)
            #expect(last(window)! == (0, -3))
        }

        final class Feed: ObservableObject {
            @Published var overs = OversLineWheel.overs
        }

        struct Live: View {
            @ObservedObject var feed: Feed
            var body: some View { OversLine(overs: feed.overs) }
        }

        // A new ball brings the line back to the current over, unless the user
        // clicked in to look back at older overs.
        @Test func newBallJumpsBackUnlessEngaged() {
            let feed = Feed()
            let v = host(Live(feed: feed), size: CGSize(width: 300, height: 40), settle: 0.2)
            defer { v.removeFromSuperview(); pump(0.2) }
            let scroller = scrollView(in: v)!
            func lookBack() {
                scroller.contentView.scroll(to: NSPoint(x: 200, y: 0))
                scroller.reflectScrolledClipView(scroller.contentView)
                pump(0.1)
            }
            func offset() -> CGFloat { scroller.contentView.bounds.origin.x }

            // Current over sits at the left edge; older overs run off to the right.
            #expect(offset() == 0)
            #expect(scroller.documentView!.frame.width > 300)

            // Engaged and looking back: a new ball leaves the line where it is.
            click(v, at: CGPoint(x: 150, y: 20))
            lookBack()
            feed.overs.append(OverSummary(number: 13, balls: [Ball(label: "1", kind: .runs, runs: 1)]))
            pump(0.5)
            #expect(offset() == 200)

            // Let go, then another ball: back to the current over.
            click(v, at: CGPoint(x: 150, y: 20))
            feed.overs[12] = OverSummary(number: 13, balls: [Ball(label: "1", kind: .runs, runs: 1), Ball(label: "•", kind: .dot, runs: 0)])
            pump(0.5)
            #expect(offset() == 0)
        }

        @Test func redirectTurnsVerticalIntoHorizontal() {
            let (_, window) = recordingWindow(Color.clear, size: CGSize(width: 200, height: 200))
            defer { window.close() }
            let w = WheelRedirect()
            defer { w.stop() }
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
            wheel(window, lines: 0, sideways: -3)

            let got = window.wheels
            #expect(got.count == 5)
            #expect(got[0] == (0, -3))
            #expect(got[1] == (0, -3))
            #expect(got[2] == (-3, 0))
            #expect(got[3] == (0, -3))
            #expect(got[4] == (-3, 0))

            // Stopped: events pass through untouched.
            w.stop()
            wheel(window)
            #expect(last(window)! == (0, -3))
        }

        @Test func redirectStopsWhenReleased() {
            let (_, window) = recordingWindow(Color.clear, size: CGSize(width: 200, height: 200))
            defer { window.close() }
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
            #expect(window.wheels.count == 2)
            #expect(window.wheels[0] == (-3, 0))
            #expect(window.wheels[1] == (0, -3))
        }
    }
}
