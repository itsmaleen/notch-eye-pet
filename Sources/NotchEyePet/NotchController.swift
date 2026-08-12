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
            expanded: { BreakPanelView(model: model) },
            compactLeading: { CompactPetView(model: model) },
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

    var body: some View {
        PetView(mood: model.mood, species: model.species)
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
