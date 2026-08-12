import AppKit
import EyePetCore
import Foundation

/// Tracks screen lock / sleep / screensaver so the engine can treat them as hard absence.
///
/// These are notification-driven rather than polled because there is no public API to
/// query "is the screen locked" directly. Consequence: state is only correct from launch
/// onward — we assume unlocked and awake at startup, which is true in practice since the
/// app is launched by a logged-in session.
@MainActor
final class SessionMonitor {
    private(set) var screenLocked = false
    private(set) var displayAsleep = false
    private(set) var screensaverActive = false

    private var observers: [NSObjectProtocol] = []

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        func observe(
            _ center: NotificationCenter,
            _ name: NSNotification.Name,
            _ handler: @escaping @MainActor () -> Void
        ) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            })
        }

        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.displayAsleep = true
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.displayAsleep = false
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.displayAsleep = true
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.displayAsleep = false
        }

        // Lock state has no public API; the distributed notifications are the
        // long-standing convention and are not sandbox-safe. See TODO.md.
        observe(distributed, .init("com.apple.screenIsLocked")) { [weak self] in
            self?.screenLocked = true
        }
        observe(distributed, .init("com.apple.screenIsUnlocked")) { [weak self] in
            self?.screenLocked = false
        }
        observe(distributed, .init("com.apple.screensaver.didstart")) { [weak self] in
            self?.screensaverActive = true
        }
        observe(distributed, .init("com.apple.screensaver.didstop")) { [weak self] in
            self?.screensaverActive = false
        }
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for observer in observers {
            workspace.removeObserver(observer)
            distributed.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// Builds the pure input the engine consumes.
    func sample() -> PresenceSample {
        PresenceSample(
            clocks: .sample(),
            displaySleepPrevented: PowerAssertions.isDisplaySleepPrevented(),
            screenLocked: screenLocked,
            displayAsleep: displayAsleep,
            screensaverActive: screensaverActive
        )
    }
}
