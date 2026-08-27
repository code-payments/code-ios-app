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
/// the version string never announces anything. Owns the message it shows and
/// the delay that takes it away again, so the footer only has to draw it.
@MainActor
@Observable
final class VersionTapUnlock {

    /// The line to show above the version footer, or `nil` when there is
    /// nothing to say.
    private(set) var message: String?

    private var tapCount: Int = 0

    @ObservationIgnored private var clearTask: Task<Void, Never>?

    /// Taps needed to flip beta access, matching the count this easter egg has
    /// always used.
    private static let tapsToToggle: Int = 10

    /// How many taps out the countdown starts speaking up.
    private static let countdownFrom: Int = 3

    private static let messageDuration: Int = 2000

    // MARK: - Taps -

    /// Registers a tap on the version footer, counting toward the toggle and
    /// updating ``message``.
    ///
    /// - Parameters:
    ///   - isUnlocked: Beta access as it stands, which decides whether the taps
    ///     are counting toward showing the beta rows or hiding them again.
    ///   - toggle: Flips beta access. Called on the tap that completes the count.
    func registerTap(isUnlocked: Bool, toggle: () -> Void) {
        tapCount += 1
        let remaining = Self.tapsToToggle - tapCount

        if remaining <= 0 {
            tapCount = 0
            toggle()
            show(isUnlocked ? "Beta features are hidden again" : "You are now a developer!")
        } else if remaining <= Self.countdownFrom {
            let steps = remaining == 1 ? "step" : "steps"
            show(
                isUnlocked
                    ? "You are now \(remaining) \(steps) away from hiding beta features"
                    : "You are now \(remaining) \(steps) away from being a developer"
            )
        }
    }

    // MARK: - Message -

    private func show(_ message: String) {
        self.message = message
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.delay(milliseconds: Self.messageDuration)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}
