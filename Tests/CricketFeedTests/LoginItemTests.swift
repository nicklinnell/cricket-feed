import AppKit
import Foundation
import ServiceManagement
import Testing
@testable import CricketFeed

// Records what the app asks of the login item, standing in for macOS.
final class FakeLoginItem: LoginItem {
    var available = true
    var state: LoginItemState = .off
    // What turning it on leaves it as: on, or waiting for the user to allow it.
    var stateWhenOn: LoginItemState = .on
    var failure: Error?
    // What a failed call leaves it as.
    var stateOnFailure: LoginItemState?
    var sets: [Bool] = []
    var settingsOpened = 0

    func set(_ on: Bool) throws {
        sets.append(on)
        if let failure {
            if let stateOnFailure { state = stateOnFailure }
            throw failure
        }
        state = on ? stateWhenOn : .off
    }

    func openSettings() { settingsOpened += 1 }
}

struct LoginItemFailure: LocalizedError {
    var errorDescription: String? { "Not allowed" }
}

@MainActor @Suite struct LoginItemMenu {
    let fake = FakeLoginItem()
    let temp = TempDefaults()

    // Just the menu bits; no panel or refresh loop.
    func makeDelegate() -> (AppDelegate, () -> [String]) {
        let d = AppDelegate(store: ScoreStore(defaults: temp.defaults), loginItem: fake)
        d.loginMenuItem = NSMenuItem(title: "Open at Login", action: #selector(AppDelegate.toggleLoginItem), keyEquivalent: "")
        var errors: [String] = []
        d.showError = { errors.append($0) }
        return (d, { errors })
    }

    @Test func tickFollowsMacOS() {
        let (d, _) = makeDelegate()
        d.updateLoginMenuItem()
        #expect(d.loginMenuItem.state == .off)
        #expect(d.loginMenuItem.toolTip == nil)
        #expect(d.loginMenuItem.action == #selector(AppDelegate.toggleLoginItem))

        // Changed in System Settings while the app ran: re-read when the menu opens.
        fake.state = .on
        d.menuNeedsUpdate(NSMenu())
        #expect(d.loginMenuItem.state == .on)

        fake.state = .needsApproval
        d.menuNeedsUpdate(NSMenu())
        #expect(d.loginMenuItem.state == .mixed)
        #expect(d.loginMenuItem.toolTip?.contains("Login Items") == true)
    }

    // A dev build can't be a login item: greyed out, so a click can't register it.
    @Test func greyedOutWhenNotInstalled() {
        let (d, _) = makeDelegate()
        fake.available = false
        d.updateLoginMenuItem()
        #expect(d.loginMenuItem.action == nil)
        #expect(d.loginMenuItem.state == .off)
        #expect(d.loginMenuItem.toolTip == "Only for the copy in Applications")
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
        let (d, errors) = makeDelegate()
        fake.stateWhenOn = .needsApproval
        d.toggleLoginItem()
        #expect(fake.settingsOpened == 1)
        #expect(d.loginMenuItem.state == .mixed)

        // Clicking the dash takes them to Settings again and keeps the request.
        d.toggleLoginItem()
        #expect(fake.sets == [true])
        #expect(fake.settingsOpened == 2)
        #expect(d.loginMenuItem.state == .mixed)
        #expect(errors().isEmpty)
    }

    // macOS may not have caught up when register() returns: still send them to Settings.
    @Test func notOnYetOpensSettings() {
        let (d, _) = makeDelegate()
        fake.stateWhenOn = .off
        d.toggleLoginItem()
        #expect(fake.settingsOpened == 1)
    }

    // register() can throw when the user has to allow it first. That's not an error to show.
    @Test func throwWhileNeedingApprovalOpensSettings() {
        let (d, errors) = makeDelegate()
        fake.failure = LoginItemFailure()
        fake.stateOnFailure = .needsApproval
        d.toggleLoginItem()
        #expect(errors().isEmpty)
        #expect(fake.settingsOpened == 1)
        #expect(d.loginMenuItem.state == .mixed)
    }

    @Test func failureShowsErrorAndLeavesTickAlone() {
        let (d, errors) = makeDelegate()
        fake.failure = LoginItemFailure()
        d.toggleLoginItem()
        #expect(errors() == ["Not allowed"])
        #expect(fake.settingsOpened == 0)
        #expect(d.loginMenuItem.state == .off)

        // Same when turning it off fails.
        fake.state = .on
        d.toggleLoginItem()
        #expect(fake.sets == [true, false])
        #expect(errors() == ["Not allowed", "Not allowed"])
        #expect(d.loginMenuItem.state == .on)
    }

    @Test func macOSStatusMapsToState() {
        #expect(LoginItemState(.enabled) == .on)
        #expect(LoginItemState(.requiresApproval) == .needsApproval)
        #expect(LoginItemState(.notRegistered) == .off)
        #expect(LoginItemState(.notFound) == .off)
    }

    // Only the copy in an Applications folder; never a build folder or swift test.
    @Test func onlyTheInstalledAppIsALoginItem() throws {
        let home = URL(fileURLWithPath: "/Users/someone")
        let installed = { SystemLoginItem.isInstalled(URL(fileURLWithPath: $0), home: home) }
        #expect(installed("/Applications/CricketFeed.app"))
        #expect(installed("/Users/someone/Applications/CricketFeed.app"))
        #expect(!installed("/Users/someone/repo/build/CricketFeed.app"))
        #expect(!installed("/Applications/Tools/CricketFeed.app"))
        #expect(!installed("/Applications/CricketFeed"))
        #expect(!installed("/Users/other/Applications/CricketFeed.app"))

        #expect(SystemLoginItem.make() is NoLoginItem)
        let none = NoLoginItem()
        #expect(!none.available)
        try none.set(true)
        none.openSettings()
        #expect(none.state == .off)
    }
}
