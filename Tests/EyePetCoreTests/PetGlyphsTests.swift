import XCTest
@testable import EyePetCore

/// `PetGlyphs` is pure data, so these are invariant checks on the mood table.
/// SwiftUI text rendering has no way to surface a jittery frame or a broken grapheme
/// at runtime, so the invariants live here instead.
final class PetGlyphsTests: XCTestCase {
    // MARK: - Coverage

    func testEveryMoodHasAnAnimation() {
        // `animation(for:)` switches exhaustively over `PetMood`, so this only proves
        // itself if a case were ever missing the file would fail to compile. Keeping
        // the runtime check too documents the invariant for anyone reading the tests.
        XCTAssertEqual(PetGlyphs.all.count, PetMood.allCases.count)
    }

    func testEveryMoodHasAtLeastOneFrame() {
        for mood in PetMood.allCases {
            XCTAssertGreaterThanOrEqual(
                PetGlyphs.animation(for: mood).frames.count, 1,
                "\(mood) has no frames"
            )
        }
    }

    // MARK: - Monospace safety

    func testFramesWithinAMoodAreEqualWidth() {
        for mood in PetMood.allCases {
            let frames = PetGlyphs.animation(for: mood).frames
            let widths = Set(frames.map(\.count))
            XCTAssertEqual(widths.count, 1, "\(mood) frames have mixed widths: \(frames)")
        }
    }

    func testNoFrameContainsCombiningCharacters() {
        for mood in PetMood.allCases {
            for frame in PetGlyphs.animation(for: mood).frames {
                for scalar in frame.unicodeScalars {
                    XCTAssertFalse(
                        isCombining(scalar),
                        "\(mood) frame \"\(frame)\" contains combining scalar U+\(String(scalar.value, radix: 16))"
                    )
                }
            }
        }
    }

    // MARK: - Timing

    func testFrameDurationsAreAlwaysPositive() {
        for mood in PetMood.allCases {
            let animation = PetGlyphs.animation(for: mood)
            XCTAssertGreaterThan(animation.frameDuration, 0, "\(mood)")
            for duration in animation.frameDurations ?? [] {
                XCTAssertGreaterThan(duration, 0, "\(mood)")
            }
        }
    }

    func testFrameDurationsOverrideCountMatchesFrameCount() {
        for mood in PetMood.allCases {
            let animation = PetGlyphs.animation(for: mood)
            guard let frameDurations = animation.frameDurations else { continue }
            XCTAssertEqual(frameDurations.count, animation.frames.count, "\(mood)")
        }
    }

    // MARK: - Duration lookup

    func testDurationForFrameFallsBackToScalarWhenNoOverride() {
        let animation = PetGlyphs.animation(for: .idle)
        XCTAssertEqual(animation.duration(forFrame: 0), animation.frameDuration)
    }

    func testDurationForFrameHonorsAsymmetricOverride() {
        let animation = PetGlyphs.animation(for: .coaxing)
        XCTAssertEqual(animation.duration(forFrame: 0), 2.0)
        XCTAssertEqual(animation.duration(forFrame: 1), 0.3)
    }

    // MARK: - Spec-specific spot checks

    /// Coaxing is the pet demonstratively looking away, then flicking back to check on
    /// the user: the behaviour the whole app is asking them to copy. It reads wrong if
    /// the hold and the check-back are the same length.
    func testCoaxingHoldsTheLookAwayLongerThanTheCheckBack() {
        let animation = PetGlyphs.animation(for: .coaxing)
        guard let frameDurations = animation.frameDurations, frameDurations.count == 2 else {
            XCTFail("coaxing should have an asymmetric two-frame timing override")
            return
        }
        XCTAssertGreaterThan(frameDurations[0], frameDurations[1])
    }

    /// Paused is the one mood that should never animate: it should read as stopped,
    /// not as a variant of asleep.
    func testPausedIsStaticAndDimmed() {
        let animation = PetGlyphs.animation(for: .paused)
        XCTAssertEqual(animation.frames.count, 1)
        XCTAssertTrue(animation.dimmed)
        XCTAssertEqual(animation.motion, .still)
    }

    func testOnlyAsleepAndPausedAreDimmed() {
        for mood in PetMood.allCases {
            let dimmed = PetGlyphs.animation(for: mood).dimmed
            switch mood {
            case .asleep, .paused: XCTAssertTrue(dimmed, "\(mood) should be dimmed")
            default: XCTAssertFalse(dimmed, "\(mood) should not be dimmed")
            }
        }
    }

    private func isCombining(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    // MARK: - Species

    /// Every (species, mood) pair needs at least one frame, and so does the quirk —
    /// an empty frame list would render nothing.
    func testEverySpeciesMoodHasAtLeastOneFrame() {
        for species in PetSpecies.allCases {
            for mood in PetMood.allCases {
                XCTAssertGreaterThanOrEqual(
                    PetGlyphs.animation(for: mood, species: species).frames.count, 1,
                    "\(species) \(mood) has no frames"
                )
            }
            XCTAssertGreaterThanOrEqual(
                PetGlyphs.quirk(for: species).frames.count, 1,
                "\(species) quirk has no frames"
            )
        }
    }

    /// Stronger than `testFramesWithinAMoodAreEqualWidth`: every frame across every
    /// mood AND the quirk, for a given species, must share one width, since the view
    /// swaps between them without reflowing the notch.
    func testAllFramesOfASpeciesShareOneWidth() {
        for species in PetSpecies.allCases {
            var widths = Set<Int>()
            for mood in PetMood.allCases {
                widths.formUnion(PetGlyphs.animation(for: mood, species: species).frames.map(\.count))
            }
            widths.formUnion(PetGlyphs.quirk(for: species).frames.map(\.count))
            XCTAssertEqual(widths.count, 1, "\(species) frames have mixed widths: \(widths)")
        }
    }

    func testNoSpeciesFrameContainsCombiningCharacters() {
        for species in PetSpecies.allCases {
            var frames = PetMood.allCases.flatMap { PetGlyphs.animation(for: $0, species: species).frames }
            frames += PetGlyphs.quirk(for: species).frames
            for frame in frames {
                for scalar in frame.unicodeScalars {
                    XCTAssertFalse(
                        isCombining(scalar),
                        "\(species) frame \"\(frame)\" contains combining scalar U+\(String(scalar.value, radix: 16))"
                    )
                }
            }
        }
    }

    /// `PetView` closes whatever sits at `eyeSlots` on every frame it shows, so those
    /// indices must be valid for every frame of that species, mood frames and quirk
    /// frames alike.
    func testEyeSlotsAreInBoundsForEveryFrame() {
        for species in PetSpecies.allCases {
            let slots = PetGlyphs.eyeSlots(for: species)
            var frames = PetMood.allCases.flatMap { PetGlyphs.animation(for: $0, species: species).frames }
            frames += PetGlyphs.quirk(for: species).frames
            for frame in frames {
                let count = frame.count
                for slot in slots {
                    XCTAssertTrue(
                        slot >= 0 && slot < count,
                        "\(species) frame \"\(frame)\" eye slot \(slot) out of bounds (width \(count))"
                    )
                }
            }
        }
    }

    func testSpeciesFrameDurationsOverrideCountMatchesFrameCountAndArePositive() {
        for species in PetSpecies.allCases {
            for mood in PetMood.allCases {
                let animation = PetGlyphs.animation(for: mood, species: species)
                XCTAssertGreaterThan(animation.frameDuration, 0, "\(species) \(mood)")
                if let frameDurations = animation.frameDurations {
                    XCTAssertEqual(frameDurations.count, animation.frames.count, "\(species) \(mood)")
                    for duration in frameDurations {
                        XCTAssertGreaterThan(duration, 0, "\(species) \(mood)")
                    }
                }
            }
            let quirk = PetGlyphs.quirk(for: species)
            XCTAssertGreaterThan(quirk.frameDuration, 0, "\(species) quirk")
            if let frameDurations = quirk.frameDurations {
                XCTAssertEqual(frameDurations.count, quirk.frames.count, "\(species) quirk")
                for duration in frameDurations {
                    XCTAssertGreaterThan(duration, 0, "\(species) quirk")
                }
            }
        }
    }

    /// Robots do not blink — that IS the personality — for every mood, not just idle.
    func testRoboNeverBlinks() {
        for mood in PetMood.allCases {
            XCTAssertFalse(
                PetGlyphs.animation(for: mood, species: .robo).blinks,
                "robo \(mood) should never blink"
            )
        }
    }

    func testPetSpeciesRoundTripsThroughCodable() throws {
        for species in PetSpecies.allCases {
            let data = try JSONEncoder().encode(species)
            let decoded = try JSONDecoder().decode(PetSpecies.self, from: data)
            XCTAssertEqual(decoded, species)
        }
    }
}
