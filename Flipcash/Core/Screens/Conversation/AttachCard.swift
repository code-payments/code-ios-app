//
//  AttachCard.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import Observation
import FlipcashUI

/// The camera or photo card the attach menu expands into: a fixed share of the screen, standing on
/// the composer's bottom edge over the composer row and the transcript.
///
/// The card floats over the transcript, outside the bar's own frame, so the screen has to let the
/// bar draw above itself for as long as the card is on screen — which outlasts ``isOpen`` by the
/// length of the exit. ``holdsOverflow`` is that longer span.
@MainActor
@Observable
final class AttachCard {

    /// What the attach menu can expand into.
    nonisolated enum Content: Equatable {
        case camera
        case photos
    }

    /// The share of the screen's height the card takes, measured off the reference recording.
    nonisolated static let screenHeightFraction: CGFloat = 0.58

    /// The card's height before a screen has been measured.
    nonisolated static let fallbackHeight: CGFloat = 480

    /// Returns the card's height on a screen `screenHeight` points tall.
    nonisolated static func height(forScreenHeight screenHeight: CGFloat) -> CGFloat {
        guard screenHeight > 0 else { return fallbackHeight }
        return (screenHeight * screenHeightFraction).rounded()
    }

    /// What is up, if anything.
    private(set) var content: Content?

    /// Whether a card is up.
    var isOpen: Bool { content != nil }

    /// The card's height, fixed when it opens.
    private(set) var height: CGFloat = fallbackHeight

    /// Whether the bar needs room above itself: from opening until the exit has finished.
    private(set) var holdsOverflow = false

    /// The chip the last capture or added photo was staged as, held hidden in the strip until the
    /// surface has shrunk onto it.
    private(set) var landingChipID: ComposerChip.ID?

    /// That chip's frame in window coordinates, once the bar has laid it out.
    private(set) var landingChipFrame: CGRect?
    /// The photo the card is shrinking into the chip, drawn by the surface for the whole landing.
    private(set) var landingImage: UIImage?

    /// Whether the keyboard coming up takes the card down. Off while the card is drawn over the
    /// keyboard, where the keyboard never left, and an input view swap announces it again.
    @ObservationIgnored var closesOnKeyboardShow = true

    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let isLocal = notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool ?? true
            MainActor.assumeIsolated {
                guard isLocal else { return }
                self?.keyboardWillShow()
            }
        }
    }

    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Sizes the card for a screen `screenHeight` points tall ahead of opening it, so its content can
    /// be laid out at its final size while the panel is still up.
    func measure(screenHeight: CGFloat) {
        guard content == nil else { return }
        height = Self.height(forScreenHeight: screenHeight)
    }

    /// Puts `content` up on a screen `screenHeight` points tall, unless a card is already up.
    func open(_ content: Content, screenHeight: CGFloat) {
        guard self.content == nil else { return }
        height = Self.height(forScreenHeight: screenHeight)
        self.content = content
        holdsOverflow = true
    }

    /// Takes the card down, leaving the room above the bar until ``exitDidFinish()``.
    func close() {
        guard content != nil else { return }
        content = nil
    }

    /// Marks `chipID` as the chip the card will shrink onto, keeping the card up until the bar has
    /// laid that chip out.
    func beginLanding(on chipID: ComposerChip.ID, image: UIImage? = nil) {
        landingChipID = chipID
        landingChipFrame = nil
        landingImage = image
    }

    /// Records where the landing chip was laid out. Returns whether the card is still up and can now
    /// shrink onto it.
    @discardableResult
    func landingChipDidLayout(_ frame: CGRect) -> Bool {
        guard landingChipID != nil, frame.width > 0 else { return false }
        landingChipFrame = frame
        return content != nil
    }

    /// Ends the landing once the surface has shrunk onto the chip: without animation, so the chip
    /// takes the surface's place in one frame.
    func endLanding() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            landingChipID = nil
            landingChipFrame = nil
            landingImage = nil
        }
    }

    /// Releases the room above the bar once the exit's animation has run, unless a card came back up
    /// in the meantime.
    func exitDidFinish() {
        guard content == nil else { return }
        holdsOverflow = false
    }

    /// Runs `change` on the card's curve, and calls ``exitDidFinish()`` once the motion it started has
    /// logically finished. `then` runs after that, for whatever else the motion moved.
    func animate(_ change: () -> Void, then: @escaping () -> Void = {}) {
        withAnimation(ChatMotion.attachCard.animation, completionCriteria: .logicallyComplete) {
            change()
        } completion: { [weak self] in
            self?.exitDidFinish()
            then()
        }
    }

    /// The keyboard is taking the screen back from a card still up: it goes at once, with nothing to
    /// animate out. A card landing on its chip — Add raises the keyboard as it starts — or already
    /// leaving finishes on its own.
    func keyboardWillShow() {
        guard closesOnKeyboardShow, landingChipID == nil, content != nil else { return }
        close()
        exitDidFinish()
    }
}
