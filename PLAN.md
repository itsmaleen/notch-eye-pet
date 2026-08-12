# Build plan

Status as of 2026-08-12 (second session): **Phases 0–3 done** except multi-display (10) and the motion-tuning judgment call (2), which needs real-world wear first. The pet is text glyphs rather than pixel sprites — the asset-pack survey found nothing complete + clean + permissively licensed, and the notch-specific moods (peeking, coaxing) exist in no generic pack. See TODO.md for current state and docs/images/ for the verified cycle.

The ordering is deliberate. The product thesis is that *charm buys retention where enforcement fails*, so the art and the interruption feel are not polish to do at the end — they are the risky part, and they come before features.

---

## Phase 0 — Skeleton ✅ done

Everything below builds, tests, and runs.

- [x] SwiftPM package, no `.xcodeproj` (plain text an agent can edit)
- [x] `EyePetCore`: idle clocks, power assertions, presence classifier, break engine, pet mood
- [x] Three-state presence model with unit tests (11 passing)
- [x] `SessionMonitor` for lock / sleep / screensaver
- [x] `AppModel` 1 Hz tick loop
- [x] `NotchController` on DynamicNotchKit 1.1.0
- [x] Placeholder vector pet with per-mood expressions
- [x] Menu bar item: status, break now, skip, pause, schedule presets
- [x] `Scripts/bundle.sh` → real `.app` with `LSUIElement`, ad-hoc signed
- [x] `--probe` headless mode, cross-checked against `pmset -g assertions`
- [x] Verified: `caffeinate -d` flips classification `absent` → `passive` correctly

**Not verified: what the notch UI actually looks like.** The app launches and stays resident, but nobody has looked at it. That is task 1.

---

## Phase 1 — Make it feel right

The make-or-break phase. If the interruption feels like a nag, no amount of feature work saves it.

1. **Look at it.** Run `./Scripts/run.sh`, set "Debug fast", watch a full work → peek → break → praise cycle. Screenshot each state.
2. **Tune the motion.** The peek (pre-break) should read as a creature leaning out, not a notification sliding down. `DynamicNotchTransitionConfiguration` exposes the animations.
3. **Real art.** Replace `PetView`'s vector blob with pixel sprite sheets, one per mood. This is the single highest-leverage change in the project.
4. **Decide the always-visible question.** `NotchController.alwaysShowPet` currently defaults true. A resident pet is the retention thesis, but it may read as clutter. Try both for a day each.
5. **Sound, off by default.** One soft cue at break start. Test whether it helps or annoys.

## Phase 2 — Make it stick

6. **Persistence.** `UserDefaults` for schedule, `alwaysShowPet`, pet species. Currently everything resets on launch.
7. **Launch at login** via `SMAppService.mainApp`.
8. **Settings window.** SwiftUI, reachable from the menu bar. Schedule editor with a custom option, not just presets.
9. **Streaks and stats.** Breaks taken vs ignored, per day. Retention mechanic and a self-honesty signal. Keep it local; no telemetry.
10. **Multi-display and fullscreen.** Which screen gets the notch when there are two? Suppress during fullscreen presentations and screen sharing.

## Phase 3 — Species and personality

11. **Multiple pets.** Buddi ships 18 species; personalisation drives attachment, and attachment is the retention mechanism. Pick 4–6 good ones over 18 mediocre ones.
12. **Reactions to activity texture.** The `IdleClocks` per-type signals are already wired into `PetMood` — `grazing` when scrolling, `busy` when typing. Give each a distinct animation.
13. **Idle personality.** Occasional unprompted animations during long work stretches, rate-limited hard.

## Phase 4 — The camera lane (opt-in, off by default)

Only worth building because it is what would make this defensible rather than the twenty-first 20-20-20 timer. Read the camera section of `CLAUDE.md` before starting.

14. **Sampled capture.** ~10s of `AVCaptureSession` every 5 min, not streaming. Add `NSCameraUsageDescription` to the bundle plist *only* at this point.
15. **Blink rate** via eye-aspect-ratio from `VNFaceLandmarks2D` eye contours. Surface it as a trend, not a live number.
16. **Break compliance** via `VNFaceObservation.yaw`/`.pitch` swinging off-axis. This is the payoff: the pet reacts to a real look-away instead of assuming one from keyboard silence.
17. **Kill switch and honesty.** Visible indicator whenever the app has the camera open, a hard off toggle, and never write frames to disk.

## Phase 5 — Ship

18. Icon, DMG or notarised zip, README with screenshots.
19. Decide: free/OSS (fits the personal-project pattern and the notch-app community) vs paid. Mac Pet clears $9.99 for less.
20. If OSS: MIT, and credit DynamicNotchKit prominently.

---

## Deliberately not doing

- **Full-screen blur overlays.** That is the enforcement model this product is arguing against.
- **Real gaze tracking.** No macOS API exists; webcam gaze models are a few degrees accurate at best and collapse with glasses and bad lighting. Blink + head pose is the useful subset.
- **Cloud anything.** No accounts, no sync, no telemetry.
