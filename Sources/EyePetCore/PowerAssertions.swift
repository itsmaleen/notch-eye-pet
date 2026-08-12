import Foundation
import IOKit.pwr_mgt

/// Reads IOKit power assertions to tell *passive viewing* apart from *absence*.
///
/// This is the fix for the classic break-timer failure: the user is watching a video
/// or reading, so there is no input for ten minutes, and a naive idle timer concludes
/// they left — during exactly the screen time that matters most.
///
/// Media players take a `PreventUserIdleDisplaySleep` assertion while playing.
/// WebKit's is named `com.apple.WebCore: HTMLMediaElement playback`; native players
/// show `CoreMedia Playback` variants. Cross-check any change here against
/// `pmset -g assertions`, which is the same data in human-readable form.
public enum PowerAssertions {
    /// Assertion type that means "something wants the display to stay awake".
    /// `CFSTR` macros do not import into Swift, so the type names are literals.
    public static let preventUserIdleDisplaySleep = "PreventUserIdleDisplaySleep"
    public static let preventUserIdleSystemSleep = "PreventUserIdleSystemSleep"
    /// Legacy equivalent still used by some apps.
    public static let preventDisplaySleep = "PreventDisplaySleep"

    public struct Assertion: Sendable, Equatable {
        public let type: String
        public let name: String
        public let pid: Int32

        public init(type: String, name: String, pid: Int32) {
            self.type = type
            self.name = name
            self.pid = pid
        }

        /// Heuristic: does this assertion look like media playback rather than, say,
        /// `caffeinate` or a long build? Used only to soften the nudge, never to skip
        /// a break — a false negative here just means a slightly firmer prompt.
        public var looksLikeMediaPlayback: Bool {
            let haystack = name.lowercased()
            return ["playback", "htmlmediaelement", "coremedia", "video", "audio", "movie"]
                .contains { haystack.contains($0) }
        }
    }

    /// True if anything is currently holding the display awake.
    ///
    /// Reads the aggregated status dictionary, which maps assertion type -> 0/1.
    public static func isDisplaySleepPrevented() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Int]
        else { return false }

        return [preventUserIdleDisplaySleep, preventDisplaySleep]
            .contains { (dict[$0] ?? 0) > 0 }
    }

    /// Every currently-held assertion, with its owning pid and human-readable name.
    ///
    /// `IOPMCopyAssertionsByProcess` returns pid -> [assertion dictionaries].
    public static func current() -> [Assertion] {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let dict = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }

        return dict.flatMap { pid, entries in
            entries.compactMap { entry -> Assertion? in
                guard let type = entry[kIOPMAssertionTypeKey] as? String else { return nil }
                let name = entry[kIOPMAssertionNameKey] as? String ?? ""
                return Assertion(type: type, name: name, pid: pid.int32Value)
            }
        }
    }

    /// Display-awake assertions only — the ones that mean "eyes may still be on the screen".
    public static func displayAwakeAssertions() -> [Assertion] {
        current().filter {
            $0.type == preventUserIdleDisplaySleep || $0.type == preventDisplaySleep
        }
    }
}
