import AppKit
import Combine
import EyePetCore
import Foundation
import SwiftUI

/// Owns the engine, the polling loop, and the published state the views read.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var phase: BreakPhase = .working(progress: 0)
    @Published private(set) var mood: PetMood = .idle
    @Published private(set) var presence: PresenceState = .active
    @Published private(set) var clocks: IdleClocks = .sample()
    @Published private(set) var species: PetSpecies = .dot

    /// Polling cadence. One second is plenty while someone is at the machine — every
    /// signal we read is recency-based, so there is nothing to miss between ticks.
    /// While `.absent` nobody is watching the pet, so back off to save battery; the
    /// engine's `maxTickDelta` clamp means the coarser cadence still accrues/decays
    /// correctly, it just samples less often.
    private let activeTickInterval: TimeInterval = 1.0
    private let absentTickInterval: TimeInterval = 5.0
    private var currentTickInterval: TimeInterval = 1.0

    let engine: BreakEngine
    private let session = SessionMonitor()
    private var preferences: Preferences
    private var timer: Timer?
    private var lastTickAt = Date()

    /// Local break taken/ignored history. Persisted after every recorded outcome;
    /// never leaves the device.
    private var ledger: BreakLedger

    var scheduleName: String = "20-20-20"

    init(schedule: BreakSchedule = .twentyTwentyTwenty, preferences: Preferences = Preferences()) {
        self.preferences = preferences
        engine = BreakEngine(schedule: preferences.schedule ?? schedule)
        ledger = preferences.ledger ?? BreakLedger()
        if let savedName = preferences.scheduleName { scheduleName = savedName }
        if preferences.isPaused { engine.pause() }
        species = preferences.species ?? .dot
    }

    /// Sets and persists the pet's species. Goes through the model, not straight to
    /// `Preferences`, so every observer of `species` (the notch pet, the break panel)
    /// picks up the change the same way a schedule change does.
    func apply(species: PetSpecies) {
        self.species = species
        preferences.species = species
    }

    /// Pause and resume go through the model, not straight to the engine, so the
    /// paused flag persists across launches.
    func pause() {
        engine.pause()
        preferences.isPaused = true
    }

    func resume() {
        engine.resume()
        preferences.isPaused = false
    }

    func start() {
        session.start()
        lastTickAt = Date()
        scheduleTimer(interval: activeTickInterval)
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        session.stop()
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Keep firing while menus are tracking, otherwise the timer stalls whenever
        // the user has the menu bar item open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        currentTickInterval = interval
    }

    func apply(schedule: BreakSchedule, named name: String) {
        engine.schedule = schedule
        scheduleName = name
        preferences.schedule = schedule
        preferences.scheduleName = name
        engine.skip()
        tick()
    }

    private func tick() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTickAt)
        lastTickAt = now

        let sample = session.sample()
        let previousPhase = phase
        let newPhase = engine.tick(delta: delta, sample: sample)
        recordOutcomeIfNeeded(previousPhase: previousPhase, newPhase: newPhase, at: now)
        playBreakSoundIfNeeded(previousPhase: previousPhase, newPhase: newPhase)

        clocks = sample.clocks
        presence = engine.presence
        phase = newPhase
        mood = PetMoodResolver.mood(phase: newPhase, presence: engine.presence, clocks: sample.clocks)

        let desiredInterval = presence == .absent ? absentTickInterval : activeTickInterval
        if desiredInterval != currentTickInterval {
            scheduleTimer(interval: desiredInterval)
        }
    }

    /// Records exactly once per transition into `.praise`/`.ignored`. The engine holds
    /// those phases for a few seconds of ticks so the pet's reaction is visible, so this
    /// compares against the phase before this tick rather than the phase itself —
    /// otherwise every tick spent holding `.praise` would count as another taken break.
    private func recordOutcomeIfNeeded(previousPhase: BreakPhase, newPhase: BreakPhase, at date: Date) {
        guard previousPhase != newPhase else { return }
        let outcome: BreakOutcome
        switch newPhase {
        case .praise: outcome = .taken
        case .ignored: outcome = .ignored
        default: return
        }
        ledger.record(outcome, on: date, calendar: .current)
        preferences.ledger = ledger
    }

    /// Plays exactly once on the transition into `.resting` (only ever reached from
    /// `.warning`, per `BreakEngine.tick`) — `.resting` holds for many ticks as
    /// `remaining` counts down, so this checks the edge rather than the phase itself,
    /// the same reasoning as `recordOutcomeIfNeeded` above. Off unless the user opted
    /// in; see `Preferences.soundEnabled`.
    private func playBreakSoundIfNeeded(previousPhase: BreakPhase, newPhase: BreakPhase) {
        guard preferences.soundEnabled else { return }
        guard case .resting = newPhase, case .warning = previousPhase else { return }
        guard let sound = NSSound(named: "Purr") else { return }
        sound.volume = 0.5
        sound.play()
    }

    // MARK: - Stats, for the menu bar

    /// Taken/ignored breaks so far today.
    var todayBreakCounts: (taken: Int, ignored: Int) {
        ledger.counts(on: Date(), calendar: .current)
    }

    /// Consecutive days ending today with at least one taken break.
    var breakStreak: Int {
        ledger.streak(endingOn: Date(), calendar: .current)
    }

    // MARK: - Human-readable status for the menu bar

    var statusLine: String {
        switch phase {
        case let .working(progress):
            let remaining = engine.schedule.workInterval * (1 - progress)
            return "Next break in \(Self.format(remaining))"
        case let .warning(remaining):
            return "Break in \(Int(remaining.rounded()))s"
        case let .resting(remaining):
            return "Look away, \(Int(remaining.rounded()))s left"
        case .praise: return "Nice one"
        case .ignored: return "You worked through it"
        case .paused: return "Paused"
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let minutes = total / 60
        let secs = total % 60
        return minutes > 0 ? "\(minutes)m \(secs)s" : "\(secs)s"
    }
}
