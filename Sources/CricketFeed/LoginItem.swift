import Foundation
import ServiceManagement

enum LoginItemState: Equatable {
    case on, off
    // Turned on, but the user still has to allow it in System Settings.
    case needsApproval
}

// Whether the app opens when the user logs in. macOS keeps this, not UserDefaults:
// the user can change it in System Settings, and a saved copy would go stale.
protocol LoginItem: AnyObject {
    var state: LoginItemState { get }
    func set(_ on: Bool) throws
    func openSettings()
}

// Used by tests and by `swift test`'s bare process, so they never add a real login item.
final class NoLoginItem: LoginItem {
    var state: LoginItemState { .off }
    func set(_ on: Bool) throws {}
    func openSettings() {}
}

// The real one. Only works inside a .app.
final class SystemLoginItem: LoginItem {
    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        default: .off
        }
    }

    func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    static func makeIfBundled(_ bundle: Bundle = .main) -> LoginItem {
        bundle.bundleURL.pathExtension == "app" ? SystemLoginItem() : NoLoginItem()
    }
}
