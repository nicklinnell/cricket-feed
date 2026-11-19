import Foundation
import ServiceManagement

enum LoginItemState: Equatable {
    case on, off
    // Turned on, but the user still has to allow it in System Settings.
    case needsApproval

    // `.notFound` counts as off: registering is what makes macOS find it.
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .on
        case .requiresApproval: self = .needsApproval
        default: self = .off
        }
    }
}

// Whether the app opens when the user logs in. macOS keeps this, not UserDefaults:
// the user can change it in System Settings, and a saved copy would go stale.
protocol LoginItem: AnyObject {
    // False for copies that shouldn't open at login, like a dev build.
    var available: Bool { get }
    var state: LoginItemState { get }
    func set(_ on: Bool) throws
    func openSettings()
}

// Used by tests, `swift test`'s bare process and dev builds, so none of them add a login item.
final class NoLoginItem: LoginItem {
    var available: Bool { false }
    var state: LoginItemState { .off }
    func set(_ on: Bool) throws {}
    func openSettings() {}
}

// The real one, for the installed app.
final class SystemLoginItem: LoginItem {
    var available: Bool { true }
    var state: LoginItemState { LoginItemState(SMAppService.mainApp.status) }

    func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    static func make() -> LoginItem {
        isInstalled(Bundle.main.bundleURL) ? SystemLoginItem() : NoLoginItem()
    }

    // Only an app in an Applications folder. A build folder gets wiped on the next build,
    // so a login item pointing there would break.
    static func isInstalled(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let folder = url.deletingLastPathComponent().standardizedFileURL.path
        return url.pathExtension == "app"
            && (folder == "/Applications" || folder == home.appendingPathComponent("Applications").standardizedFileURL.path)
    }
}
