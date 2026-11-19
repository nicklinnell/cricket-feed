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

        func expectedRoom(_ panel: NSPanel) -> CGFloat {
            panel.frame.maxY - (panel.screen ?? NSScreen.main!).visibleFrame.minY
        }

        @Test func floatingPanelSetup() {
            NSWindow.removeFrame(usingName: Self.frameName)
            let content = NSView()
            let panel = FloatingPanel(content: content)
            defer { panel.setFrameAutosaveName(""); NSWindow.removeFrame(usingName: Self.frameName) }
            #expect(panel.canBecomeKey)
            #expect(panel.level == .floating)
            #expect(panel.isFloatingPanel)
            #expect(!panel.hidesOnDeactivate)
            #expect(panel.isMovableByWindowBackground)
            #expect(!panel.isOpaque)
            #expect(panel.hasShadow)
            #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
            #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
            #expect(panel.styleMask.contains(.nonactivatingPanel))
            #expect(panel.contentView === content)
            #expect(panel.frameAutosaveName == Self.frameName)
        }

        @Test func defaultInitUsesItsOwnStoreAndDoesNothingWithoutAPanel() {
            // Default store, never launched, so nothing starts.
            let d = AppDelegate()
            #expect(d.panel == nil)
            #expect(d.store.error == nil)
            // Guards: no panel means no resize and no room change.
            d.fitPanel(to: CGSize(width: 100, height: 100))
            d.updateRoom()
            #expect(d.room.height == 800)
            #expect(d.panel == nil)
        }

        @Test func firstLaunchPlacesPanelTopRight() async throws {
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

            let panel = try #require(d.panel)
            let screen = try #require(NSScreen.main)
            let f = screen.visibleFrame
            #expect(panel.frame.minX == f.maxX - 320)
            #expect(panel.frame.maxY == f.maxY - 20)
            #expect(panel.isVisible)
            #expect(d.room.height == expectedRoom(panel))

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
            #expect(panel.frame.minX == f.maxX - 320)
            #expect(abs(panel.frame.maxY - (f.maxY - 20)) < 1)
            #expect(panel.frame.size != CGSize(width: 300, height: 200))
        }

        @Test func launchRestoresSavedFrame() async throws {
            let screen = try #require(NSScreen.main)
            let f = screen.visibleFrame
            let saved = NSRect(x: f.minX + 40, y: f.minY + 60, width: 280, height: 300)
            // Save a frame under the panel's name, as a previous run would have.
            let old = NSWindow(contentRect: saved, styleMask: [.borderless], backing: .buffered, defer: true)
            old.setFrame(saved, display: false)
            old.saveFrame(usingName: Self.frameName)

            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
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
            d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
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
            d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try await waitForFirstRefresh(d)
            pump(0.1)
            let panel = try #require(d.panel)

            d.room.height = 1
            d.updateRoom()
            #expect(d.room.height == expectedRoom(panel))

            // Within a point of the real value: left alone.
            let near = expectedRoom(panel) - 0.5
            d.room.height = near
            d.updateRoom()
            #expect(d.room.height == near)
        }

        @Test func moveAndScreenChangesUpdateRoom() async throws {
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try await waitForFirstRefresh(d)
            pump(0.1)
            let panel = try #require(d.panel)

            // Moving the panel down shrinks the room below it.
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: panel.frame.minY - 100))
            pump(0.1)
            #expect(d.room.height == expectedRoom(panel))

            // Screen shape changes recheck it too.
            d.room.height = 1
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            pump(0.1)
            #expect(d.room.height == expectedRoom(panel))

            // So does the panel moving to another screen.
            d.room.height = 1
            NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: panel)
            pump(0.1)
            #expect(d.room.height == expectedRoom(panel))
        }

        @Test func statusIconFallsBack() {
            #expect(AppDelegate.statusIcon(["no.such.symbol.here", "sportscourt"]) != nil)
            #expect(AppDelegate.statusIcon(["no.such.symbol.here"]) == nil)
            #expect(AppDelegate.statusIcon() != nil)
        }

        @Test func updateRoomUsesMainScreenWhenPanelIsOffScreen() async throws {
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try await waitForFirstRefresh(d)
            pump(0.1)
            let panel = try #require(d.panel)

            panel.setFrameOrigin(NSPoint(x: -50000, y: -50000))
            #expect(panel.screen == nil)
            d.room.height = 1
            d.updateRoom()
            let main = try #require(NSScreen.main)
            #expect(d.room.height == panel.frame.maxY - main.visibleFrame.minY)
        }

        @Test func togglePanelHidesAndShows() async throws {
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            let d = makeDelegate(temp)
            defer { tearDown(d) }
            d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            try await waitForFirstRefresh(d)
            let panel = try #require(d.panel)

            #expect(panel.isVisible)
            d.togglePanel()
            #expect(!panel.isVisible)
            d.togglePanel()
            #expect(panel.isVisible)
        }

        @Test func storeIsFreedAfterTearDown() async throws {
            NSWindow.removeFrame(usingName: Self.frameName)
            let temp = TempDefaults()
            weak var weakStore: ScoreStore?
            weak var weakDelegate: AppDelegate?
            do {
                let d = makeDelegate(temp)
                weakStore = d.store
                weakDelegate = d
                d.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
                try await waitForFirstRefresh(d)
                pump(0.1)
                tearDown(d)
            }
            // SwiftUI and AppKit let go a moment later, once autoreleased objects drain.
            for _ in 0..<60 where weakStore != nil {
                pump(0.05)
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(weakDelegate == nil)
            #expect(weakStore == nil)
        }

        @Test func mainSetsUpAppAndRuns() async throws {
            let app = NSApplication.shared
            let oldDelegate = app.delegate
            let oldPolicy = app.activationPolicy()
            let oldFactory = Main.makeDelegate
            NSWindow.removeFrame(usingName: Self.frameName)

            // The default factory gives a plain delegate.
            #expect(oldFactory().panel == nil)

            let temp = TempDefaults()
            var made: AppDelegate?
            Main.makeDelegate = { [self] in
                let d = makeDelegate(temp)
                made = d
                return d
            }
            defer {
                Main.makeDelegate = oldFactory
                app.delegate = oldDelegate
                app.setActivationPolicy(oldPolicy)
            }

            // Stop the run loop that main() starts, then wake it so run() returns.
            let stopper = Timer(timeInterval: 0.3, repeats: false) { _ in
                MainActor.assumeIsolated {
                    NSApp.stop(nil)
                    let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                                  timestamp: 0, windowNumber: 0, context: nil,
                                                  subtype: 0, data1: 0, data2: 0)!
                    NSApp.postEvent(wake, atStart: true)
                }
            }
            RunLoop.main.add(stopper, forMode: .common)
            Main.main()

            let d = try #require(made)
            #expect(app.delegate === d)
            #expect(app.activationPolicy() == .accessory)
            // run() may or may not finish launching in a test process; clean up if it did.
            if d.panel != nil {
                try await waitForFirstRefresh(d)
                tearDown(d)
            }
        }
    }
}
