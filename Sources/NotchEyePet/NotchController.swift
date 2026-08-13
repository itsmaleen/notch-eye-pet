import AppKit
import Combine
import DynamicNotchKit
import EyePetCore
import SwiftUI

/// Drives the notch presentation from the model's phase.
///
/// DynamicNotchKit (MIT) rather than boring.notch (GPL-3): the licence is the deciding
/// factor, and it also gives a floating-pill fallback on Macs with no notch for free,
/// which matters because plenty of use is on an external display.
@MainActor
final class NotchController {
    /// Keep a compact pet visible while working. The whole retention thesis is that a
    /// resident creature beats an overlay that only appears to interrupt you.
    /// Persisted so a future settings toggle (Phase 2) sticks across launches; there is
    /// no UI to flip it yet.
    var alwaysShowPet: Bool {
        didSet { preferences.alwaysShowPet = alwaysShowPet }
    }

    /// Opens the settings window from the break panel's gear.
    ///
    /// A closure rather than a `SettingsWindowController` reference because that type
    /// already takes a `NotchController` (it owns the always-show-pet toggle), and
    /// holding each other directly would be a construction cycle. Assign before `start()`.
    var onOpenSettings: (() -> Void)?

    private let model: AppModel
    private var preferences: Preferences
    private var notch: DynamicNotch<BreakPanelView, CompactPetView, CompactStatusView>?
    private var cancellable: AnyCancellable?
    private var presented: Presentation = .hidden

    private enum Presentation { case hidden, compact, expanded }

    init(model: AppModel, preferences: Preferences = Preferences()) {
        self.model = model
        self.preferences = preferences
        alwaysShowPet = preferences.alwaysShowPet
    }

    func start() {
        let model = self.model
        notch = DynamicNotch(
            hoverBehavior: .all,
            style: .auto,
            // The closure body runs once, so the gear's action indirects through
            // `self.onOpenSettings` at tap time rather than capturing its value here.
            expanded: { [weak self] in
                BreakPanelView(model: model, onOpenSettings: { self?.onOpenSettings?() })
            },
            compactLeading: { [weak self] in
                CompactPetView(model: model, onOpenSettings: { self?.onOpenSettings?() })
            },
            compactTrailing: { CompactStatusView(model: model) }
        )

        cancellable = model.$phase
            .removeDuplicates()
            .sink { [weak self] phase in
                Task { @MainActor in self?.apply(phase) }
            }

        apply(model.phase)
    }

    func stop() {
        cancellable = nil
        let notch = self.notch
        self.notch = nil
        Task { @MainActor in await notch?.hide() }
    }

    /// Re-runs the presentation logic against the current phase without waiting for a
    /// phase change. `apply(_:)` is normally driven by the `$phase` subscription below,
    /// which only fires on transitions — so anything that flips `alwaysShowPet` from
    /// outside that pipeline (the settings window's toggle) needs this to take effect
    /// immediately instead of on the next break-phase change.
    func refreshPresentation() {
        apply(model.phase)
    }

    private func apply(_ phase: BreakPhase) {
        let target: Presentation = if phase.isBreakVisible {
            .expanded
        } else if alwaysShowPet, phase != .paused {
            .compact
        } else {
            .hidden
        }

        guard target != presented else { return }
        presented = target

        Task { @MainActor [weak self] in
            guard let notch = self?.notch else { return }
            switch target {
            case .hidden: await notch.hide()
            case .compact: await notch.compact()
            case .expanded: await notch.expand()
            }
        }
    }
}

/// The leading half of the compact pill. DynamicNotchKit evaluates its content closures
/// once, so a bare `PetView(mood:)` there would freeze on whatever mood existed at
/// setup — the face only follows the engine if something observes the model.
struct CompactPetView: View {
    @ObservedObject var model: AppModel
    /// Set by `NotchController`. Optional so previews can build the pet standalone.
    var onOpenSettings: (() -> Void)?

    var body: some View {
        // A `Button` rather than `.onTapGesture`: the gesture recogniser never fires
        // inside the compact notch (verified), while the break panel's gear button
        // works, so the button's own hit testing is what the notch window honours.
        //
        // This matters because the pet is the most reliable way in. The menu bar item
        // vanishes with the menu bar in a fullscreen app, and gets hidden behind the
        // notch entirely once enough apps compete for menu bar space, while the break
        // panel's gear only exists during a break.
        Button(action: { onOpenSettings?() }) {
            PetView(mood: model.mood, species: model.species)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Notch Eye Pet settings")
        .accessibilityLabel("Open Notch Eye Pet settings")
    }
}

/// The trailing half of the compact pill: a thin progress hint, no numbers.
///
/// Deliberately not a countdown. A visible timer invites clock-watching, which is the
/// opposite of the ambient-companion posture the product is betting on.
struct CompactStatusView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.18))
            .frame(width: 26, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(tint)
                    .frame(width: 26 * progress, height: 4)
                    .animation(.linear(duration: 0.9), value: progress)
            }
    }

    private var progress: CGFloat {
        if case let .working(value) = model.phase { return CGFloat(value) }
        return 1
    }

    private var tint: Color {
        switch model.presence {
        case .active: .teal
        case .passive: .blue
        case .absent: .gray
        }
    }
}
