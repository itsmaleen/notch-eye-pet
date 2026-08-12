import Foundation

/// How often to nudge, and for how long.
///
/// Deliberately configurable and deliberately not marketed as "clinically proven".
/// Johnson & Rosenfield (Optom Vis Sci 2023;100(1):52-56) tested breaks at 5/10/20/40
/// minutes and found no measurable difference in symptoms — the specific numbers are
/// folklore, traceable to a media soundbite rather than a trial. What the evidence does
/// support (Talens-Estarelles, Cont Lens Anterior Eye 2023) is that *sustained* reminding
/// improves dry-eye scores, and that the benefit disappears within a week of stopping.
///
/// So: the numbers are a preference, and retention is the product.
public struct BreakSchedule: Sendable, Equatable {
    /// Screen-time seconds that must accrue before a break is due.
    public let workInterval: TimeInterval
    /// How long the break lasts.
    public let breakDuration: TimeInterval
    /// How long the pet peeks out before the break actually starts.
    public let warningLead: TimeInterval

    public init(workInterval: TimeInterval, breakDuration: TimeInterval, warningLead: TimeInterval = 10) {
        self.workInterval = workInterval
        self.breakDuration = breakDuration
        self.warningLead = warningLead
    }

    /// The rule the optometrist quoted: every 20 minutes, look 20 feet away for 20 seconds.
    public static let twentyTwentyTwenty = BreakSchedule(
        workInterval: 20 * 60,
        breakDuration: 20,
        warningLead: 10
    )

    /// A much lighter touch: a few seconds every hour. Lower compliance cost,
    /// which by the retention argument may beat a "better" schedule that gets disabled.
    public static let hourlyMicro = BreakSchedule(
        workInterval: 60 * 60,
        breakDuration: 10,
        warningLead: 5
    )

    /// Short cycle for development — you do not want to wait 20 minutes to see the UI.
    public static let debugFast = BreakSchedule(
        workInterval: 20,
        breakDuration: 5,
        warningLead: 3
    )
}

/// Tuning for how screen time accrues in each presence state.
public struct AccrualPolicy: Sendable, Equatable {
    /// Multiplier applied while `.active`.
    public let activeWeight: Double
    /// Multiplier applied while `.passive`. Video still tires the eyes, but blink rate
    /// during passive viewing differs from active work, so this is left tunable.
    public let passiveWeight: Double
    /// Accrued time bled off per second of absence — stepping away is itself a break.
    public let absentDecayPerSecond: Double
    /// Largest `delta` a single `tick` will honour. A wall-clock-derived delta can be
    /// hours wide after a system sleep; without this, one tick would fast-forward
    /// accrual and phase countdowns as if the whole gap were spent at the screen.
    /// 10s covers the 5s absent-backoff tick cadence (see `AppModel`) with headroom.
    public let maxTickDelta: TimeInterval

    public init(
        activeWeight: Double = 1.0,
        passiveWeight: Double = 1.0,
        absentDecayPerSecond: Double = 2.0,
        maxTickDelta: TimeInterval = 10
    ) {
        self.activeWeight = activeWeight
        self.passiveWeight = passiveWeight
        self.absentDecayPerSecond = absentDecayPerSecond
        self.maxTickDelta = maxTickDelta
    }

    public static let `default` = AccrualPolicy()

    public func weight(for state: PresenceState) -> Double {
        switch state {
        case .active: activeWeight
        case .passive: passiveWeight
        case .absent: -absentDecayPerSecond
        }
    }
}
