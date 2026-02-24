import ServiceManagement

final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                SettingsService.shared.launchAtLogin = newValue
            } catch {
                NSLog("[PathPal] Launch at login error: %@", error.localizedDescription)
            }
        }
    }
}
