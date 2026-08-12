import EyePetCore
import SwiftUI

/// Contents of the settings window: schedule editor, the notch pet's visibility, and
/// launch-at-login. Kept to native `Form`/`GroupBox` — this is a utility window, not a
/// showpiece, and a plain settings sheet is one less thing that could feel like it is
/// trying too hard (see the retention argument in `CLAUDE.md`).
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
            GroupBox("Pet") {
                Picker("Species", selection: $selectedSpecies) {
                    ForEach(PetSpecies.allCases, id: \.self) { species in
                        Text(species.displayName).tag(species)
                    }
                }
                .onChange(of: selectedSpecies) { newValue in
                    model.apply(species: newValue)
                }
                .padding(.top, 4)
            }

            GroupBox("Break schedule") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Preset", selection: $selectedPresetName) {
                        ForEach(MenuBarController.presets, id: \.name) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                        Text(Self.customName).tag(Self.customName)
                    }
                    .onChange(of: selectedPresetName, perform: applyPreset)

                    if selectedPresetName == Self.customName {
                        Stepper(value: $customWorkMinutes, in: 1...120, step: 1) {
                            Text("Work interval: \(Int(customWorkMinutes)) min")
                        }
                        .onChange(of: customWorkMinutes) { _ in applyCustomSchedule() }

                        Stepper(value: $customBreakSeconds, in: 5...120, step: 5) {
                            Text("Break duration: \(Int(customBreakSeconds)) s")
                        }
                        .onChange(of: customBreakSeconds) { _ in applyCustomSchedule() }

                        Stepper(value: $customWarningLeadSeconds, in: 3...30, step: 1) {
                            Text("Warning lead: \(Int(customWarningLeadSeconds)) s")
                        }
                        .onChange(of: customWarningLeadSeconds) { _ in applyCustomSchedule() }
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Notch") {
                Toggle("Show pet while working", isOn: $alwaysShowPet)
                    .onChange(of: alwaysShowPet) { newValue in
                        notchController.alwaysShowPet = newValue
                        // Presentation only re-evaluates automatically on a break-phase
                        // change; force it now so the toggle takes effect immediately.
                        notchController.refreshPresentation()
                    }
                    .padding(.top, 4)
            }

            GroupBox("General") {
                VStack(alignment: .leading, spacing: 10) {
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
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

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
