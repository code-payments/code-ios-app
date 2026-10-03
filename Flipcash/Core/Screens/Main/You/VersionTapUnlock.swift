//
//  VersionTapUnlock.swift
//  Flipcash
//

import Observation
import FlipcashCore

/// The version footer's easter egg: ten taps toggle beta access, and the last
/// few taps say so out loud.
///
/// The counter is silent until the unlock is within reach, so a stray tap on
/// the version string never announces anything.
@MainActor
@Observable
final class VersionTapUnlock {

    private var tapCount: Int = 0

    /// Taps needed to flip beta access, matching the count this easter egg has
    /// always used.
    private static let tapsToToggle: Int = 10

    /// How many taps out the countdown starts speaking up.
    private static let countdownFrom: Int = 3

    // MARK: - Taps -

    /// Registers a tap on the version footer, counting toward the toggle, and
    /// returns the line to show for it, or `nil` when there is nothing to say.
    ///
    /// - Parameters:
    ///   - isUnlocked: Beta access as it stands, which decides whether the taps
    ///     are counting toward showing the beta rows or hiding them again.
    ///   - toggle: Flips beta access. Called on the tap that completes the count.
    func registerTap(isUnlocked: Bool, toggle: () -> Void) -> String? {
        tapCount += 1
        let remaining = Self.tapsToToggle - tapCount

        if remaining <= 0 {
            tapCount = 0
            toggle()
            return isUnlocked ? "Beta features are hidden again" : "You are now a developer!"
        } else if remaining <= Self.countdownFrom {
            let steps = remaining == 1 ? "step" : "steps"
            return isUnlocked
                ? "You are now \(remaining) \(steps) away from hiding beta features"
                : "You are now \(remaining) \(steps) away from being a developer"
        }
        return nil
    }
}
