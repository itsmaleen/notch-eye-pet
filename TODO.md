# TODO

Working list. `PLAN.md` has the phase reasoning; this is what to actually pick up.

## Start here (next session)

- [ ] **Live with it.** The full cycle is built and visually verified (see `docs/images/`), but nobody has worn it for a real workday: is the always-visible pet tolerable? Is 20-20-20 the right default? Does the coaxing look-away read?
- [ ] **Verify behaviour on an external display** (no notch → DynamicNotchKit floating fallback). Untested — needs the hardware plugged in.
- [ ] Multi-display: pick the screen; suppress during fullscreen presentations and screen sharing.
- [ ] `Package.swift` pins `swiftLanguageMode(.v5)` to dodge strict concurrency during scaffolding. Migrate to v6 and delete the pins.

## Known gaps in what exists

- [ ] `SessionMonitor` assumes unlocked + awake at launch. There is no public API to query lock state, only notifications, so state is correct only from launch onward. Acceptable, but note it if it causes a weird first tick.
- [ ] Distributed notifications (`com.apple.screenIsLocked`) are not sandbox-safe. Fine for direct distribution; blocks Mac App Store. Decide before Phase 5.
- [ ] A persisted "Debug fast" schedule survives relaunch, which will surprise anyone who forgot they picked it. Consider resetting debug presets on launch.
- [x] ~~Nothing persists~~ → `Preferences` (UserDefaults): schedule, pause, species, pet visibility, sound.
- [x] ~~`AppModel.tick()` runs at a fixed 1 Hz even when absent~~ → backs off to 5 s while absent.
- [x] ~~`BreakEngine.tick` trusts the caller's delta~~ → clamped via `AccrualPolicy.maxTickDelta` (default 10 s), tested.

## Phase 1 — feel ✅ (art direction changed: text glyphs, not sprites)

- [x] Pet art: kaomoji-style text-glyph pet (`PetGlyphs`, pure data + width-invariant tests). Asset-pack survey found nothing complete + clean + permissively licensed; the two notch-specific moods (peeking, coaxing) exist in no generic pack.
- [x] Full cycle visually verified in the notch: working → peek → break → praise (screenshots in `docs/images/`)
- [x] Optional soft sound at break start ("Purr", volume 0.5), off by default
- [ ] Tune peek/emerge motion via `DynamicNotchTransitionConfiguration` if the default expand still reads as a banner after real use

## Phase 2 — stickiness ✅ (except multi-display, moved up top)

- [x] `UserDefaults` persistence (`Preferences`)
- [x] Launch at login via `SMAppService.mainApp` (menu + settings toggle; status read back honestly)
- [x] SwiftUI settings window: preset picker + custom schedule editor, species picker, pet visibility, sound, login item
- [x] Local streaks and stats (`BreakLedger`, pure + tested; "Today: N taken · M missed" in the menu)

## Phase 3 — personality ✅

- [x] 4 species, selectable in Settings: Dot `(•ᴗ•)`, Cat `(=•ᴗ•=)`, Robo `[■_■]` (never blinks), Owl `(ʘᴗʘ)` (holds still)
- [x] Distinct animations per activity texture (busy flicker, grazing eye-tracking, watching stillness)
- [x] Rate-limited idle quirks (once per 180–360 s of continuous idle, cancelled by any mood change)

## Phase 4 — camera, opt-in and off by default

Read the camera section of `CLAUDE.md` first. There is no gaze API on macOS and the LED cannot be suppressed.

- [ ] Sampled `AVCaptureSession` (~10 s every 5 min), never streaming
- [ ] Blink rate via eye-aspect-ratio from `VNFaceLandmarks2D` eye contours
- [ ] Break-compliance confirmation via `VNFaceObservation.yaw`/`.pitch`
- [ ] Add `NSCameraUsageDescription` to `Scripts/bundle.sh`'s Info.plist only at this point
- [ ] Visible in-app indicator whenever the camera is open; hard off switch; never persist frames

## Phase 5 — ship

- [ ] App icon
- [ ] Notarised zip or DMG
- [ ] README with screenshots
- [ ] Licence decision (MIT if OSS) and DynamicNotchKit credit

## Open questions

- [ ] Does an always-visible pet beat one that only appears for breaks? The retention thesis says visible; clutter says not. Needs a week of real use, not an opinion.
- [ ] Should `passive` (video) accrue at full weight? Currently 1.0, same as active. Blink rate during passive viewing differs from active work, so this is a guess. `AccrualPolicy.passiveWeight` is the knob.
- [ ] Is 90 s the right idle threshold? Untested against real work rhythm.
- [ ] Notch contention: what happens if boring.notch or MewNotch is also running? Detect on launch and say something honest.
