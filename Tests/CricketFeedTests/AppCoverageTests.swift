import AppKit
import Foundation
import Testing
@testable import CricketFeed

// The app's panel, menu bar item and launch. These start a real ScoreStore, so they
// live under NetworkTests (one at a time, stubbed network with no routes).
extension NetworkTests {
    @MainActor @Suite struct AppShell {
        static let frameName = "CricketFeedPanel"

        // No routes: every fetch fails fast and nothing reaches ESPN.
        init() { StubURLProtocol.reset() }

        // A delegate on a throwaway defaults suite. Keep `temp` alive as long as the delegate.
        func makeDelegate(_ temp: TempDefaults) -> AppDelegate {
            AppDelegate(store: ScoreStore(defaults: temp.defaults))
        }

        // Waits until the store's first refresh fails (no stub routes), proving start() ran.
        func waitForFirstRefresh(_ d: AppDelegate) async throws {
            for _ in 0..<100 where d.store.error == nil {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(d.store.error != nil)
        }

        // Hides and lets go of everything a launch made, so nothing leaks into other tests.
        func tearDown(_ d: AppDelegate) {
            if let panel = d.panel {
                panel.orderOut(nil)
                panel.setFrameAutosaveName("")
                panel.contentView = nil
            }
            if let item = d.statusItem { NSStatusBar.system.removeStatusItem(item) }
            d.panel = nil
            d.statusItem = nil
            NSWindow.removeFrame(usingName: Self.frameName)
        }

        func launch(_ d: AppDelegate) {
            d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        }

        // The search box needs a key window, and the panel's spot is remembered under one name.
        @Test func floatingPanelTakesTypingAndRemembersItsFrame() {
            NSWindow.removeFrame(usingName: Self.frameName)
            let panel = FloatingPanel(content: NSView())
            defer { panel.setFrameAutosaveName(""); NSWindow.removeFrame(usingName: Self.frameName) }
            #expect(panel.canBecomeKey)
            #expect(panel.frameAutosaveName == Self.frameName)
        }

        @Test func firstLaunchPlacesPanelTopRight() async throws {
            // Needs a real display to place against.
            guard let screen = NSScreen.main else { return }
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            launch(d)

            let panel = try #require(d.panel)
            let f = screen.visibleFrame
            #expect(abs(panel.frame.minX - (f.maxX - 320)) < 1)
            #expect(abs(panel.frame.maxY - (f.maxY - 20)) < 1)
            #expect(panel.isVisible)
            // Room below the panel: the screen's usable height less the 20pt gap at the top.
            #expect(abs(d.room.height - (f.height - 20)) < 1)

            // Menu bar item with show/hide, a separator and quit.
            let item = try #require(d.statusItem)
            #expect(item.button?.image != nil)
            #expect(item.button?.image?.isTemplate == true)
            let menu = try #require(item.menu)
            #expect(menu.items.map(\.title) == ["Show / Hide Scores", "", "Quit"])
            #expect(menu.items[0].action == #selector(AppDelegate.togglePanel))
            #expect(menu.items[1].isSeparatorItem)
            #expect(menu.items[2].action == #selector(NSApplication.terminate(_:)))

            try await waitForFirstRefresh(d)

            // SwiftUI reports its size and the panel fits to it, top-left kept.
            pump(0.2)
            #expect(abs(panel.frame.minX - (f.maxX - 320)) < 1)
            #expect(abs(panel.frame.maxY - (f.maxY - 20)) < 1)
            #expect(panel.frame.size != CGSize(width: 300, height: 200))
        }

        @Test func launchRestoresSavedFrame() async throws {
            guard let screen = NSScreen.main else { return }
            let f = screen.visibleFrame
            let saved = NSRect(x: f.minX + 40, y: f.minY + 60, width: 280, height: 300)
            // Save a frame under the panel's name, as a previous run would have.
            let old = NSWindow(contentRect: saved, styleMask: [.borderless], backing: .buffered, defer: true)
            old.setFrame(saved, display: false)
            old.saveFrame(usingName: Self.frameName)

            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            launch(d)
            let panel = try #require(d.panel)
            // A fixed-size panel takes the saved top-left, not the saved size.
            #expect(panel.frame.minX == saved.minX)
            #expect(panel.frame.maxY == saved.maxY)
            try await waitForFirstRefresh(d)
        }

        @Test func fitPanelKeepsTopLeftAndSkipsBadOrSameSizes() async throws {
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            launch(d)
            try await waitForFirstRefresh(d)
            pump(0.1)
            let panel = try #require(d.panel)

            let before = panel.frame
            d.fitPanel(to: CGSize(width: 0, height: 120))
            #expect(panel.frame == before)
            d.fitPanel(to: CGSize(width: 120, height: 0))
            #expect(panel.frame == before)
            d.fitPanel(to: before.size)
            #expect(panel.frame == before)

            d.fitPanel(to: CGSize(width: 250, height: 150))
            #expect(panel.frame.size == CGSize(width: 250, height: 150))
            #expect(panel.frame.minX == before.minX)
            #expect(panel.frame.maxY == before.maxY)
        }

        @Test func updateRoomTracksPanelAndIgnoresTinyChanges() async throws {
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            launch(d)
            try await waitForFirstRefresh(d)
            pump(0.1)
            let panel = try #require(d.panel)
            guard let f = NSScreen.main?.visibleFrame, panel.screen == NSScreen.main else { return }

            // Top edge 400pt above the bottom of the usable screen: 400pt of room.
            panel.setFrameTopLeftPoint(NSPoint(x: f.minX + 10, y: f.minY + 400))
            d.room.height = 1
            d.updateRoom()
            #expect(abs(d.room.height - 400) < 0.01)

            // Within a point of the real value: left alone.
            let near: CGFloat = 399.5
            d.room.height = near
            d.updateRoom()
            #expect(d.room.height == near)
        }

        @Test func moveAndScreenChangesUpdateRoom() async throws {
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            launch(d)
            try await waitForFirstRefresh(d)
            pump(0.1)
            let panel = try #require(d.panel)

            let before = d.room.height

            // Moving the panel down 100pt leaves 100pt less room below it.
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: panel.frame.minY - 100))
            pump(0.1)
            #expect(abs(d.room.height - (before - 100)) < 0.01)

            // Screen shape changes recheck it too.
            d.room.height = 1
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            pump(0.1)
            #expect(abs(d.room.height - (before - 100)) < 0.01)

            // So does the panel moving to another screen.
            d.room.height = 1
            NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: panel)
            pump(0.1)
            #expect(abs(d.room.height - (before - 100)) < 0.01)
        }

        // Older macOS lacks the cricket ball symbol: the next name is used instead.
        @Test func statusIconFallsBack() {
            #expect(AppDelegate.statusIcon(["no.such.symbol.here", "sportscourt"]) != nil)
            #expect(AppDelegate.statusIcon(["no.such.symbol.here"]) == nil)
        }

        @Test func updateRoomUsesMainScreenWhenPanelIsOffScreen() async throws {
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            launch(d)
            try await waitForFirstRefresh(d)
            pump(0.1)
            let panel = try #require(d.panel)

            guard let f = NSScreen.main?.visibleFrame else { return }

            // Far off to the side (no screen), top edge 250pt above the main screen's usable bottom.
            panel.setFrameTopLeftPoint(NSPoint(x: -50000, y: f.minY + 250))
            #expect(panel.screen == nil)
            d.room.height = 1
            d.updateRoom()
            #expect(abs(d.room.height - 250) < 0.01)
        }

        @Test func togglePanelHidesAndShows() async throws {
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            launch(d)
            try await waitForFirstRefresh(d)
            let panel = try #require(d.panel)

            #expect(panel.isVisible)
            d.togglePanel()
            #expect(!panel.isVisible)
            d.togglePanel()
            #expect(panel.isVisible)
        }

        // The screen observers are never removed, so they must hold the delegate weakly
        // or it (and its store and refresh loop) would live on. Not a check on the resize
        // callback: tearDown drops the panel's content, which would free that either way.
        @Test func launchCallbacksDoNotRetainDelegate() async throws {
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            weak var weakDelegate: AppDelegate?
            do {
                let d = makeDelegate(temp)
                weakDelegate = d
                launch(d)
                try await waitForFirstRefresh(d)
                pump(0.1)
                tearDown(d)
            }
            // AppKit and SwiftUI let go a moment later, once autoreleased objects drain.
            for _ in 0..<60 where weakDelegate != nil {
                pump(0.05)
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(weakDelegate == nil)
        }
    }
}
