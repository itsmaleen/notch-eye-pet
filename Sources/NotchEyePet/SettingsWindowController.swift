import AppKit
import SwiftUI

/// Owns the single settings window, reachable from the menu bar's "Settings…" item.
///
/// The app is `LSUIElement` (accessory, no Dock icon, no application menu), so there is
/// no standard "Settings…" plumbing to hook into — this opens an `NSWindow` by hand and
/// keeps it around so a second click focuses the existing window instead of stacking a
/// duplicate.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let notchController: NotchController
    private var window: NSWindow?

    init(model: AppModel, notchController: NotchController) {
        self.model = model
        self.notchController = notchController
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(
            rootView: SettingsView(model: model, notchController: notchController)
        )

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 1),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Notch Eye Pet Settings"
        newWindow.contentView = hosting
        // Accessory apps have no app-wide window manager holding this for us, and we
        // want to reuse the same instance rather than let AppKit deallocate it on close.
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.center()
        window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
