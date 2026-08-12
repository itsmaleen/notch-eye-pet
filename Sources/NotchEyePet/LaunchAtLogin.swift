import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` for "Launch at login".
///
/// No extra permissions and no persistence of our own: the login item registration
/// *is* the state. Registration can fail quietly on an ad-hoc-signed dev build or when
/// the bare binary is run outside `NotchEyePet.app` (see `Scripts/bundle.sh`), so every
/// call here reads `SMAppService.mainApp.status` back afterwards instead of trusting
/// the request succeeded. The toggle must never show a checkmark that isn't true.
enum LaunchAtLogin {
    /// True only when the service is actually registered and enabled right now.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Attempts to register or unregister, then returns the state actually observed
    /// afterwards, which may not match what was requested.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Swallow it deliberately: `isEnabled` below reports whatever the system
            // actually did, which is what the caller should show.
        }
        return isEnabled
    }
}
