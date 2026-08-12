import EyePetCore
import Foundation

/// Typed `UserDefaults.standard` wrapper for the handful of settings that survive a
/// relaunch. No settings UI yet — the menu bar is still the only way to change any of
/// this — so this just remembers whatever it last set.
struct Preferences {
    private enum Key {
        static let scheduleName = "schedule.name"
        static let scheduleWorkInterval = "schedule.workInterval"
        static let scheduleBreakDuration = "schedule.breakDuration"
        static let scheduleWarningLead = "schedule.warningLead"
        static let alwaysShowPet = "alwaysShowPet"
        static let isPaused = "isPaused"
        static let statsLedger = "stats.ledger"
        static let petSpecies = "pet.species"
        static let soundEnabled = "sound.enabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Display name of the last-picked preset, for menu highlighting. Not used to
    /// reconstruct the schedule itself — `schedule` below does that from the numeric
    /// fields directly, so restoration keeps working even if the preset list changes.
    var scheduleName: String? {
        get { defaults.string(forKey: Key.scheduleName) }
        set { defaults.set(newValue, forKey: Key.scheduleName) }
    }

    var schedule: BreakSchedule? {
        get {
            guard
                let workInterval = defaults.object(forKey: Key.scheduleWorkInterval) as? Double,
                let breakDuration = defaults.object(forKey: Key.scheduleBreakDuration) as? Double,
                let warningLead = defaults.object(forKey: Key.scheduleWarningLead) as? Double
            else { return nil }
            return BreakSchedule(workInterval: workInterval, breakDuration: breakDuration, warningLead: warningLead)
        }
        set {
            defaults.set(newValue?.workInterval, forKey: Key.scheduleWorkInterval)
            defaults.set(newValue?.breakDuration, forKey: Key.scheduleBreakDuration)
            defaults.set(newValue?.warningLead, forKey: Key.scheduleWarningLead)
        }
    }

    /// Defaults to `true` to match `NotchController.alwaysShowPet`'s built-in default
    /// when nothing has been saved yet.
    var alwaysShowPet: Bool {
        get { defaults.object(forKey: Key.alwaysShowPet) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.alwaysShowPet) }
    }

    var isPaused: Bool {
        get { defaults.bool(forKey: Key.isPaused) }
        set { defaults.set(newValue, forKey: Key.isPaused) }
    }

    /// `nil` when nothing has been saved yet, so callers can fall back to `.dot`
    /// without this type needing to know that default itself.
    var species: PetSpecies? {
        get {
            defaults.string(forKey: Key.petSpecies).flatMap(PetSpecies.init(rawValue:))
        }
        set { defaults.set(newValue?.rawValue, forKey: Key.petSpecies) }
    }

    /// Soft sound cue when a break starts. Defaults to `false` — a break sound is
    /// exactly the kind of nag that risks the app getting disabled (see CLAUDE.md's
    /// retention thesis), so it stays opt-in rather than on by default.
    var soundEnabled: Bool {
        get { defaults.bool(forKey: Key.soundEnabled) }
        set { defaults.set(newValue, forKey: Key.soundEnabled) }
    }

    /// Break taken/ignored history, JSON-encoded. Local only — never leaves the device.
    var ledger: BreakLedger? {
        get {
            guard let data = defaults.data(forKey: Key.statsLedger) else { return nil }
            return try? JSONDecoder().decode(BreakLedger.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: Key.statsLedger)
                return
            }
            defaults.set(data, forKey: Key.statsLedger)
        }
    }
}
