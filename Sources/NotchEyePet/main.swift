import AppKit
import EyePetCore

/// Entry point.
///
/// Built as a SwiftPM executable rather than an Xcode project so the whole thing is
/// plain text an agent (or a human) can edit without wrestling pbxproj XML.
/// `Scripts/bundle.sh` wraps the binary in a proper .app with `LSUIElement` set —
/// run that, not the bare binary, or the notch window and menu bar item will not
/// behave like a real accessory app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel(schedule: .twentyTwentyTwenty)
    private lazy var notch = NotchController(model: model)
    private lazy var settings = SettingsWindowController(model: model, notchController: notch)
    private lazy var menuBar = MenuBarController(model: model, settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        menuBar.start()
        notch.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notch.stop()
        menuBar.stop()
        model.stop()
    }
}

// `NotchEyePet --probe` dumps the presence signals and exits without showing any UI.
// Cross-check the assertion lines against `pmset -g assertions`; if they disagree,
// PowerAssertions.swift is wrong, not pmset.
if CommandLine.arguments.contains("--probe") {
    let clocks = IdleClocks.sample()
    print("idle clocks (seconds since last event)")
    print(String(format: "  anyInput     %8.2f", clocks.anyInput))
    print(String(format: "  keyDown      %8.2f", clocks.keyDown))
    print(String(format: "  mouseClick   %8.2f", clocks.mouseClick))
    print(String(format: "  mouseMoved   %8.2f", clocks.mouseMoved))
    print(String(format: "  scrollWheel  %8.2f", clocks.scrollWheel))
    print("texture: typing=\(clocks.isTyping()) scrolling=\(clocks.isScrolling()) drifting=\(clocks.isDrifting())")

    let prevented = PowerAssertions.isDisplaySleepPrevented()
    print("\ndisplay sleep prevented: \(prevented)")
    let awake = PowerAssertions.displayAwakeAssertions()
    print("display-awake assertions: \(awake.count)")
    for assertion in awake {
        print("  pid \(assertion.pid) [\(assertion.type)] \(assertion.name) media=\(assertion.looksLikeMediaPlayback)")
    }
    print("total assertions held: \(PowerAssertions.current().count)")

    let sample = PresenceSample(clocks: clocks, displaySleepPrevented: prevented)
    print("\npresence (lock/sleep unknown in probe mode): \(PresenceClassifier.classify(sample).rawValue)")
    exit(0)
}

// Top-level code in main.swift is nonisolated, but everything below touches
// main-actor state. We are on the main thread at process start by definition, so
// asserting that is safe. `delegate` is a top-level binding on purpose:
// `NSApplication.delegate` is weak, so something has to hold it.
let delegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.delegate = delegate
    app.run()
}
