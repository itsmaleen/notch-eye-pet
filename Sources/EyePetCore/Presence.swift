import Foundation

/// Whether the human is at the machine, and if so whether their eyes are working.
///
/// This three-state split — rather than the usual binary idle/not-idle — is the
/// substantive fix for break-timer accuracy. See `docs/` in the repo root and
/// the wiki page `macos_presence_detection`.
public enum PresenceState: String, Sendable, Equatable, CaseIterable {
    /// Nobody there: idle past threshold with nothing holding the display awake,
    /// or the screen is locked / asleep / running a screensaver.
    case absent
    /// No input, but the display is being held awake — video, a long read.
    /// Still screen time. The eyes are working even though the hands are not.
    case passive
    /// Recent input.
    case active
}

/// Everything the classifier needs, as plain data, so classification is a pure
/// function and can be unit-tested without a Mac session at all.
public struct PresenceSample: Sendable, Equatable {
    public let clocks: IdleClocks
    public let displaySleepPrevented: Bool
    public let screenLocked: Bool
    public let displayAsleep: Bool
    public let screensaverActive: Bool

    public init(
        clocks: IdleClocks,
        displaySleepPrevented: Bool,
        screenLocked: Bool = false,
        displayAsleep: Bool = false,
        screensaverActive: Bool = false
    ) {
        self.clocks = clocks
        self.displaySleepPrevented = displaySleepPrevented
        self.screenLocked = screenLocked
        self.displayAsleep = displayAsleep
        self.screensaverActive = screensaverActive
    }
}

public struct PresenceThresholds: Sendable, Equatable {
    /// Input silence beyond this is no longer "active".
    public let idleAfter: TimeInterval

    public init(idleAfter: TimeInterval = 90) {
        self.idleAfter = idleAfter
    }

    public static let `default` = PresenceThresholds()
}

public enum PresenceClassifier {
    public static func classify(
        _ sample: PresenceSample,
        thresholds: PresenceThresholds = .default
    ) -> PresenceState {
        // Hard absence beats everything: a locked or sleeping screen cannot be watched.
        // Checked first because a stale power assertion can outlive a lock.
        if sample.screenLocked || sample.displayAsleep || sample.screensaverActive {
            return .absent
        }
        if sample.clocks.anyInput <= thresholds.idleAfter {
            return .active
        }
        return sample.displaySleepPrevented ? .passive : .absent
    }
}
