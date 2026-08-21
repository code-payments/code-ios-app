//
//  TipCardPresentation.swift
//  Flipcash
//

import UIKit
import Observation

/// Whether the You tab's tip card is expanded to fill the screen.
///
/// The card expands inside the page rather than as a presented screen, so the
/// tab bar's usual "hide while a stack is non-empty" rule cannot see it; the You
/// tab reports it here for `HomeTabView` to read. Owns the screen-brightness
/// boost too, since an expanded card is a code someone is about to scan.
@MainActor
@Observable
final class TipCardPresentation {

    private(set) var isExpanded = false

    /// The brightness to put back on collapse — set only when we raised it.
    @ObservationIgnored private var previousBrightness: CGFloat?

    /// Below this a code is hard to scan, so the screen is raised to `boosted`.
    private static let minimumScanBrightness: CGFloat = 0.4
    private static let boostedBrightness: CGFloat = 0.6

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        boostBrightness()
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        restoreBrightness()
    }

    // MARK: - Brightness -

    private var screen: UIScreen? {
        UIApplication.shared.firstWindowScene?.screen
    }

    private func boostBrightness() {
        guard let screen, screen.brightness < Self.minimumScanBrightness else { return }
        if previousBrightness == nil {
            previousBrightness = screen.brightness
        }
        screen.brightness = Self.boostedBrightness
    }

    private func restoreBrightness() {
        guard let previousBrightness, let screen else { return }
        screen.brightness = previousBrightness
        self.previousBrightness = nil
    }
}
