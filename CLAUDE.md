# Notch Eye Pet — agent context

A macOS accessory app: a pet lives in the MacBook notch and comes out to make you look away from the screen.

**Read this file first, then `PLAN.md` for phases and `TODO.md` for what to do next.**

## What makes this different from the twenty other 20-20-20 apps

Nobody has built an eye-break app that lives in the notch as a character. Verified Aug 2026: ~20 open-source eye-break apps exist, all menu-bar + full-screen-overlay; ~10 notch pets exist, all of them coding-agent status pets; the nearest neighbour overall is Mac Pet (proprietary, $9.99, notch pet + Pomodoro, no eye care). The clusters are disjoint.

## The evidence, because it drives the design

Two primary studies, and they disagree in a way that matters:

- **Johnson & Rosenfield**, *Optom Vis Sci* 2023;100(1):52–56. n=30, 40-minute tablet task, breaks at 5/10/20/40 min. **Break frequency made no measurable difference.** The "20-20-20" numbers trace to a media soundbite by Dr. Jeffrey Anshel, not a trial.
- **Talens-Estarelles et al.**, *Cont Lens Anterior Eye* 2023. n=29, webcam-driven personalised reminders for two weeks. **Dry-eye scores improved** (OSDI, DEQ-5, SANDE) — and **regressed within a week of the reminders stopping**.

Three consequences that are baked into the code:

1. **Never claim the numbers are proven.** Schedules are user preference. `BreakSchedule` ships presets, not a doctrine.
2. **Retention is the product, not enforcement.** The benefit dies when the app gets disabled, so *not being annoying* is the whole ballgame. This is the actual argument for a charming pet over a screen-blurring overlay — it is not a gimmick, it is the mechanism. Weigh every UX decision against "would this make someone quit the app?"
3. **Prompt the blink, not just the distance.** The measurable win was dry eye, which is a blink-rate story. Break copy says "and blink" deliberately.

## Architecture

```
Sources/EyePetCore/     Pure logic. No AppKit UI, no timers, no I/O. Fully unit-tested.
  IdleClocks.swift      CGEventSource per-event-type idle. Zero permissions.
  PowerAssertions.swift IOKit — separates passive viewing from absence.
  Presence.swift        PresenceSample -> PresenceState. Pure function.
  BreakSchedule.swift   Presets + accrual policy.
  BreakEngine.swift     The state machine. tick(delta:sample:) — no wall clock.
  PetMood.swift         phase + presence + texture -> PetMood.

Sources/NotchEyePet/    App layer.
  main.swift            Entry point, plus `--probe` headless dump.
  SessionMonitor.swift  NSWorkspace + distributed notifications -> PresenceSample.
  AppModel.swift        1 Hz tick loop, @Published state.
  NotchController.swift DynamicNotchKit wiring.
  PetView.swift         Placeholder vector pet + break panel.
  MenuBarController.swift NSStatusItem.
```

### Non-obvious decisions, do not undo casually

- **DynamicNotchKit (MIT), never boring.notch (GPL-3).** boring.notch has 10.3k stars and is tempting, but building on it forces GPL on this app. DynamicNotchKit also gives a floating-pill fallback on non-notch screens for free, which matters for external displays.
- **`EyePetCore` has no AppKit UI dependency on purpose.** The engine is a pure function of (delta, sample), so tests simulate a workday in microseconds. Keep it that way — if you need session state in core logic, pass it in via `PresenceSample`.
- **1 Hz polling, not event taps.** Every signal is recency-based, so nothing is missed between ticks, and it avoids the Accessibility (TCC) permission that an event tap would require. **The app currently needs zero permissions. That is a feature — protect it.**
- **Swift language mode is pinned to `.v5`** in `Package.swift` to avoid a strict-concurrency fight during scaffolding. Migrating to v6 is a TODO, not an accident.

### Three-state presence model — the core idea

| State | Detection | Timer |
|---|---|---|
| `absent` | idle > 90s with no display assertion, or locked / asleep / screensaver | pause + decay (2x) |
| `passive` | idle **but** `PreventUserIdleDisplaySleep` held (video, long read) | keep accruing |
| `active` | recent input | accrue at full rate |

The `passive` state is the whole point. A naive idle timer sees someone watching a 40-minute video as *absent* and never nudges them — during peak eye load. LookAway's best-reviewed behaviour is just `absent` done well; almost every OSS competitor skips it, fires breaks at empty desks, and gets uninstalled.

## There is no gaze API on macOS

Do not go looking. `rg -ril "gaze"` across every header in `Vision.framework` returns **zero files**. Apple's Eye Tracking accessibility feature is iOS/iPadOS 18 only; visionOS has it because Vision Pro has the hardware.

What Vision *does* offer, if the opt-in camera lane is built: `VNFaceLandmarks2D.leftEye`/`.rightEye` contours (enough for eye-aspect-ratio blink detection), `.leftPupil`/`.rightPupil` (the header warns they are unreliable mid-blink), and `VNFaceObservation.roll`/`.yaw` (macOS 10.14+) / `.pitch` (macOS 12+).

**The camera LED is wired to the sensor in hardware and cannot be suppressed by any software.** A green dot lit all workday is not an acceptable default for a background health app. If the camera lane is built it must be opt-in, off by default, and **sampled** (~10s every 5 min) rather than streaming — blink *rate* is a statistical quantity and samples fine.

## Build and run

```bash
swift build && swift test          # 11 tests, all pure logic
./Scripts/run.sh                   # bundle + relaunch the .app
./.build/debug/NotchEyePet --probe # headless signal dump, no UI
pmset -g assertions                # ground truth to check --probe against
```

Always run the **`.app`**, not the bare binary — `LSUIElement` in the bundle Info.plist is what makes it an accessory app. Pick "Debug fast (20 s / 5 s)" from the menu bar rather than waiting 20 minutes to see the break UI.

## Background reading in the Wrinkles wiki

- `~/wrinkles/wiki/articles/notch_eye_break_pet.md` — prior-art scan, evidence, competitor teardown
- `~/wrinkles/wiki/articles/macos_presence_detection.md` — the verified API surface, with the probe output

## House rules

- No AI attribution in commits or code comments. No `Co-Authored-By` trailers.
- No em dashes in anything user-facing that goes outward.
