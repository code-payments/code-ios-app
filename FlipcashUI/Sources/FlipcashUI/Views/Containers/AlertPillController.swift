//
//  AlertPillController.swift
//  FlipcashUI
//

import SwiftUI
import UIKit
import Observation

/// What an alert pill says. Mirrors the `Alert/Reaction pill` component: a top row, a title and one
/// subtitle line, and a trailing accessory.
public struct AlertPillContent: Equatable, Sendable {

    /// The trailing accessory of the expanded pill, and what the compact pill keeps of it.
    public enum Trailing: Equatable, Sendable {
        /// One emoji, large.
        case emoji(String)
        /// Up to three emoji, for several reactors on one message.
        case emojis([String])
        /// A boost's green amount, already formatted.
        case amount(String)
    }

    /// One reactor's avatar: their photo when there is one, else an initial on a colour seeded by `seed`.
    public struct Avatar: Equatable, Sendable {
        public let initial: String
        public let seed: Int
        public let imageData: Data?

        public init(initial: String, seed: Int, imageData: Data? = nil) {
            self.initial = initial
            self.seed = seed
            self.imageData = imageData
        }
    }

    public let topRow: String
    public let title: String
    public let subtitle: String
    public let trailing: Trailing
    /// The reactors, newest last. More than one draws the overlapping stack.
    public let avatars: [Avatar]

    public init(topRow: String, title: String, subtitle: String, trailing: Trailing, avatars: [Avatar]) {
        self.topRow = topRow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.avatars = avatars
    }
}

/// The pill on screen: the top-anchored slot of the app's toast host.
///
/// The owner decides what shows and in what order; this holds the one pill being drawn. Calling
/// ``present(_:hold:haptic:onTap:)`` while a pill is up swaps its content in place and restarts its hold.
@MainActor
@Observable
public final class AlertPillController {

    /// The haptic that goes with a pill.
    public enum Haptic: Sendable {
        /// A reaction.
        case light
        /// A boost.
        case success
    }

    /// A pill being shown.
    public struct Presented: Identifiable {
        public let id: UUID
        public fileprivate(set) var content: AlertPillContent
        public fileprivate(set) var hold: Duration
        /// Bumped by every in-place swap, so the host restarts the hold without replaying the entrance.
        public fileprivate(set) var revision: Int
        fileprivate(set) var haptic: Haptic
        fileprivate(set) var onTap: () -> Void
    }

    /// The pill on screen, or `nil` when none is.
    public private(set) var current: Presented?
    /// Where the pill is on screen, so its window can pass every other touch through.
    @ObservationIgnored var pillFrame: CGRect = .null

    /// Called once with the pill's id when it has finished closing, by timeout, tap or swipe, or when
    /// it was dropped; the owner shows the next one from here.
    @ObservationIgnored public var onFinished: ((UUID) -> Void)?

    @ObservationIgnored private let impact = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private let notification = UINotificationFeedbackGenerator()
    @ObservationIgnored private let selection = UISelectionFeedbackGenerator()

    public init() {}

    /// Shows `content` for `hold`, or swaps it into the pill already up. `onTap` runs when the user taps it.
    @discardableResult
    public func present(
        _ content: AlertPillContent,
        hold: Duration,
        haptic: Haptic,
        onTap: @escaping () -> Void
    ) -> UUID {
        // Warmed here and played by the banner once it has landed, so the tap lines up with what you see.
        impact.prepare()
        notification.prepare()
        selection.prepare()
        AccessibilityNotification.Announcement("\(content.title). \(content.subtitle)").post()
        if var presented = current {
            presented.content = content
            presented.hold = hold
            presented.revision += 1
            presented.haptic = haptic
            presented.onTap = onTap
            current = presented
            return presented.id
        }
        let presented = Presented(id: UUID(), content: content, hold: hold, revision: 0, haptic: haptic, onTap: onTap)
        current = presented
        return presented.id
    }

    /// Plays the haptic for the banner as it lands. A banner updated in place gets a lighter tick,
    /// unless the update turned it into a boost.
    func playHaptic(_ haptic: Haptic, isUpdate: Bool) {
        switch (haptic, isUpdate) {
        case (.success, _): notification.notificationOccurred(.success)
        case (.light, false): impact.impactOccurred(intensity: 0.75)
        case (.light, true): selection.selectionChanged()
        }
    }

    /// Removes the pill `id` once the host has played its close, if it is still the one showing.
    func finish(_ id: UUID) {
        guard current?.id == id else { return }
        current = nil
        onFinished?(id)
    }

    /// Drops the pill without a close, for a sign-out or a sheet opening over the host.
    public func cancel() {
        guard let id = current?.id else { return }
        finish(id)
    }
}
