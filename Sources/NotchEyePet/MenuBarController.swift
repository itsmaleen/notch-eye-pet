import AppKit
import EyePetCore
import SwiftUI

/// Menu bar item: status, schedule presets, and the manual controls.
///
/// A menu bar presence is not redundant with the notch — it is where the app lives on
/// Macs with no notch, and it is where the user goes to find settings and to trust that
/// nothing is running the camera.
///
/// The contents are built on demand in `menuNeedsUpdate(_:)` rather than pushed from a
/// subscription. A menu only has to be right at the instant it opens, and rebuilding it
/// on every phase change meant ~15 `NSMenuItem` allocations *and* a synchronous XPC
/// round-trip to `smd` (via `LaunchAtLogin.isEnabled`) on the main thread once a second
/// for the life of the app, to refresh something nobody was looking at.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    /// Preset name/schedule pairs, shared with the settings window so the two surfaces
    /// never drift out of sync about what "20-20-20" means.
    static let presets: [(name: String, schedule: BreakSchedule)] = [
        ("20-20-20 (20 min / 20 s)", .twentyTwentyTwenty),
        ("Hourly micro (60 min / 10 s)", .hourlyMicro),
        ("Debug fast (20 s / 5 s)", .debugFast)
    ]

    private let model: AppModel
    private let settings: SettingsWindowController
    private let statusItem: NSStatusItem

    init(model: AppModel, settings: SettingsWindowController) {
        self.model = model
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
    }

    func start() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "eye",
                accessibilityDescription: "Notch Eye Pet"
            )
            button.image?.isTemplate = true
        }

        // Attached empty; `menuNeedsUpdate(_:)` fills it just before each open.
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    func stop() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: model.statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let presence = NSMenuItem(
            title: "State: \(model.presence.rawValue) · pet: \(model.mood.rawValue)",
            action: nil,
            keyEquivalent: ""
        )
        presence.isEnabled = false
        menu.addItem(presence)

        let todayCounts = model.todayBreakCounts
        let stats = NSMenuItem(
            title: "Today: \(todayCounts.taken) taken · \(todayCounts.ignored) missed",
            action: nil,
            keyEquivalent: ""
        )
        stats.isEnabled = false
        menu.addItem(stats)

        let streak = model.breakStreak
        if streak >= 2 {
            let streakItem = NSMenuItem(title: "Streak: \(streak) days", action: nil, keyEquivalent: "")
            streakItem.isEnabled = false
            menu.addItem(streakItem)
        }

        menu.addItem(.separator())

        menu.addItem(action("Take a break now", #selector(breakNow)))
        menu.addItem(action("Skip this one", #selector(skip)))
        menu.addItem(action(isPaused ? "Resume" : "Pause", #selector(togglePause)))

        menu.addItem(.separator())

        for (name, schedule) in Self.presets {
            let item = action(name, #selector(pickSchedule(_:)))
            item.representedObject = ScheduleBox(name: name, schedule: schedule)
            item.state = model.scheduleName == name ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let launchAtLogin = action("Launch at Login", #selector(toggleLaunchAtLogin))
        launchAtLogin.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchAtLogin)

        menu.addItem(action("Settings…", #selector(openSettings)))

        menu.addItem(.separator())
        menu.addItem(action("Quit", #selector(quit)))
    }

    private var isPaused: Bool { model.phase == .paused }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private final class ScheduleBox: NSObject {
        let name: String
        let schedule: BreakSchedule
        init(name: String, schedule: BreakSchedule) {
            self.name = name
            self.schedule = schedule
        }
    }

    // None of these rebuild the menu: picking an item closes it, and the next open
    // rebuilds from scratch.

    @objc private func breakNow() { model.engine.breakNow() }
    @objc private func skip() { model.engine.skip() }

    @objc private func togglePause() {
        if isPaused { model.resume() } else { model.pause() }
    }

    @objc private func pickSchedule(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ScheduleBox else { return }
        model.apply(schedule: box.schedule, named: box.name)
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
    }

    @objc private func openSettings() { settings.show() }

    @objc private func quit() { NSApp.terminate(nil) }
}
