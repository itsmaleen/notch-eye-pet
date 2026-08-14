import AppKit
import EyePetCore
import SwiftUI

/// Hosts `content` in its own layer so an endless motion can be handed to Core Animation
/// rather than run by SwiftUI.
///
/// SwiftUI evaluates its animations on the main thread once per displayed frame, and a
/// `repeatForever` never settles — so `withAnimation(...repeatForever) { offsetY = -1.5 }`
/// kept the notch running a full `NSHostingView` layout pass at the display's refresh
/// rate for the entire life of the app. Measured 2026-08-13 on a 120Hz panel: 7.9% CPU
/// with the bob versus 0.6% without, for a pet drifting a pt and a half. A
/// `CABasicAnimation` is handed to the render server once and then costs the app nothing
/// per frame, which is the only acceptable shape for a motion that never stops in a
/// process that never quits.
private struct PerpetualBob<Content: View>: NSViewRepresentable {
    let isActive: Bool
    let amplitude: CGFloat
    let duration: CFTimeInterval
    let content: Content

    private static var key: String { "pet.bob" }

    final class Coordinator {
        var controller: NSHostingController<Content>?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let controller = NSHostingController(rootView: content)
        // Keep AppKit from consulting `intrinsicContentSize`. On a hosting view that is
        // not in a window yet, that getter converts through the backing store, the
        // transform is singular, and AppKit aborts on an assertion. Sizing is answered
        // by `sizeThatFits` below instead.
        controller.sizingOptions = []
        context.coordinator.controller = controller
        controller.view.wantsLayer = true
        return controller.view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.controller?.rootView = content
        guard let layer = view.layer else { return }

        guard isActive else {
            layer.removeAnimation(forKey: Self.key)
            return
        }
        // The glyph is swapped on every blink and frame step, so this runs constantly.
        // Re-adding the animation each time would restart the bob mid-arc and make the
        // pet twitch, so a running one is left alone.
        guard layer.animation(forKey: Self.key) == nil else { return }

        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        // Negative is up: `NSHostingView` is flipped, so its layer geometry is too.
        // Matches the sign the SwiftUI version used on `offsetY`.
        bob.fromValue = 0
        bob.toValue = -amplitude
        bob.duration = duration
        bob.autoreverses = true
        bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(bob, forKey: Self.key)
    }

    /// Without this the representable claims the whole proposal and the compact pill
    /// stretches; the hosted SwiftUI content already knows its own ideal size.
    ///
    /// Measured through the hosting *controller*, which asks SwiftUI directly. Going via
    /// the view's `fittingSize`/`intrinsicContentSize` instead routes through Auto Layout
    /// and a backing-store conversion that is singular before the view has a window, and
    /// AppKit aborts on an assertion there.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSView,
        context: Context
    ) -> CGSize? {
        context.coordinator.controller?.sizeThatFits(
            in: proposal.replacingUnspecifiedDimensions(
                by: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            )
        )
    }
}

/// The pet: a kaomoji-style text glyph, stepped through its mood's frame table.
///
/// Text glyphs, not a sprite sheet — no asset pack surveyed (2026-08-12) was both
/// complete and permissively licensed, and a monospaced glyph animates for free off
/// the system font. All the personality lives in `PetGlyphs`; this view just steps
/// the frame index, runs the blink scheduler, and applies the per-mood motion.
struct PetView: View {
    let mood: PetMood
    var species: PetSpecies = .dot
    var size: CGFloat = 22

    @State private var frameIndex = 0
    @State private var blinking = false
    @State private var offsetY: CGFloat = 0
    @State private var quirkFrame: String?

    private var animation: MoodAnimation { PetGlyphs.animation(for: mood, species: species) }

    /// Identifies a face configuration: mood plus species, since either can change
    /// which glyphs, timing, or motion apply. Every animation loop below keys its
    /// `.task` on this instead of on `mood` alone, so switching species from Settings
    /// restarts them cleanly instead of running with a stale species (e.g. robo still
    /// blinking, or owl still bobbing) captured from before the switch.
    private struct FaceKey: Equatable {
        let mood: PetMood
        let species: PetSpecies
    }

    private var faceKey: FaceKey { FaceKey(mood: mood, species: species) }

    var body: some View {
        // The bob is the one perpetual motion the pet has, so it is the one handed to
        // Core Animation; `.bounce` and `.droop` are finite and settle, so they stay on
        // SwiftUI's `offsetY` below.
        PerpetualBob(
            isActive: animation.motion == .bob,
            amplitude: 1.5,
            duration: 1.2,
            content: face
        )
        .offset(y: offsetY)
        .task(id: faceKey) { await runAnimation() }
        .task(id: faceKey) { await scheduleBlink() }
        .task(id: faceKey) { await applyMotion() }
        .task(id: faceKey) { await runQuirk() }
        .accessibilityLabel("Pet is \(mood.rawValue)")
    }

    /// Everything that actually draws. Still plain SwiftUI: only the transform moved to
    /// Core Animation, so the glyph renders exactly as it did before.
    private var face: some View {
        ZStack {
            Text(currentFrame)
                .font(.system(size: size * 0.62, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(tint)

            if mood == .asleep {
                // Rides the same frame index as the face, so the z rises in step with
                // the (otherwise static) closed-eye face rather than on its own clock.
                Text("ᶻ")
                    .font(.system(size: size * 0.3, weight: .semibold, design: .monospaced))
                    .fixedSize()
                    .foregroundStyle(tint)
                    .offset(x: size * 0.11 * CGFloat(frameWidth), y: zOffset)
            }
        }
        .frame(height: size)
        .opacity(animation.dimmed ? 0.6 : 1)
    }

    // MARK: - Frame

    private var currentFrame: String {
        if let quirkFrame { return quirkFrame }
        let frames = animation.frames
        let index = frames.indices.contains(frameIndex) ? frameIndex : 0
        let base = frames[index]
        guard blinking, animation.blinks else { return base }
        return closedEyes(of: base)
    }

    /// Character count of this species' frames (all frames of a species share one
    /// width by construction — see `PetGlyphsTests`), used to scale the sleeping "z"
    /// overlay's x-offset so it still lands past the frame regardless of species width.
    private var frameWidth: Int {
        animation.frames.first?.count ?? 5
    }

    /// Swaps whatever sits in the species' eye slots for the closed-eye en dash.
    /// Position-based rather than a literal glyph match, so the blink still reads on
    /// moods whose open-eye glyph differs (watching, peeking) rather than silently
    /// doing nothing on those frames.
    private func closedEyes(of frame: String) -> String {
        var characters = Array(frame)
        for slot in PetGlyphs.eyeSlots(for: species) where characters.indices.contains(slot) {
            characters[slot] = "–"
        }
        return String(characters)
    }

    private var zOffset: CGFloat {
        -CGFloat(frameIndex % 3) * size * 0.12
    }

    private var tint: Color {
        switch mood {
        case .idle: .teal
        case .busy: .orange
        case .grazing: .purple
        case .watching: .blue
        case .peeking: .yellow
        case .coaxing: .green
        case .delighted: .mint
        case .sulking: .red
        case .asleep, .paused: .gray
        }
    }

    // MARK: - Animation loops
    //
    // Each runs as a separate `.task(id: faceKey)`, so a mood or species change cancels
    // and restarts all four cleanly instead of needing a manual reset path.

    private func runAnimation() async {
        frameIndex = 0
        let frames = animation.frames
        guard frames.count > 1 else { return }
        while !Task.isCancelled {
            let duration = animation.duration(forFrame: frameIndex)
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            frameIndex = (frameIndex + 1) % frames.count
        }
    }

    private func scheduleBlink() async {
        blinking = false
        guard animation.blinks else { return }
        // Irregular blinking reads as alive; a fixed interval reads as a loading spinner.
        while !Task.isCancelled {
            let delay = Double.random(in: 2.5...6.0)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            blinking = true
            try? await Task.sleep(for: .seconds(0.12))
            guard !Task.isCancelled else { return }
            blinking = false
        }
    }

    private func applyMotion() async {
        // Assigning without `withAnimation` interrupts any repeating animation left
        // over from the previous mood before starting the new one.
        offsetY = 0
        switch animation.motion {
        case .still:
            break
        case .bob:
            // Driven by `PerpetualBob` in Core Animation, not from here. Resetting
            // `offsetY` to 0 above is all this case needs to do.
            break
        case .bounce:
            for _ in 0..<3 {
                guard !Task.isCancelled else { return }
                withAnimation(.interpolatingSpring(stiffness: 260, damping: 14)) { offsetY = -3 }
                try? await Task.sleep(for: .seconds(0.18))
                guard !Task.isCancelled else { return }
                withAnimation(.interpolatingSpring(stiffness: 260, damping: 14)) { offsetY = 0 }
                try? await Task.sleep(for: .seconds(0.18))
            }
        case .droop:
            withAnimation(.easeInOut(duration: 1.5)) {
                offsetY = 2
            }
        }
    }

    /// Rare idle-only personality beat. Rate-limited by construction, not by a
    /// cooldown flag: the wait is re-rolled every loop iteration, the loop only starts
    /// while `mood == .idle`, and a `.task(id: faceKey)` change (any mood or species
    /// switch) cancels it outright — so it can only ever fire during idle, at most
    /// once per 180...360s of continuous idle.
    private func runQuirk() async {
        quirkFrame = nil
        guard mood == .idle else { return }
        while !Task.isCancelled {
            let delay = Double.random(in: 180...360)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await playQuirkOnce()
        }
    }

    private func playQuirkOnce() async {
        let quirk = PetGlyphs.quirk(for: species)
        for (index, frame) in quirk.frames.enumerated() {
            guard !Task.isCancelled else { break }
            quirkFrame = frame
            try? await Task.sleep(for: .seconds(quirk.duration(forFrame: index)))
        }
        guard !Task.isCancelled else { return }
        quirkFrame = nil
    }
}

/// The expanded break UI shown inside the notch.
struct BreakPanelView: View {
    @ObservedObject var model: AppModel
    /// All set by `NotchController`. Optional so previews can build the panel standalone.
    var onOpenSettings: (() -> Void)?
    var onCollapse: (() -> Void)?
    /// Called on hover so a panel the user is reading does not auto-collapse under them.
    var onInteraction: (() -> Void)?

    /// True during an actual break. The panel is doing two jobs — the break itself, and
    /// the hand-opened status/controls view — and they want different chrome: a break
    /// must not offer "take a break now", and controls must not compete with "look away".
    private var isBreak: Bool { model.phase.isBreakVisible }

    var body: some View {
        HStack(spacing: 16) {
            PetView(mood: model.mood, species: model.species, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subhead)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
            // One line each. The control cluster competes for the same row, and a
            // headline that wraps to "Next break / in 19m 55s" reads as broken layout.
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            if case let .resting(remaining) = model.phase {
                CountdownRing(
                    progress: 1 - (remaining / max(model.engine.schedule.breakDuration, 1)),
                    remaining: remaining
                )
                .frame(width: 34, height: 34)
            }

            controls
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        // Wider than the original 380: the hand-opened panel carries four controls
        // alongside the status text, which the narrower box could not fit on one line.
        .frame(width: 470)
        .onHover { if $0 { onInteraction?() } }
    }

    /// During a break this is the gear alone, deliberately quiet: the instruction is to
    /// look away from the screen, so controls must not invite looking back at it.
    /// Otherwise it is the full set, since the panel was opened on purpose.
    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 6) {
            if !isBreak {
                iconButton("cup.and.saucer.fill", help: "Take a break now") {
                    model.engine.breakNow()
                }
                iconButton(
                    isPaused ? "play.fill" : "pause.fill",
                    help: isPaused ? "Resume" : "Pause"
                ) {
                    if isPaused { model.resume() } else { model.pause() }
                }
            }

            iconButton("gearshape.fill", help: "Settings", dimmed: isBreak) {
                onOpenSettings?()
            }

            if !isBreak {
                iconButton("xmark", help: "Close") { onCollapse?() }
            }
        }
    }

    private var isPaused: Bool { model.phase == .paused }

    private func iconButton(
        _ symbol: String,
        help: String,
        dimmed: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(dimmed ? 0.45 : 0.8))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(dimmed ? 0.06 : 0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var headline: String {
        switch model.phase {
        case .warning: "Eyes up soon"
        case .resting: "Look far away"
        case .praise: "Nice one"
        case .ignored: "You worked through it"
        default: model.statusLine
        }
    }

    private var subhead: String {
        switch model.phase {
        case let .warning(remaining):
            "Starting in \(Int(remaining.rounded()))s"
        case let .resting(remaining):
            // "and blink" is deliberate: dry eye was the measurable win in the
            // Talens-Estarelles trial, and blinking is what moves it.
            "Something across the room, and blink. \(Int(remaining.rounded()))s left"
        case .praise:
            "That is the habit. See you in \(AppModel.format(model.engine.schedule.workInterval))."
        case .ignored:
            "No judgement. Next one in \(AppModel.format(model.engine.schedule.workInterval))."
        default:
            // The hand-opened panel: show what the menu bar would, so opening it is
            // worth the click rather than just a route to the gear.
            todayLine
        }
    }

    private var todayLine: String {
        let counts = model.todayBreakCounts
        let streak = model.breakStreak
        let base = "Today: \(counts.taken) taken · \(counts.ignored) missed"
        return streak >= 2 ? base + " · \(streak) day streak" : base
    }
}

/// The break countdown, a ring that fills clockwise from twelve o'clock.
///
/// Drawn by Core Animation rather than an animated SwiftUI `.trim`, for the same reason
/// the pet bobs in Core Animation. `remaining` ticks once a second, so a 0.9s SwiftUI
/// animation keyed on it never settles, and `.trim` rebuilds the path on every displayed
/// frame: the whole panel re-rendered at the display's refresh rate for the length of the
/// break. Measured 2026-08-14 on a 120Hz panel, 12.2% CPU versus 1.0% for this version.
///
/// It also looks better. The sweep is handed over once and runs continuously, instead of
/// being re-tweened toward a new target every second.
struct CountdownRing: NSViewRepresentable {
    /// How much of the break has already elapsed, 0...1.
    let progress: Double
    /// Seconds left, which is how long the rest of the sweep should take.
    let remaining: TimeInterval
    var lineWidth: CGFloat = 3

    func makeNSView(context: Context) -> RingView {
        RingView(lineWidth: lineWidth)
    }

    func updateNSView(_ view: RingView, context: Context) {
        view.sweep(from: progress, over: remaining)
    }

    final class RingView: NSView {
        private let track = CAShapeLayer()
        private let sweepLayer = CAShapeLayer()
        private let lineWidth: CGFloat

        init(lineWidth: CGFloat) {
            self.lineWidth = lineWidth
            super.init(frame: .zero)
            wantsLayer = true

            track.fillColor = .clear
            track.strokeColor = NSColor.white.withAlphaComponent(0.15).cgColor
            track.lineWidth = lineWidth

            sweepLayer.fillColor = .clear
            sweepLayer.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
            sweepLayer.lineWidth = lineWidth
            sweepLayer.lineCap = .round
            sweepLayer.strokeEnd = 0

            layer?.addSublayer(track)
            layer?.addSublayer(sweepLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let scale = window?.backingScaleFactor ?? 2
            track.contentsScale = scale
            sweepLayer.contentsScale = scale
        }

        override func layout() {
            super.layout()
            // The layers are positioned by hand, so the implicit animation AppKit would
            // otherwise attach to every frame/path change has to be suppressed.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let radius = (min(bounds.width, bounds.height) - lineWidth) / 2
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let path = CGMutablePath()
            // Unflipped view, so +y is up: start at the top and sweep clockwise, which is
            // what the SwiftUI version did with `.trim` plus a -90 degree rotation.
            path.addArc(
                center: center,
                radius: max(radius, 0),
                startAngle: .pi / 2,
                endAngle: .pi / 2 - 2 * .pi,
                clockwise: true
            )
            for sublayer in [track, sweepLayer] {
                sublayer.frame = bounds
                sublayer.path = path
            }
            CATransaction.commit()
        }

        /// Hands the rest of the sweep to the render server in one go.
        func sweep(from progress: Double, over remaining: TimeInterval) {
            // `updateNSView` runs every second as the countdown text changes. Re-adding
            // the animation there would restart the sweep each time and cost exactly what
            // this class exists to avoid, so a running one is left alone.
            guard sweepLayer.animation(forKey: "sweep") == nil else { return }

            let start = min(max(progress, 0), 1)
            guard remaining > 0 else {
                sweepLayer.strokeEnd = CGFloat(start)
                return
            }

            let fill = CABasicAnimation(keyPath: "strokeEnd")
            fill.fromValue = start
            fill.toValue = 1
            fill.duration = remaining
            fill.timingFunction = CAMediaTimingFunction(name: .linear)
            // Hold the filled ring rather than snapping back to `strokeEnd` at the end of
            // the break, which is still 0 on the model layer.
            fill.fillMode = .forwards
            fill.isRemovedOnCompletion = false
            sweepLayer.add(fill, forKey: "sweep")
        }
    }
}
