import AppKit
import Combine
import EyePetCore
import SwiftUI

/// Menu bar item: status, schedule presets, and the manual controls.
///
/// A menu bar presence is not redundant with the notch — it is where the app lives on
/// Macs with no notch, and it is where the user goes to find settings and to trust that
/// nothing is running the camera.
@MainActor
final class MenuBarController {
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
    private var cancellable: AnyCancellable?

    init(model: AppModel, settings: SettingsWindowController) {
        self.model = model
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    func start() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "eye",
                accessibilityDescription: "Notch Eye Pet"
            )
            button.image?.isTemplate = true
        }
        rebuildMenu()

        cancellable = model.$phase
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.rebuildMenu() }
    }

    func stop() {
        cancellable = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

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

        statusItem.menu = menu
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

    @objc private func breakNow() { model.engine.breakNow(); rebuildMenu() }
    @objc private func skip() { model.engine.skip(); rebuildMenu() }

    @objc private func togglePause() {
        if isPaused { model.resume() } else { model.pause() }
        rebuildMenu()
    }

    @objc private func pickSchedule(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ScheduleBox else { return }
        model.apply(schedule: box.schedule, named: box.name)
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        rebuildMenu()
    }

    @objc private func openSettings() { settings.show() }

    @objc private func quit() { NSApp.terminate(nil) }
}
