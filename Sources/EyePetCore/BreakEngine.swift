import Foundation

/// What the app is currently doing about breaks.
public enum BreakPhase: Sendable, Equatable {
    /// Accruing screen time. `progress` is 0...1 toward the next break.
    case working(progress: Double)
    /// Break is imminent; the pet peeks out. `remaining` counts down to the break.
    case warning(remaining: TimeInterval)
    /// Break in progress. `remaining` counts down to the end.
    case resting(remaining: TimeInterval)
    /// Break just finished and the user actually stopped touching the machine.
    case praise
    /// Break just finished but they typed straight through it.
    case ignored
    /// Explicitly paused by the user.
    case paused

    public var isBreakVisible: Bool {
        switch self {
        case .warning, .resting, .praise, .ignored: true
        case .working, .paused: false
        }
    }
}

/// Drives break scheduling from presence samples. Pure: no timers, no AppKit, no I/O —
/// `tick` is called with an elapsed delta, so tests can run a simulated day in microseconds.
public final class BreakEngine {
    public private(set) var phase: BreakPhase = .working(progress: 0)
    public private(set) var accrued: TimeInterval = 0
    public private(set) var presence: PresenceState = .active

    public var schedule: BreakSchedule
    public var policy: AccrualPolicy
    public var thresholds: PresenceThresholds

    /// Fraction of the break the user must leave the input devices alone for it to count.
    /// This is the tier-0 compliance proxy: we cannot see the eyes, but we can see that
    /// the hands stopped. Head-yaw confirmation is the opt-in camera lane's job.
    public var complianceFraction: Double = 0.8

    private var phaseElapsed: TimeInterval = 0
    /// Seconds of the current break during which no input arrived.
    private var restStillness: TimeInterval = 0
    private var isPaused = false

    public init(
        schedule: BreakSchedule = .twentyTwentyTwenty,
        policy: AccrualPolicy = .default,
        thresholds: PresenceThresholds = .default
    ) {
        self.schedule = schedule
        self.policy = policy
        self.thresholds = thresholds
    }

    public func pause() {
        isPaused = true
        phase = .paused
    }

    public func resume() {
        isPaused = false
        phaseElapsed = 0
        phase = .working(progress: progressFraction)
    }

    /// Skip the pending break. Counts as ignored, and resets the clock.
    public func skip() {
        accrued = 0
        phaseElapsed = 0
        restStillness = 0
        phase = .working(progress: 0)
    }

    /// Force a break right now.
    public func breakNow() {
        accrued = schedule.workInterval
        phaseElapsed = 0
        restStillness = 0
        phase = .warning(remaining: schedule.warningLead)
    }

    private var progressFraction: Double {
        guard schedule.workInterval > 0 else { return 0 }
        return min(1, max(0, accrued / schedule.workInterval))
    }

    /// Advance the state machine by `delta` seconds given a fresh presence sample.
    @discardableResult
    public func tick(delta rawDelta: TimeInterval, sample: PresenceSample) -> BreakPhase {
        guard !isPaused else { return phase }

        // Clamp before doing anything else: a wall-clock delta can be negative (clock
        // adjustment) or hours wide (system sleep), and neither should reach the phase
        // math below.
        let delta = min(max(rawDelta, 0), policy.maxTickDelta)

        presence = PresenceClassifier.classify(sample, thresholds: thresholds)
        phaseElapsed += delta

        switch phase {
        case .working:
            accrued = max(0, accrued + delta * policy.weight(for: presence))
            if accrued >= schedule.workInterval {
                // Never ambush someone who is not there. If they are already away,
                // the absence is itself the break — bank it and reset.
                if presence == .absent {
                    accrued = 0
                    phase = .working(progress: 0)
                } else {
                    phaseElapsed = 0
                    phase = .warning(remaining: schedule.warningLead)
                }
            } else {
                phase = .working(progress: progressFraction)
            }

        case .warning:
            let remaining = schedule.warningLead - phaseElapsed
            if remaining <= 0 {
                phaseElapsed = 0
                restStillness = 0
                phase = .resting(remaining: schedule.breakDuration)
            } else {
                phase = .warning(remaining: remaining)
            }

        case .resting:
            // Input during the break means they worked through it.
            if sample.clocks.anyInput > delta { restStillness += delta }
            let remaining = schedule.breakDuration - phaseElapsed
            if remaining <= 0 {
                let required = schedule.breakDuration * complianceFraction
                phase = restStillness >= required ? .praise : .ignored
                phaseElapsed = 0
                accrued = 0
            } else {
                phase = .resting(remaining: remaining)
            }

        case .praise, .ignored:
            // Hold the reaction briefly, then go back to work.
            if phaseElapsed >= 4 {
                phaseElapsed = 0
                phase = .working(progress: 0)
            }

        case .paused:
            break
        }

        return phase
    }
}
