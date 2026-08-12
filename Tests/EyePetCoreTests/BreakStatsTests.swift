import XCTest
@testable import EyePetCore

/// The ledger is pure, so day boundaries are driven by injected dates rather than
/// waiting on the wall clock.
final class BreakStatsTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Recording

    func testRecordIncrementsTheRightDay() {
        var ledger = BreakLedger()
        ledger.record(.taken, on: day(2026, 8, 12), calendar: calendar)
        ledger.record(.taken, on: day(2026, 8, 12), calendar: calendar)
        ledger.record(.ignored, on: day(2026, 8, 12), calendar: calendar)

        let counts = ledger.counts(on: day(2026, 8, 12), calendar: calendar)
        XCTAssertEqual(counts.taken, 2)
        XCTAssertEqual(counts.ignored, 1)
    }

    func testCountsIsolatePerDay() {
        var ledger = BreakLedger()
        ledger.record(.taken, on: day(2026, 8, 11), calendar: calendar)
        ledger.record(.ignored, on: day(2026, 8, 12), calendar: calendar)

        let day11 = ledger.counts(on: day(2026, 8, 11), calendar: calendar)
        let day12 = ledger.counts(on: day(2026, 8, 12), calendar: calendar)
        XCTAssertEqual(day11.taken, 1)
        XCTAssertEqual(day11.ignored, 0)
        XCTAssertEqual(day12.taken, 0)
        XCTAssertEqual(day12.ignored, 1)
    }

    func testCountsOnUntouchedDayIsZero() {
        let ledger = BreakLedger()
        let counts = ledger.counts(on: day(2026, 8, 12), calendar: calendar)
        XCTAssertEqual(counts.taken, 0)
        XCTAssertEqual(counts.ignored, 0)
    }

    // MARK: - Streaks

    func testStreakCountsConsecutiveTakenDays() {
        var ledger = BreakLedger()
        ledger.record(.taken, on: day(2026, 8, 10), calendar: calendar)
        ledger.record(.taken, on: day(2026, 8, 11), calendar: calendar)
        ledger.record(.taken, on: day(2026, 8, 12), calendar: calendar)

        XCTAssertEqual(ledger.streak(endingOn: day(2026, 8, 12), calendar: calendar), 3)
    }

    func testGapDayResetsStreak() {
        var ledger = BreakLedger()
        ledger.record(.taken, on: day(2026, 8, 9), calendar: calendar)
        // 8/10 has nothing recorded at all — a gap.
        ledger.record(.taken, on: day(2026, 8, 11), calendar: calendar)
        ledger.record(.taken, on: day(2026, 8, 12), calendar: calendar)

        XCTAssertEqual(ledger.streak(endingOn: day(2026, 8, 12), calendar: calendar), 2)
    }

    /// An all-ignored day is not a taken day, so it breaks the streak the same as an
    /// empty day.
    func testAllIgnoredDayBreaksStreak() {
        var ledger = BreakLedger()
        ledger.record(.taken, on: day(2026, 8, 10), calendar: calendar)
        ledger.record(.ignored, on: day(2026, 8, 11), calendar: calendar)
        ledger.record(.taken, on: day(2026, 8, 12), calendar: calendar)

        XCTAssertEqual(ledger.streak(endingOn: day(2026, 8, 12), calendar: calendar), 1)
    }

    /// Today without a taken break yet must not extend the streak, but the streak as
    /// of end-of-yesterday should still be reported correctly.
    func testTodayWithoutTakenBreakDoesNotExtendStreakButYesterdayStillCounts() {
        var ledger = BreakLedger()
        ledger.record(.taken, on: day(2026, 8, 11), calendar: calendar)
        ledger.record(.taken, on: day(2026, 8, 12), calendar: calendar)
        // 8/13 ("today") has only an ignored break so far.
        ledger.record(.ignored, on: day(2026, 8, 13), calendar: calendar)

        XCTAssertEqual(ledger.streak(endingOn: day(2026, 8, 13), calendar: calendar), 0)
        XCTAssertEqual(ledger.streak(endingOn: day(2026, 8, 12), calendar: calendar), 2)
    }

    func testStreakOnCompletelyEmptyLedgerIsZero() {
        let ledger = BreakLedger()
        XCTAssertEqual(ledger.streak(endingOn: day(2026, 8, 12), calendar: calendar), 0)
    }

    // MARK: - Pruning

    func testPruningDropsEntriesOlderThanNinetyDays() {
        var ledger = BreakLedger()
        let old = day(2026, 1, 1)
        let recent = day(2026, 8, 12)
        ledger.record(.taken, on: old, calendar: calendar)

        // The gap between 1/1 and 8/12 2026 is well past 90 days, so recording on the
        // later date should prune the old entry away.
        ledger.record(.taken, on: recent, calendar: calendar)

        XCTAssertEqual(ledger.counts(on: old, calendar: calendar).taken, 0)
        XCTAssertEqual(ledger.counts(on: recent, calendar: calendar).taken, 1)
    }

    func testPruningKeepsEntriesWithinNinetyDays() {
        var ledger = BreakLedger()
        let within = day(2026, 6, 1)
        let recent = day(2026, 8, 12)
        ledger.record(.taken, on: within, calendar: calendar)
        ledger.record(.taken, on: recent, calendar: calendar)

        XCTAssertEqual(ledger.counts(on: within, calendar: calendar).taken, 1)
    }

    // MARK: - Codable

    func testRoundTripsThroughJSONEncoderDecoder() throws {
        var ledger = BreakLedger()
        ledger.record(.taken, on: day(2026, 8, 11), calendar: calendar)
        ledger.record(.taken, on: day(2026, 8, 12), calendar: calendar)
        ledger.record(.ignored, on: day(2026, 8, 12), calendar: calendar)

        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(BreakLedger.self, from: data)

        XCTAssertEqual(decoded, ledger)
        XCTAssertEqual(decoded.counts(on: day(2026, 8, 12), calendar: calendar).taken, 1)
        XCTAssertEqual(decoded.counts(on: day(2026, 8, 12), calendar: calendar).ignored, 1)
        XCTAssertEqual(decoded.streak(endingOn: day(2026, 8, 12), calendar: calendar), 2)
    }
}
