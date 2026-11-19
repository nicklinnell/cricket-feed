import AppKit
import Foundation
import Testing
@testable import CricketFeed

// Records what the app asks of the login item, standing in for macOS.
final class FakeLoginItem: LoginItem {
    var state: LoginItemState = .off
    // What turning it on leaves it as: on, or waiting for the user to allow it.
    var stateWhenOn: LoginItemState = .on
    var failure: Error?
    var sets: [Bool] = []
    var settingsOpened = 0

    func set(_ on: Bool) throws {
        sets.append(on)
        if let failure { throw failure }
        state = on ? stateWhenOn : .off
    }

    func openSettings() { settingsOpened += 1 }
}

struct LoginItemFailure: LocalizedError {
    var errorDescription: String? { "Not allowed" }
}

@MainActor @Suite struct LoginItemMenu {
    let fake = FakeLoginItem()
    // Just the menu bits; no panel or refresh loop.
    func makeDelegate() -> (AppDelegate, () -> [String]) {
        let d = AppDelegate(store: ScoreStore(defaults: TempDefaults().defaults), loginItem: fake)
        d.loginMenuItem = NSMenuItem(title: "Open at Login", action: nil, keyEquivalent: "")
        var errors: [String] = []
        d.showError = { errors.append($0) }
        return (d, { errors })
    }

    @Test func tickFollowsMacOS() {
        let (d, _) = makeDelegate()
        d.updateLoginMenuItem()
        #expect(d.loginMenuItem.state == .off)
        #expect(d.loginMenuItem.toolTip == nil)

        // Changed in System Settings while the app ran: re-read when the menu opens.
        fake.state = .on
        d.menuNeedsUpdate(NSMenu())
        #expect(d.loginMenuItem.state == .on)

        fake.state = .needsApproval
        d.menuNeedsUpdate(NSMenu())
        #expect(d.loginMenuItem.state == .mixed)
        #expect(d.loginMenuItem.toolTip?.contains("Login Items") == true)
    }

    @Test func clickTurnsItOnThenOff() {
        let (d, errors) = makeDelegate()
        d.toggleLoginItem()
        #expect(fake.sets == [true])
        #expect(d.loginMenuItem.state == .on)
        #expect(fake.settingsOpened == 0)

        d.toggleLoginItem()
        #expect(fake.sets == [true, false])
        #expect(d.loginMenuItem.state == .off)
        #expect(errors().isEmpty)
    }

    // macOS can hold a new login item until the user allows it.
    @Test func waitingForApprovalOpensSettings() {
        let (d, _) = makeDelegate()
        fake.stateWhenOn = .needsApproval
        d.toggleLoginItem()
        #expect(fake.settingsOpened == 1)
        #expect(d.loginMenuItem.state == .mixed)

        // Clicking again while it waits turns it off.
        d.toggleLoginItem()
        #expect(fake.sets == [true, false])
        #expect(d.loginMenuItem.state == .off)
    }

    @Test func failureShowsErrorAndLeavesTickAlone() {
        let (d, errors) = makeDelegate()
        fake.failure = LoginItemFailure()
        d.toggleLoginItem()
        #expect(errors() == ["Not allowed"])
        #expect(d.loginMenuItem.state == .off)
    }

    // swift test has no app bundle, so it must never touch the real login items.
    @Test func bareProcessGetsNoLoginItem() throws {
        #expect(SystemLoginItem.makeIfBundled() is NoLoginItem)
        let none = NoLoginItem()
        #expect(none.state == .off)
        try none.set(true)
        none.openSettings()
        #expect(none.state == .off)
        let app = try #require(Bundle(path: "/System/Applications/Calculator.app"))
        #expect(SystemLoginItem.makeIfBundled(app) is SystemLoginItem)
    }
}
