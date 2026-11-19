import SwiftUI
import AppKit

// A borderless panel that floats above other windows on every Space.
final class FloatingPanel: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        contentView = content
        setFrameAutosaveName("CricketFeedPanel")
    }

    // Lets the search box take typing.
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store: ScoreStore
    let room = PanelRoom()
    let loginItem: LoginItem
    var panel: FloatingPanel!
    var statusItem: NSStatusItem!
    var loginMenuItem: NSMenuItem!
    // Tests swap this so no alert blocks them.
    var showError: (String) -> Void = { message in
        let alert = NSAlert()
        alert.messageText = "Couldn't change Open at Login"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // Tests pass a store on a throwaway defaults suite and a fake login item.
    init(store: ScoreStore? = nil, loginItem: LoginItem? = nil) {
        self.store = store ?? ScoreStore()
        self.loginItem = loginItem ?? SystemLoginItem.make()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.notifier = SystemNotifier.makeIfBundled()
        if store.notifyMilestones && !store.favourites.isEmpty { store.notifier.requestPermission() }
        let hosting = NSHostingView(rootView: ContentView(store: store, room: room) { [weak self] size in
            self?.fitPanel(to: size)
        })
        hosting.sizingOptions = []
        panel = FloatingPanel(content: hosting)
        if !panel.setFrameUsingName("CricketFeedPanel"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: f.maxX - 320, y: f.maxY - 20))
        }
        panel.orderFrontRegardless()
        updateRoom()

        // Keep the list's height cap in step with where the panel is.
        let nc = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
            nc.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateRoom() }
            }
        }
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateRoom() }
        }

        // Menu bar icon to show/hide and quit (the app has no Dock icon).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.statusIcon()
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show / Hide Scores", action: #selector(togglePanel), keyEquivalent: "s"))
        loginMenuItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
        updateLoginMenuItem()

        store.start()
    }

    // Resize the panel to fit its content, keeping the top-left corner in place.
    func fitPanel(to size: CGSize) {
        guard let panel, size.width > 0, size.height > 0 else { return }
        let old = panel.frame
        let new = NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
        if new != old {
            panel.setFrame(new, display: true)
            panel.invalidateShadow()
        }
    }

    // Space from the panel's top edge down to the bottom of its screen.
    func updateRoom() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let room = panel.frame.maxY - screen.visibleFrame.minY
        if abs(self.room.height - room) > 1 { self.room.height = room }
    }

    // First SF Symbol this macOS has, as older versions lack the cricket ball.
    static func statusIcon(_ names: [String] = ["cricket.ball", "sportscourt"]) -> NSImage? {
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Cricket") { return image }
        }
        return nil
    }

    // Re-read each time, as the user can change it in System Settings.
    func menuNeedsUpdate(_ menu: NSMenu) { updateLoginMenuItem() }

    func updateLoginMenuItem() {
        guard loginItem.available else {
            loginMenuItem.action = nil  // greyed out
            loginMenuItem.state = .off
            loginMenuItem.toolTip = "Only for the copy in Applications"
            return
        }
        let state = loginItem.state
        switch state {
        case .on: loginMenuItem.state = .on
        case .off: loginMenuItem.state = .off
        case .needsApproval: loginMenuItem.state = .mixed
        }
        loginMenuItem.toolTip = state == .needsApproval
            ? "Allow Cricket Feed in System Settings > General > Login Items"
            : nil
    }

    @objc func toggleLoginItem() {
        switch loginItem.state {
        case .on:
            do { try loginItem.set(false) } catch { showError(error.localizedDescription) }
        case .needsApproval:
            // Waiting on the user, so take them to where they allow it.
            loginItem.openSettings()
        case .off:
            do {
                try loginItem.set(true)
                // macOS can hold it until the user allows it, and may not say so straight away.
                if loginItem.state != .on { loginItem.openSettings() }
            } catch {
                // macOS can also throw when the user has to allow it first.
                if loginItem.state == .needsApproval { loginItem.openSettings() } else { showError(error.localizedDescription) }
            }
        }
        updateLoginMenuItem()
    }

    @objc func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
}

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
