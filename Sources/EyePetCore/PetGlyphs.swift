import Foundation

/// How a mood's frames move as a whole, layered on top of frame stepping.
///
/// The frame text carries the face; motion is a cheap offset animation the view
/// applies around it, picked to match the mood's energy.
public enum PetMotion: String, Sendable, Equatable {
    case bob
    case bounce
    case droop
    case still
}

/// One mood's full animation recipe: pure data, no rendering.
///
/// `frames` are all the same `count` of Characters by construction (see
/// `PetGlyphsTests`), so stepping between them never jitters the notch horizontally —
/// monospaced text only holds still if every frame is the same width. That invariant
/// holds per species: every mood's frames, plus the species' quirk, share one width.
public struct MoodAnimation: Sendable, Equatable {
    /// The cycle of glyph strings, shown in order and looped.
    public let frames: [String]
    /// Seconds each frame holds, used unless `frameDurations` overrides that frame.
    public let frameDuration: TimeInterval
    /// Per-frame override for asymmetric timing (coaxing: a long look-away, a quick
    /// check-back). When present, `frameDurations.count == frames.count`.
    public let frameDurations: [TimeInterval]?
    /// Whether the irregular blink scheduler may swap this mood's eyes shut.
    public let blinks: Bool
    /// The whole-glyph motion layered on top of frame stepping.
    public let motion: PetMotion
    /// Renders at reduced opacity. The low-energy moods only: asleep, paused.
    public let dimmed: Bool

    public init(
        frames: [String],
        frameDuration: TimeInterval,
        frameDurations: [TimeInterval]? = nil,
        blinks: Bool,
        motion: PetMotion,
        dimmed: Bool = false
    ) {
        self.frames = frames
        self.frameDuration = frameDuration
        self.frameDurations = frameDurations
        self.blinks = blinks
        self.motion = motion
        self.dimmed = dimmed
    }

    /// Seconds frame `index` should hold, honoring the asymmetric override when present.
    public func duration(forFrame index: Int) -> TimeInterval {
        guard let frameDurations, frameDurations.indices.contains(index) else {
            return frameDuration
        }
        return frameDurations[index]
    }
}

/// A pet species. Chooses the whole glyph set for every mood, which character
/// positions the blink scheduler closes, and a rare idle-only "quirk" animation.
/// Personality lives entirely in this data — `PetView` stays generic over it.
public enum PetSpecies: String, CaseIterable, Sendable, Equatable, Codable {
    case dot
    case cat
    case robo
    case owl

    /// Shown in the species picker.
    public var displayName: String {
        switch self {
        case .dot: "Dot"
        case .cat: "Cat"
        case .robo: "Robo"
        case .owl: "Owl"
        }
    }
}

/// Mood -> kaomoji animation table, one full table per species.
///
/// Text glyphs, monospaced, drawn as `Text` in the app layer: no asset pack surveyed
/// (2026-08-12) was both complete and permissively licensed, and a text glyph animates
/// for free off the system font. Every frame of a given species is the same character
/// width on purpose — an open bracket, eyes, a mouth, a close bracket — so a mood
/// switch never reflows the notch. Width differs by species (dot/robo/owl are 5
/// characters, cat is 7 to fit its cheeks), but never within one.
public enum PetGlyphs {
    /// The animation recipe for a mood. Delegates to `.dot` so existing call sites
    /// (and their tests) keep compiling without threading a species through.
    public static func animation(for mood: PetMood) -> MoodAnimation {
        animation(for: mood, species: .dot)
    }

    /// The animation recipe for a mood, for a given species. Each species' switch is
    /// exhaustive over `PetMood`, so a new mood case fails to compile here before it
    /// can fail a test.
    public static func animation(for mood: PetMood, species: PetSpecies) -> MoodAnimation {
        switch species {
        case .dot: dotAnimation(for: mood)
        case .cat: catAnimation(for: mood)
        case .robo: roboAnimation(for: mood)
        case .owl: owlAnimation(for: mood)
        }
    }

    /// Character indices the blink scheduler swaps for the closed-eye en dash.
    /// Position-based rather than a literal glyph match, so the blink still reads on
    /// frames whose open-eye glyph differs by mood (watching, peeking, ...).
    public static func eyeSlots(for species: PetSpecies) -> [Int] {
        switch species {
        case .dot, .robo, .owl: [1, 3]
        case .cat: [2, 4]
        }
    }

    /// A short, one-shot idle-only flourish: rare personality that plays while the pet
    /// is otherwise just idling, never during any other mood. Always still and
    /// non-blinking, so it reads as a distinct beat rather than another ordinary blink.
    public static func quirk(for species: PetSpecies) -> MoodAnimation {
        switch species {
        case .dot:
            // Glance around: a peek left, then right.
            MoodAnimation(frames: ["(‹ᴗ‹)", "(›ᴗ›)"], frameDuration: 0.5, blinks: false, motion: .still)
        case .cat:
            // Contented slow double-squint.
            MoodAnimation(
                frames: ["(=–ᴗ–=)", "(=•ᴗ•=)", "(=–ᴗ–=)"],
                frameDuration: 0.4,
                blinks: false,
                motion: .still
            )
        case .robo:
            // Eye flicker, like a status LED.
            MoodAnimation(frames: ["[□_■]", "[■_□]", "[■_■]"], frameDuration: 0.25, blinks: false, motion: .still)
        case .owl:
            // Slow, deliberate double blink.
            MoodAnimation(
                frames: ["(–ᴗ–)", "(ʘᴗʘ)", "(–ᴗ–)"],
                frameDuration: 0.35,
                blinks: false,
                motion: .still
            )
        }
    }

    /// The full table, one entry per `PetMood`, for `.dot`. Built from `animation(for:)`
    /// so there is exactly one source of truth; exists for callers (and tests) that
    /// want to iterate it without threading a species through. `PetMood` is not
    /// `Hashable`, so this is an array of pairs, not a dictionary.
    public static var all: [(mood: PetMood, animation: MoodAnimation)] {
        PetMood.allCases.map { ($0, animation(for: $0)) }
    }

    // MARK: - Dot (width 5, eyeSlots [1,3])

    private static func dotAnimation(for mood: PetMood) -> MoodAnimation {
        switch mood {
        case .idle:
            // Present, working normally: eyes forward, nothing to perform.
            MoodAnimation(frames: ["(•ᴗ•)"], frameDuration: 1, blinks: true, motion: .bob)
        case .busy:
            // Typing hard: eyes widen and relax, a flicker of focus.
            MoodAnimation(frames: ["(◉ᴗ◉)", "(•ᴗ•)"], frameDuration: 0.6, blinks: true, motion: .bob)
        case .grazing:
            // Scrolling: eyes track side to side like reading down a page.
            MoodAnimation(
                frames: ["(‹ᴗ‹)", "(•ᴗ•)", "(›ᴗ›)", "(•ᴗ•)"],
                frameDuration: 0.9,
                blinks: true,
                motion: .bob
            )
        case .watching:
            // Passive viewing: wide, settled eyes, no bob, slow blink.
            MoodAnimation(frames: ["(◕ᴗ◕)"], frameDuration: 1, blinks: true, motion: .still)
        case .peeking:
            // Break approaching: a curious upward look. The lean out of the notch
            // itself is NotchController's transition, not the face.
            MoodAnimation(frames: ["(◔ᴗ◔)"], frameDuration: 1, blinks: true, motion: .bob)
        case .coaxing:
            // Break in progress: the pet demonstratively looks away, then flicks back
            // to check on you. That is the behaviour the whole app is asking the user
            // to copy, so the look-away holds far longer than the check-back.
            MoodAnimation(
                frames: ["(‹ᴗ‹)", "(•ᴗ•)"],
                frameDuration: 2.0,
                frameDurations: [2.0, 0.3],
                blinks: false,
                motion: .bob
            )
        case .delighted:
            // They actually took the break: a small spring, praise-moment energy.
            MoodAnimation(frames: ["(^ᴗ^)"], frameDuration: 1, blinks: false, motion: .bounce)
        case .sulking:
            // Typed straight through it: no blame, just a sag.
            MoodAnimation(frames: ["(•︵•)"], frameDuration: 1, blinks: false, motion: .droop)
        case .asleep:
            // Nobody home. Three identical face frames: the view derives a rising
            // "z" position from the stepping index instead of baking it into the
            // text, since a single monospaced frame cannot hold a glyph at three
            // different heights.
            MoodAnimation(
                frames: ["(–ᴗ–)", "(–ᴗ–)", "(–ᴗ–)"],
                frameDuration: 0.8,
                blinks: false,
                motion: .still,
                dimmed: true
            )
        case .paused:
            // Deliberately the only mood with zero animation: paused should feel paused.
            MoodAnimation(frames: ["(–ᴗ–)"], frameDuration: 1, blinks: false, motion: .still, dimmed: true)
        }
    }

    // MARK: - Cat (width 7, eyeSlots [2,4]; `=` cheeks/whiskers)

    private static func catAnimation(for mood: PetMood) -> MoodAnimation {
        switch mood {
        case .idle:
            MoodAnimation(frames: ["(=•ᴗ•=)"], frameDuration: 1, blinks: true, motion: .bob)
        case .busy:
            MoodAnimation(frames: ["(=◉ᴗ◉=)", "(=•ᴗ•=)"], frameDuration: 0.6, blinks: true, motion: .bob)
        case .grazing:
            MoodAnimation(
                frames: ["(=‹ᴗ‹=)", "(=•ᴗ•=)", "(=›ᴗ›=)", "(=•ᴗ•=)"],
                frameDuration: 0.9,
                blinks: true,
                motion: .bob
            )
        case .watching:
            MoodAnimation(frames: ["(=◕ᴗ◕=)"], frameDuration: 1, blinks: true, motion: .still)
        case .peeking:
            MoodAnimation(frames: ["(=◔ᴗ◔=)"], frameDuration: 1, blinks: true, motion: .bob)
        case .coaxing:
            MoodAnimation(
                frames: ["(=‹ᴗ‹=)", "(=•ᴗ•=)"],
                frameDuration: 2.0,
                frameDurations: [2.0, 0.3],
                blinks: false,
                motion: .bob
            )
        case .delighted:
            MoodAnimation(frames: ["(=^ᴗ^=)"], frameDuration: 1, blinks: false, motion: .bounce)
        case .sulking:
            MoodAnimation(frames: ["(=•︵•=)"], frameDuration: 1, blinks: false, motion: .droop)
        case .asleep:
            MoodAnimation(
                frames: ["(=–ᴗ–=)", "(=–ᴗ–=)", "(=–ᴗ–=)"],
                frameDuration: 0.8,
                blinks: false,
                motion: .still,
                dimmed: true
            )
        case .paused:
            MoodAnimation(frames: ["(=–ᴗ–=)"], frameDuration: 1, blinks: false, motion: .still, dimmed: true)
        }
    }

    // MARK: - Robo (width 5, eyeSlots [1,3]; square brackets, `_` mouth, never blinks)

    private static func roboAnimation(for mood: PetMood) -> MoodAnimation {
        switch mood {
        case .idle:
            MoodAnimation(frames: ["[■_■]"], frameDuration: 1, blinks: false, motion: .bob)
        case .busy:
            MoodAnimation(frames: ["[▣_▣]", "[■_■]"], frameDuration: 0.6, blinks: false, motion: .bob)
        case .grazing:
            MoodAnimation(
                frames: ["[‹_‹]", "[■_■]", "[›_›]", "[■_■]"],
                frameDuration: 0.9,
                blinks: false,
                motion: .bob
            )
        case .watching:
            MoodAnimation(frames: ["[◉_◉]"], frameDuration: 1, blinks: false, motion: .still)
        case .peeking:
            MoodAnimation(frames: ["[◔_◔]"], frameDuration: 1, blinks: false, motion: .bob)
        case .coaxing:
            MoodAnimation(
                frames: ["[‹_‹]", "[■_■]"],
                frameDuration: 2.0,
                frameDurations: [2.0, 0.3],
                blinks: false,
                motion: .bob
            )
        case .delighted:
            MoodAnimation(frames: ["[^_^]"], frameDuration: 1, blinks: false, motion: .bounce)
        case .sulking:
            MoodAnimation(frames: ["[■︵■]"], frameDuration: 1, blinks: false, motion: .droop)
        case .asleep:
            MoodAnimation(
                frames: ["[–_–]", "[–_–]", "[–_–]"],
                frameDuration: 0.8,
                blinks: false,
                motion: .still,
                dimmed: true
            )
        case .paused:
            MoodAnimation(frames: ["[–_–]"], frameDuration: 1, blinks: false, motion: .still, dimmed: true)
        }
    }

    // MARK: - Owl (width 5, eyeSlots [1,3]; ʘ eyes, stillness is the personality)

    private static func owlAnimation(for mood: PetMood) -> MoodAnimation {
        switch mood {
        case .idle:
            MoodAnimation(frames: ["(ʘᴗʘ)"], frameDuration: 1, blinks: true, motion: .still)
        case .busy:
            MoodAnimation(frames: ["(◉ᴗ◉)", "(ʘᴗʘ)"], frameDuration: 0.6, blinks: true, motion: .still)
        case .grazing:
            MoodAnimation(
                frames: ["(‹ᴗ‹)", "(ʘᴗʘ)", "(›ᴗ›)", "(ʘᴗʘ)"],
                frameDuration: 0.9,
                blinks: true,
                motion: .still
            )
        case .watching:
            MoodAnimation(frames: ["(◕ᴗ◕)"], frameDuration: 1, blinks: true, motion: .still)
        case .peeking:
            // The one mood an owl moves for.
            MoodAnimation(frames: ["(◔ᴗ◔)"], frameDuration: 1, blinks: true, motion: .bob)
        case .coaxing:
            MoodAnimation(
                frames: ["(‹ᴗ‹)", "(ʘᴗʘ)"],
                frameDuration: 2.0,
                frameDurations: [2.0, 0.3],
                blinks: false,
                motion: .still
            )
        case .delighted:
            MoodAnimation(frames: ["(^ᴗ^)"], frameDuration: 1, blinks: false, motion: .bounce)
        case .sulking:
            MoodAnimation(frames: ["(ʘ︵ʘ)"], frameDuration: 1, blinks: false, motion: .droop)
        case .asleep:
            MoodAnimation(
                frames: ["(–ᴗ–)", "(–ᴗ–)", "(–ᴗ–)"],
                frameDuration: 0.8,
                blinks: false,
                motion: .still,
                dimmed: true
            )
        case .paused:
            MoodAnimation(frames: ["(–ᴗ–)"], frameDuration: 1, blinks: false, motion: .still, dimmed: true)
        }
    }
}
