import Foundation

/// The pet's animation state.
///
/// Derived entirely from signals the break engine already collects, so charm costs
/// no extra plumbing — and charm is load-bearing here, since the retention argument
/// is the reason this is a pet in the notch rather than a screen-blurring overlay.
public enum PetMood: String, Sendable, Equatable, CaseIterable {
    /// Nobody home.
    case asleep
    /// Present, working normally.
    case idle
    /// Typing hard.
    case busy
    /// Scrolling with no typing — reading or grazing.
    case grazing
    /// Passive viewing: display held awake, hands off.
    case watching
    /// Break approaching — peeking out of the notch.
    case peeking
    /// Break in progress — fully emerged, pointing away from the screen.
    case coaxing
    /// They actually took the break.
    case delighted
    /// They typed straight through it.
    case sulking
    case paused
}

public enum PetMoodResolver {
    public static func mood(
        phase: BreakPhase,
        presence: PresenceState,
        clocks: IdleClocks
    ) -> PetMood {
        switch phase {
        case .paused: return .paused
        case .warning: return .peeking
        case .resting: return .coaxing
        case .praise: return .delighted
        case .ignored: return .sulking
        case .working: break
        }

        switch presence {
        case .absent: return .asleep
        case .passive: return .watching
        case .active:
            if clocks.isTyping() { return .busy }
            if clocks.isScrolling() { return .grazing }
            return .idle
        }
    }
}
