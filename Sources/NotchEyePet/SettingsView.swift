import EyePetCore
import SwiftUI

/// Contents of the settings window.
///
/// Uses `Form` with `.formStyle(.grouped)`, which is what System Settings itself renders
/// as on macOS 13+: inset rounded sections with trailing controls. The previous stack of
/// `GroupBox`es was legible but read as a debug panel, and this is the surface someone
/// lands on right after being interrupted, so it is worth looking settled rather than
/// improvised (see the retention argument in `CLAUDE.md`).
struct SettingsView: View {
    @ObservedObject var model: AppModel
    let notchController: NotchController

    private static let customName = "Custom"

    @State private var selectedPresetName: String
    @State private var customWorkMinutes: Double
    @State private var customBreakSeconds: Double
    @State private var customWarningLeadSeconds: Double
    @State private var alwaysShowPet: Bool
    @State private var launchAtLoginEnabled: Bool
    @State private var selectedSpecies: PetSpecies
    @State private var soundEnabled: Bool

    init(model: AppModel, notchController: NotchController) {
        self.model = model
        self.notchController = notchController

        let isKnownPreset = MenuBarController.presets.contains { $0.name == model.scheduleName }
        _selectedPresetName = State(initialValue: isKnownPreset ? model.scheduleName : Self.customName)

        let schedule = model.engine.schedule
        _customWorkMinutes = State(initialValue: (schedule.workInterval / 60).rounded())
        _customBreakSeconds = State(initialValue: schedule.breakDuration.rounded())
        _customWarningLeadSeconds = State(initialValue: schedule.warningLead.rounded())

        _alwaysShowPet = State(initialValue: notchController.alwaysShowPet)
        _launchAtLoginEnabled = State(initialValue: LaunchAtLogin.isEnabled)
        _selectedSpecies = State(initialValue: model.species)
        // No stored Preferences access from this view yet; construct one the same way
        // AppModel and NotchController default their own — it is a thin, cheap wrapper
        // over UserDefaults.standard, so a fresh instance per read/write is fine.
        _soundEnabled = State(initialValue: Preferences().soundEnabled)
    }

    var body: some View {
        Form {
            todaySection
            petSection
            scheduleSection
            generalSection
            aboutSection
        }
        .formStyle(.grouped)
        // Tall enough that the closing note about permissions sits above the fold. The
        // schedule section grows when "Custom" is picked, so the form still scrolls
        // rather than being pinned to its content height.
        .frame(width: 440, height: 660)
    }

    // MARK: - Sections

    /// The ledger is the one thing here that is about the user rather than the app, so
    /// it leads. It is also the honest framing of the product: a habit you are keeping,
    /// not a feature you configured once.
    private var todaySection: some View {
        Section {
            LabeledContent("Today") {
                let counts = model.todayBreakCounts
                Text("\(counts.taken) taken · \(counts.ignored) missed")
                    .foregroundStyle(.secondary)
            }
            if model.breakStreak >= 2 {
                LabeledContent("Streak") {
                    Text("\(model.breakStreak) days")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var petSection: some View {
        Section("Pet") {
            Picker("Species", selection: $selectedSpecies) {
                ForEach(PetSpecies.allCases, id: \.self) { species in
                    // The glyph beside the name so the choice is visible before making
                    // it; "Owl" versus "Cat" means nothing without seeing the face.
                    Text("\(PetGlyphs.previewFrame(for: species))   \(species.displayName)")
                        .tag(species)
                }
            }
            .onChange(of: selectedSpecies) { newValue in
                model.apply(species: newValue)
            }

            Toggle("Show pet while working", isOn: $alwaysShowPet)
                .onChange(of: alwaysShowPet) { newValue in
                    notchController.alwaysShowPet = newValue
                    // Presentation only re-evaluates automatically on a break-phase
                    // change; force it now so the toggle takes effect immediately.
                    notchController.refreshPresentation()
                }
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Preset", selection: $selectedPresetName) {
                ForEach(MenuBarController.presets, id: \.name) { preset in
                    Text(preset.name).tag(preset.name)
                }
                Text(Self.customName).tag(Self.customName)
            }
            .onChange(of: selectedPresetName, perform: applyPreset)

            if selectedPresetName == Self.customName {
                Stepper(value: $customWorkMinutes, in: 1...120, step: 1) {
                    LabeledContent("Work interval") {
                        Text("\(Int(customWorkMinutes)) min").foregroundStyle(.secondary)
                    }
                }
                .onChange(of: customWorkMinutes) { _ in applyCustomSchedule() }

                Stepper(value: $customBreakSeconds, in: 5...120, step: 5) {
                    LabeledContent("Break duration") {
                        Text("\(Int(customBreakSeconds)) s").foregroundStyle(.secondary)
                    }
                }
                .onChange(of: customBreakSeconds) { _ in applyCustomSchedule() }

                Stepper(value: $customWarningLeadSeconds, in: 3...30, step: 1) {
                    LabeledContent("Warning lead") {
                        Text("\(Int(customWarningLeadSeconds)) s").foregroundStyle(.secondary)
                    }
                }
                .onChange(of: customWarningLeadSeconds) { _ in applyCustomSchedule() }
            }
        } header: {
            Text("Break schedule")
        } footer: {
            // Stated in the UI, not just the README. The trials do not support any
            // particular interval, and implying otherwise would be a medical claim the
            // evidence cannot carry. See CLAUDE.md.
            Text("Intervals are a preference, not a prescription. Trials have not shown one schedule to beat another; what helped was being reminded at all, and the benefit faded once reminders stopped.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at login", isOn: $launchAtLoginEnabled)
                .onChange(of: launchAtLoginEnabled) { newValue in
                    // Registration can fail quietly (ad-hoc signing, running outside
                    // the .app bundle); read the real status back so the checkbox
                    // never claims a state that isn't true.
                    launchAtLoginEnabled = LaunchAtLogin.setEnabled(newValue)
                }

            Toggle("Soft sound when a break starts", isOn: $soundEnabled)
                .onChange(of: soundEnabled) { newValue in
                    var preferences = Preferences()
                    preferences.soundEnabled = newValue
                }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Permissions") {
                Text("None required")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Version") {
                Text(Self.versionString)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Presence is inferred from input timing and power assertions. No camera, no accessibility access, and nothing leaves this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        return short
    }

    // MARK: - Actions

    private func applyPreset(named name: String) {
        guard name != Self.customName else {
            applyCustomSchedule()
            return
        }
        guard let preset = MenuBarController.presets.first(where: { $0.name == name }) else { return }
        model.apply(schedule: preset.schedule, named: preset.name)
    }

    private func applyCustomSchedule() {
        let schedule = BreakSchedule(
            workInterval: customWorkMinutes * 60,
            breakDuration: customBreakSeconds,
            warningLead: customWarningLeadSeconds
        )
        model.apply(schedule: schedule, named: Self.customName)
    }
}
