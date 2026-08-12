import Foundation

/// What happened when a break ended. Mirrors `BreakPhase.praise`/`.ignored`, but the
/// engine holds those phases for a few seconds of ticks — the app layer records exactly
/// one outcome per phase transition, not one per tick.
public enum BreakOutcome: String, Sendable, Equatable, Codable {
    /// They actually stayed off the input devices for the break.
    case taken
    /// They typed straight through it.
    case ignored
}

/// Local, on-device tally of break outcomes, keyed by calendar day.
///
/// This is the self-honesty signal: a taken/ignored count and a streak, kept entirely
/// on the machine. Deterministic on purpose — every entry point takes its `Date` and
/// `Calendar` as parameters rather than reading `Date()` or `Calendar.current`, so this
/// stays testable the same way `BreakEngine` is. The app layer supplies the real clock.
public struct BreakLedger: Sendable, Equatable, Codable {
    /// One calendar day's tally.
    private struct DayTally: Sendable, Equatable, Codable {
        var taken: Int = 0
        var ignored: Int = 0
    }

    /// Keyed by a zero-padded "YYYY-MM-DD" string rather than a raw `Date`, so:
    /// - it Codable-serializes as a plain JSON object (string keys), not an array of pairs
    /// - lexicographic string comparison matches chronological order, which `prune` relies on
    /// - it is immune to time-of-day/timezone drift the way a `Date` start-of-day could not be
    private var days: [String: DayTally] = [:]

    /// Entries older than this are dropped on every `record`, so the persisted ledger
    /// doesn't grow forever. Well past anything `counts`/`streak` need to look at.
    private static let maxAgeDays = 90

    public init() {}

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    public mutating func record(_ outcome: BreakOutcome, on date: Date, calendar: Calendar) {
        let key = Self.dayKey(for: date, calendar: calendar)
        var tally = days[key] ?? DayTally()
        switch outcome {
        case .taken: tally.taken += 1
        case .ignored: tally.ignored += 1
        }
        days[key] = tally
        prune(relativeTo: date, calendar: calendar)
    }

    /// Taken/ignored counts for the calendar day containing `date`.
    public func counts(on date: Date, calendar: Calendar) -> (taken: Int, ignored: Int) {
        let tally = days[Self.dayKey(for: date, calendar: calendar)] ?? DayTally()
        return (tally.taken, tally.ignored)
    }

    /// Consecutive calendar days ending on `date`, each with at least one taken break.
    /// A day with zero taken breaks (whether empty or all-ignored) breaks the streak.
    /// `date` itself only extends the streak if it already has a taken break — call
    /// with `endingOn: yesterday` to get the streak as of end-of-yesterday regardless
    /// of what today looks like so far.
    public func streak(endingOn date: Date, calendar: Calendar) -> Int {
        var count = 0
        var cursor = date
        while true {
            let key = Self.dayKey(for: cursor, calendar: calendar)
            guard let tally = days[key], tally.taken > 0 else { break }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private mutating func prune(relativeTo date: Date, calendar: Calendar) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.maxAgeDays, to: date) else { return }
        let cutoffKey = Self.dayKey(for: cutoff, calendar: calendar)
        days = days.filter { $0.key >= cutoffKey }
    }
}
