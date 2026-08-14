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
    @Published private(set) var species: PetSpecies = .dot

    /// The last sampled clocks. Deliberately *not* `@Published`: no view reads it, and
    /// by construction it changes on every single tick, so publishing it emitted an
    /// `objectWillChange` per second that invalidated every SwiftUI observer in the app
    /// to deliver a value nobody was listening for. Kept as plain state because it is
    /// useful when debugging the mood resolver.
    private(set) var clocks: IdleClocks = .sample()

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

    /// Display name of the active schedule, matched against `MenuBarController.presets`
    /// so the menu's checkmark and the settings picker agree about which one is on.
    /// Resolved in `init`.
    var scheduleName: String = ""

    init(schedule: BreakSchedule = .twentyTwentyTwenty, preferences: Preferences = Preferences()) {
        self.preferences = preferences
        let activeSchedule = preferences.schedule ?? schedule
        engine = BreakEngine(schedule: activeSchedule)
        ledger = preferences.ledger ?? BreakLedger()
        // Looked up in the preset table rather than defaulted to a literal. A hardcoded
        // string drifts the moment a preset is renamed, which is exactly what happened:
        // the default read "20-20-20" while the preset was "20-20-20 (20 min / 20 s)",
        // so a fresh install showed "Custom" for what was really the 20-20-20 preset.
        scheduleName = preferences.scheduleName
            ?? MenuBarController.presets.first { $0.schedule == activeSchedule }?.name
            ?? "Custom"
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

    /// Granularity the published `progress` is rounded to.
    ///
    /// The engine recomputes a fresh fraction every tick, so an unrounded value changes
    /// 1200 times over a 20-minute interval: every observer re-renders every second, and
    /// an `.animation(_:value:)` keyed on it is retriggered before the previous one has
    /// settled, so it never stops running. The bar it drives advances about a fiftieth of
    /// a pixel per second, so none of that buys anything visible.
    ///
    /// 1/64 is finer than the pixel grid of the only progress indicator drawn from it
    /// (a 26pt capsule, 52 pixels at 2x), so nothing visible is lost either way.
    private static let progressSteps: Double = 64

    /// Rounds a phase's payload to what the UI can actually show, so phases that would
    /// render identically also *compare* equal and stop churning the view tree.
    ///
    /// The countdowns round to whole seconds because that is exactly how `statusLine`
    /// and `BreakPanelView` print them. Endpoints survive rounding, so the `progress: 1`
    /// hold (break due, waiting for the user to touch something) is not rounded away.
    private static func quantized(_ phase: BreakPhase) -> BreakPhase {
        switch phase {
        case let .working(progress):
            return .working(progress: (progress * progressSteps).rounded() / progressSteps)
        case let .warning(remaining):
            return .warning(remaining: remaining.rounded())
        case let .resting(remaining):
            return .resting(remaining: remaining.rounded())
        case .praise, .ignored, .paused:
            return phase
        }
    }

    private func tick() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTickAt)
        lastTickAt = now

        let sample = session.sample()
        let previousPhase = phase
        let newPhase = Self.quantized(engine.tick(delta: delta, sample: sample))
        recordOutcomeIfNeeded(previousPhase: previousPhase, newPhase: newPhase, at: now)
        playBreakSoundIfNeeded(previousPhase: previousPhase, newPhase: newPhase)

        clocks = sample.clocks
        let newPresence = engine.presence
        let newMood = PetMoodResolver.mood(phase: newPhase, presence: newPresence, clocks: sample.clocks)

        // Assign only on a real change. These are `@Published`, so an unconditional
        // write emits `objectWillChange` whether or not the value moved — three per
        // tick, every tick. Guarding them means a steady working state does nothing at
        // all between the ~64 phase steps of an interval.
        if presence != newPresence { presence = newPresence }
        if phase != newPhase { phase = newPhase }
        if mood != newMood { mood = newMood }

        let desiredInterval = newPresence == .absent ? absentTickInterval : activeTickInterval
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
        case .working:
            // Read the engine rather than the phase's `progress`: that payload is
            // quantized before publishing (see `progressSteps`), which is right for a
            // progress bar and far too coarse for a countdown. `accrued` is unrounded.
            //
            // Nothing left to accrue means the break is due but held back because the
            // last input is old enough that they may have stepped away. "in 0s" would
            // be a lie.
            let remaining = engine.schedule.workInterval - engine.accrued
            guard remaining > 0 else { return "Break ready when you are" }
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
