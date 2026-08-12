import EyePetCore
import SwiftUI

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
        .offset(y: offsetY)
        .task(id: faceKey) { await runAnimation() }
        .task(id: faceKey) { await scheduleBlink() }
        .task(id: faceKey) { await applyMotion() }
        .task(id: faceKey) { await runQuirk() }
        .accessibilityLabel("Pet is \(mood.rawValue)")
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
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                offsetY = -1.5
            }
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

            Spacer(minLength: 0)

            if case let .resting(remaining) = model.phase {
                CountdownRing(
                    progress: 1 - (remaining / max(model.engine.schedule.breakDuration, 1))
                )
                .frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 380)
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
            ""
        }
    }
}

struct CountdownRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(.white.opacity(0.85), style: .init(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: progress)
        }
    }
}
