import Foundation
import ServiceManagement

/// Login-item wrapper around SMAppService.mainApp so the status-item menu
/// can offer an "Open at Login" toggle. Thin on purpose: the only
/// behavior is reading the current status and (un)registering, with
/// errors propagated so callers can notify instead of failing silently.
enum TimberLoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
