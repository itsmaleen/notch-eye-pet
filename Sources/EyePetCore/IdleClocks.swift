import CoreGraphics
import Foundation

/// Seconds since the last input event, read per event type.
///
/// This is the whole reason the app needs no permissions: `CGEventSource` exposes
/// recency-of-input without an event tap, so there is no Accessibility (TCC) prompt,
/// no `CGEventTapCreate`, and nothing for the user to approve at install time.
///
/// Verified on macOS 26.5 / Swift 6.3 (2026-08-12) — a live probe returned:
///
///     anyInput  89.73s
///     keyDown   89.94s
///     leftMouse 99.11s
///     mouseMove 99.13s
///     scroll   113.12s
///
/// Note `CGEventType(rawValue: ~0)` (`kCGAnyInputEventType`) does *not* return nil,
/// contra a widely repeated StackOverflow warning. We still avoid force-unwrapping it.
public struct IdleClocks: Sendable, Equatable {
    /// Seconds since *any* input event (keyboard, mouse, tablet).
    public let anyInput: TimeInterval
    public let keyDown: TimeInterval
    public let mouseClick: TimeInterval
    public let mouseMoved: TimeInterval
    public let scrollWheel: TimeInterval

    public init(
        anyInput: TimeInterval,
        keyDown: TimeInterval,
        mouseClick: TimeInterval,
        mouseMoved: TimeInterval,
        scrollWheel: TimeInterval
    ) {
        self.anyInput = anyInput
        self.keyDown = keyDown
        self.mouseClick = mouseClick
        self.mouseMoved = mouseMoved
        self.scrollWheel = scrollWheel
    }

    private static let anyInputEventType = CGEventType(rawValue: ~0)

    private static func seconds(since type: CGEventType?) -> TimeInterval {
        guard let type else { return .infinity }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type)
    }

    /// Samples every clock from the HID system state.
    public static func sample() -> IdleClocks {
        IdleClocks(
            anyInput: seconds(since: anyInputEventType),
            keyDown: seconds(since: .keyDown),
            mouseClick: seconds(since: .leftMouseDown),
            mouseMoved: seconds(since: .mouseMoved),
            scrollWheel: seconds(since: .scrollWheel)
        )
    }

    // MARK: - Derived "activity texture"
    //
    // The per-type clocks are what make the pet's personality free: the same
    // sample that drives the timer also says *how* the user is working.

    /// Recent typing, within `window` seconds.
    public func isTyping(window: TimeInterval = 5) -> Bool { keyDown <= window }

    /// Recent scrolling with little typing — reading, browsing, doomscrolling.
    public func isScrolling(window: TimeInterval = 5) -> Bool {
        scrollWheel <= window && keyDown > window
    }

    /// Mouse moving but nothing committed — hovering, hunting, thinking.
    public func isDrifting(window: TimeInterval = 5) -> Bool {
        mouseMoved <= window && keyDown > window && mouseClick > window
    }
}
