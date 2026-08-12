import XCTest
@testable import EyePetCore

/// The engine is pure, so a simulated workday runs in microseconds.
final class BreakEngineTests: XCTestCase {
    private func clocks(idle: TimeInterval) -> IdleClocks {
        IdleClocks(
            anyInput: idle,
            keyDown: idle,
            mouseClick: idle,
            mouseMoved: idle,
            scrollWheel: idle
        )
    }

    private func sample(idle: TimeInterval, displayAwake: Bool = false, locked: Bool = false) -> PresenceSample {
        PresenceSample(
            clocks: clocks(idle: idle),
            displaySleepPrevented: displayAwake,
            screenLocked: locked
        )
    }

    // MARK: - Classification

    func testRecentInputIsActive() {
        XCTAssertEqual(PresenceClassifier.classify(sample(idle: 2)), .active)
    }

    /// The failure this whole design exists to fix: idle input but a video playing
    /// must NOT read as absent, because that is peak screen time.
    func testIdleWithDisplayAssertionIsPassiveNotAbsent() {
        XCTAssertEqual(PresenceClassifier.classify(sample(idle: 600, displayAwake: true)), .passive)
    }

    func testIdleWithNoAssertionIsAbsent() {
        XCTAssertEqual(PresenceClassifier.classify(sample(idle: 600)), .absent)
    }

    /// A stale power assertion must not outvote a locked screen.
    func testLockedScreenBeatsDisplayAssertion() {
        XCTAssertEqual(
            PresenceClassifier.classify(sample(idle: 5, displayAwake: true, locked: true)),
            .absent
        )
    }

    // MARK: - Accrual

    func testBreakFiresAfterWorkInterval() {
        let engine = BreakEngine(schedule: .init(workInterval: 60, breakDuration: 10, warningLead: 5))
        for _ in 0..<59 { engine.tick(delta: 1, sample: sample(idle: 1)) }
        guard case .working = engine.phase else { return XCTFail("expected still working, got \(engine.phase)") }

        engine.tick(delta: 1, sample: sample(idle: 1))
        guard case .warning = engine.phase else { return XCTFail("expected warning, got \(engine.phase)") }
    }

    func testPassiveViewingStillAccrues() {
        let engine = BreakEngine(schedule: .init(workInterval: 30, breakDuration: 5, warningLead: 1))
        for _ in 0..<30 { engine.tick(delta: 1, sample: sample(idle: 600, displayAwake: true)) }
        guard case .warning = engine.phase else {
            return XCTFail("watching a video should still earn a break, got \(engine.phase)")
        }
    }

    func testAbsenceDecaysAccruedTime() {
        let engine = BreakEngine(schedule: .init(workInterval: 100, breakDuration: 5))
        for _ in 0..<50 { engine.tick(delta: 1, sample: sample(idle: 1)) }
        XCTAssertEqual(engine.accrued, 50, accuracy: 0.001)

        // Default decay is 2x, so 10s away should burn 20s of accrued load.
        for _ in 0..<10 { engine.tick(delta: 1, sample: sample(idle: 600)) }
        XCTAssertEqual(engine.accrued, 30, accuracy: 0.001)
    }

    /// Never ambush an empty desk: if the break comes due while they are away,
    /// bank the absence instead of queueing an interruption for their return.
    func testBreakDueWhileAbsentResetsInsteadOfFiring() {
        let engine = BreakEngine(schedule: .init(workInterval: 10, breakDuration: 5))
        engine.policy = AccrualPolicy(absentDecayPerSecond: 0)
        for _ in 0..<10 { engine.tick(delta: 1, sample: sample(idle: 1)) }
        guard case .warning = engine.phase else { return XCTFail("expected warning") }

        let other = BreakEngine(schedule: .init(workInterval: 10, breakDuration: 5))
        other.policy = AccrualPolicy(absentDecayPerSecond: 0)
        for _ in 0..<9 { other.tick(delta: 1, sample: sample(idle: 1)) }
        other.tick(delta: 1, sample: sample(idle: 600))
        guard case .working = other.phase else {
            return XCTFail("should not fire a break at an empty desk, got \(other.phase)")
        }
    }

    // MARK: - Delta clamping

    /// After a system sleep a wall-clock delta can be hours wide. One tick must not
    /// fast-forward accrual past `maxTickDelta` worth of weighted time.
    func testHugeDeltaDuringWorkingClampsAccrual() {
        let engine = BreakEngine(schedule: .init(workInterval: 1000, breakDuration: 10))
        engine.tick(delta: 7200, sample: sample(idle: 1))
        XCTAssertEqual(engine.accrued, engine.policy.maxTickDelta, accuracy: 0.001)
    }

    /// Same clamp, but during a break: a huge delta must not complete the break in
    /// one tick.
    func testHugeDeltaDuringRestingDoesNotCompleteBreakInOneTick() {
        let engine = BreakEngine(schedule: .init(workInterval: 5, breakDuration: 30, warningLead: 1))
        for _ in 0..<6 { engine.tick(delta: 1, sample: sample(idle: 1)) }
        guard case .resting = engine.phase else { return XCTFail("expected resting, got \(engine.phase)") }

        engine.tick(delta: 7200, sample: sample(idle: 1))
        guard case let .resting(remaining) = engine.phase else {
            return XCTFail("a single huge tick should not finish a 30s break, got \(engine.phase)")
        }
        XCTAssertEqual(remaining, 30 - engine.policy.maxTickDelta, accuracy: 0.001)
    }

    /// A negative delta (clock skew) should be clamped to zero rather than rewinding
    /// state or crashing.
    func testNegativeDeltaChangesNothing() {
        let engine = BreakEngine(schedule: .init(workInterval: 60, breakDuration: 10))
        for _ in 0..<10 { engine.tick(delta: 1, sample: sample(idle: 1)) }
        let accruedBefore = engine.accrued
        let phaseBefore = engine.phase

        engine.tick(delta: -50, sample: sample(idle: 1))

        XCTAssertEqual(engine.accrued, accruedBefore, accuracy: 0.001)
        XCTAssertEqual(engine.phase, phaseBefore)
    }

    // MARK: - Compliance

    func testStillnessThroughBreakEarnsPraise() {
        let engine = BreakEngine(schedule: .init(workInterval: 5, breakDuration: 10, warningLead: 1))
        for _ in 0..<6 { engine.tick(delta: 1, sample: sample(idle: 1)) }
        for _ in 0..<11 { engine.tick(delta: 1, sample: sample(idle: 300, displayAwake: true)) }
        XCTAssertEqual(engine.phase, .praise)
    }

    func testTypingThroughBreakIsIgnored() {
        let engine = BreakEngine(schedule: .init(workInterval: 5, breakDuration: 10, warningLead: 1))
        for _ in 0..<6 { engine.tick(delta: 1, sample: sample(idle: 1)) }
        for _ in 0..<11 { engine.tick(delta: 1, sample: sample(idle: 0.2)) }
        XCTAssertEqual(engine.phase, .ignored)
    }

    // MARK: - Mood

    func testMoodFollowsActivityTexture() {
        let typing = IdleClocks(anyInput: 1, keyDown: 1, mouseClick: 90, mouseMoved: 40, scrollWheel: 90)
        XCTAssertEqual(
            PetMoodResolver.mood(phase: .working(progress: 0.2), presence: .active, clocks: typing),
            .busy
        )

        let scrolling = IdleClocks(anyInput: 1, keyDown: 90, mouseClick: 60, mouseMoved: 1, scrollWheel: 1)
        XCTAssertEqual(
            PetMoodResolver.mood(phase: .working(progress: 0.2), presence: .active, clocks: scrolling),
            .grazing
        )

        XCTAssertEqual(
            PetMoodResolver.mood(phase: .working(progress: 0.2), presence: .absent, clocks: scrolling),
            .asleep
        )
        XCTAssertEqual(
            PetMoodResolver.mood(phase: .resting(remaining: 3), presence: .active, clocks: typing),
            .coaxing
        )
    }
}
