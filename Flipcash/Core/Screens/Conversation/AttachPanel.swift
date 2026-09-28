//
//  AttachPanel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import Observation
import FlipcashUI

/// Whether the attach menu's floating panel is up over the composer row, and how long it holds room
/// above the bar.
///
/// The panel floats over the transcript, outside the bar's own frame, so the screen has to let the
/// bar draw and take touches above itself for as long as the panel is on screen — which outlasts
/// ``isOpen`` by the length of the exit. ``holdsOverflow`` is that longer span.
@MainActor
@Observable
final class AttachPanel {

    /// Whether the panel is up.
    private(set) var isOpen = false

    /// Whether the bar needs room above itself: from opening until the exit has finished.
    private(set) var holdsOverflow = false

    /// Opens the panel when closed and collapses it when open, as `+` does.
    func toggle() {
        if isOpen {
            dismiss()
        } else {
            open()
        }
    }

    /// Puts the panel up: out of `+`, or back out of a card.
    func open() {
        guard !isOpen else { return }
        isOpen = true
        holdsOverflow = true
    }

    /// Takes the panel down: into `+`, or into the card it expands into.
    func dismiss() {
        guard isOpen else { return }
        isOpen = false
    }

    /// Runs `change` on the panel's spring, and releases the room above the bar once the motion it
    /// started has logically finished.
    func animate(_ change: (AttachPanel) -> Void) {
        withAnimation(ChatMotion.attachPanel.animation, completionCriteria: .logicallyComplete) {
            change(self)
        } completion: { [weak self] in
            self?.exitDidFinish()
        }
    }

    /// Releases the room above the bar once the exit's animation has run, unless the panel came back
    /// in the meantime.
    func exitDidFinish() {
        guard !isOpen else { return }
        holdsOverflow = false
    }
}

/// How the attach flow moves: the one surface springing between `+`, the panel, a card, and a chip,
/// or — under Reduce Motion — standing still at each while its content cross-fades.
nonisolated enum AttachMotion: Equatable {
    case morph
    case crossFade

    init(reduceMotion: Bool) {
        self = reduceMotion ? .crossFade : .morph
    }

    /// Whether the surface's frame and corner radius animate, rather than jump.
    var animatesGeometry: Bool {
        switch self {
        case .morph:        true
        case .crossFade:    false
        }
    }

    /// A chip's scale as it enters the strip and leaves it.
    var chipEnterScale: CGFloat {
        switch self {
        case .morph:        ChatMotion.composerChipEnterScale
        case .crossFade:    1
        }
    }

    /// A chip's transition in and out of the strip, for a chip that is or isn't the one the surface is
    /// landing on — that one arrives hidden, where it lies.
    func chipTransition(isLanding: Bool) -> AnyTransition {
        guard !isLanding else { return .identity }
        return .scale(scale: chipEnterScale).combined(with: .opacity)
    }

    /// The strip's transition as its first chip arrives and its last one leaves: grown from the
    /// leading edge, where that chip sits.
    func stripTransition(isLanding: Bool) -> AnyTransition {
        guard !isLanding else { return .identity }
        return .scale(scale: chipEnterScale, anchor: .leading).combined(with: .opacity)
    }
}

extension View {
    /// Fades this view under the camera or photo card: out before the card has grown over it, and back
    /// in once the card has shrunk away. Scoped, so nothing else inside rides these curves.
    func hiddenUnderAttachCard(_ hidden: Bool) -> some View {
        animation(hidden ? ChatMotion.attachContentOut : ChatMotion.attachContentIn) {
            $0.opacity(hidden ? 0 : 1)
        }
    }
}
