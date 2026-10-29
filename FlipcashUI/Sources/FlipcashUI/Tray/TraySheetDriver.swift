//
//  TraySheetDriver.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit

/// The UIKit seam that keeps a tray's sheet invisible and at least as tall as the tray's card.
///
/// The tray draws its own card in SwiftUI, so the card, its content and its actions resize on one
/// clock. The system sheet is only the invisible container that presents, drags and dims: the
/// driver reaches its `UISheetPresentationController`, gives it a custom detent that reads a
/// height the driver controls, and clears the detent's background effect so the system glass
/// never shows. The sheet grows at once when the card grows and shrinks once the card's resize has
/// settled, so its edge is never on screen.
///
/// Measured (simulator, 3 runs each): a sheet resized on its own curve, on a UIKit spring or on a
/// SwiftUI animation bridged to UIKit leaves a CTA inside the content 6–18 pt off during resizes,
/// because Core Animation and SwiftUI start the two motions on different frames. A card drawn in
/// SwiftUI inside an invisible sheet holds the CTA within 0.02 pt.
@MainActor
final class TraySheetDriver {

    private static let detentIdentifier = UISheetPresentationController.Detent.Identifier("com.flipcash.tray")

    private weak var sheet: UISheetPresentationController?
    private var cardHeight: CGFloat = 0
    private var dimsBackground = true
    /// The bottom safe area the system gives the floating sheet's content, read once before the
    /// driver cancels it, since it reads high while the cancellation lands.
    private var systemBottomInset: CGFloat = 0

    /// The height the detent shows: the card's, or the taller height a shrinking card is leaving.
    private var shownHeight: CGFloat = 0
    private var pendingShrink: DispatchWorkItem?

    /// Told the tallest the card can be whenever the sheet's limit changes.
    var onMaximumCardHeight: ((CGFloat) -> Void)?
    private var maximumCardHeight: CGFloat = 0

    /// Finds the sheet presenting `controller` and takes its detents over once the card has a
    /// height.
    func attach(from controller: UIViewController) {
        guard sheet == nil, let found = Self.sheet(presenting: controller) else { return }
        sheet = found
        reclaimIfNeeded()
    }

    /// Sizes the sheet for a card `cardHeight` tall: taller at once, shorter once the card's resize
    /// spring has settled.
    func update(cardHeight: CGFloat, dimsBackground: Bool) {
        let restyled = dimsBackground != self.dimsBackground
        let previousHeight = self.cardHeight
        self.cardHeight = cardHeight
        self.dimsBackground = dimsBackground

        guard let sheet, cardHeight > 0 else { return }
        if !owns(sheet) || restyled {
            takeOver(sheet)
            sheet.invalidateDetents()
        }
        // Should SwiftUI configure the sheet again later in this pass and put its own detent back,
        // the check after the pass takes it over again.
        DispatchQueue.main.async { [weak self] in self?.reclaimIfNeeded() }
        if cardHeight != previousHeight {
            resize(to: cardHeight, from: previousHeight)
        }
    }

    /// Takes the sheet's detents back if something else replaced them.
    func reclaimIfNeeded() {
        guard let sheet, cardHeight > 0, !owns(sheet) else { return }
        if shownHeight == 0 { shownHeight = cardHeight }
        takeOver(sheet)
        sheet.invalidateDetents()
    }

    // MARK: - Resizing

    /// Grows the sheet in this pass and shrinks it once the card's spring has settled. The sheet's
    /// edge never animates: it is invisible, and the card moves on its own spring inside it.
    private func resize(to height: CGFloat, from previousHeight: CGFloat) {
        pendingShrink?.cancel()
        pendingShrink = nil
        let isOnScreen = sheet?.presentedViewController.viewIfLoaded?.window != nil
        guard isOnScreen, previousHeight > 0 else {
            show(height)
            return
        }
        let spring = TrayMotion.resize.spring
        // A bouncy resize carries a growing card past its new height, and the sheet clips the card.
        let growth = max(0, height - previousHeight)
        let overshoot = growth > 0 && spring.bounce > 0 ? growth * Self.overshoot(of: spring) : 0
        let tallest = height + overshoot.rounded(.up)
        if tallest > shownHeight {
            show(tallest)
        }
        guard shownHeight > height else { return }
        let shrink = DispatchWorkItem { [weak self] in self?.show(height) }
        pendingShrink = shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + spring.settlingDuration, execute: shrink)
    }

    /// How far past its target `spring` carries a move, as a share of the move.
    private static func overshoot(of spring: Spring) -> CGFloat {
        let duration = spring.settlingDuration
        let peak = (1...60).reduce(1.0) { peak, sample in
            max(peak, spring.value(target: 1.0, time: duration * Double(sample) / 60))
        }
        return peak - 1
    }

    private func show(_ height: CGFloat) {
        guard let sheet, height != shownHeight else { return }
        shownHeight = height
        sheet.invalidateDetents()
        sheet.containerView?.layoutIfNeeded()
    }

    // MARK: - Detent

    private func takeOver(_ sheet: UISheetPresentationController) {
        let detent = UISheetPresentationController.Detent.custom(identifier: Self.detentIdentifier) { [weak self] context in
            MainActor.assumeIsolated { self?.detentHeight(in: context) }
        }
        // A translucent `.presentationBackground`, clear included, leaves the floating sheet's
        // Liquid Glass in place, and the sheet's own `backgroundEffect` is reset when SwiftUI
        // configures it; the detent's holds.
        if #available(iOS 26.1, *) {
            detent.backgroundEffect = UIColorEffect(color: .clear)
        }
        sheet.detents = [detent]
        sheet.selectedDetentIdentifier = Self.detentIdentifier
        sheet.largestUndimmedDetentIdentifier = dimsBackground ? nil : Self.detentIdentifier
        sheet.prefersGrabberVisible = false
        cancelBottomInset(sheet)
    }

    private func owns(_ sheet: UISheetPresentationController) -> Bool {
        sheet.detents.count == 1 && sheet.detents.first?.identifier == Self.detentIdentifier
    }

    /// A detent leaves out the sheet's bottom safe area, which the card covers on iOS 26; on
    /// iOS 18 the card's content stays above the home indicator, so the detent is the card's height.
    private func detentHeight(in context: UISheetPresentationControllerDetentResolutionContext) -> CGFloat? {
        reportMaximumCardHeight(context.maximumDetentValue + systemBottomInset)
        let height = shownHeight > 0 ? shownHeight : cardHeight
        guard height > 0 else { return nil }
        return min(height - systemBottomInset, context.maximumDetentValue)
    }

    /// Passes on the tallest card the detent can show, after the layout pass that resolved it.
    private func reportMaximumCardHeight(_ height: CGFloat) {
        guard height > 0, height != maximumCardHeight else { return }
        maximumCardHeight = height
        DispatchQueue.main.async { [weak self] in self?.onMaximumCardHeight?(height) }
    }

    /// Cancels the floating sheet's bottom safe area, which nothing covers, so the card's bottom
    /// edge sits on the sheet's.
    private func cancelBottomInset(_ sheet: UISheetPresentationController) {
        guard #available(iOS 26, *) else { return }
        let controller = sheet.presentedViewController
        guard controller.isViewLoaded else { return }
        if controller.additionalSafeAreaInsets.bottom == 0 {
            systemBottomInset = controller.view.safeAreaInsets.bottom
        }
        controller.additionalSafeAreaInsets.bottom = -systemBottomInset
    }

    // MARK: - Lookup

    /// The sheet of the presented controller that contains `controller`. Only a controller that is
    /// itself presented counts: `sheetPresentationController` on any other creates a new, unused
    /// sheet on read.
    private static func sheet(presenting controller: UIViewController) -> UISheetPresentationController? {
        var candidate: UIViewController? = controller
        while let current = candidate {
            if isPresented(current) {
                return current.sheetPresentationController
            }
            candidate = current.parent
        }
        var responder: UIResponder? = controller.viewIfLoaded
        while let next = responder?.next {
            if let owner = next as? UIViewController, isPresented(owner) {
                return owner.sheetPresentationController
            }
            responder = next
        }
        return nil
    }

    private static func isPresented(_ controller: UIViewController) -> Bool {
        controller.presentingViewController?.presentedViewController === controller
    }
}

/// Hosts a ``TraySheetDriver`` inside the sheet's content, where it can reach the sheet.
struct TraySheetSeam: UIViewControllerRepresentable {

    let cardHeight: CGFloat
    let dimsBackground: Bool
    /// Told the tallest the card can be in this sheet.
    let onMaximumCardHeight: (CGFloat) -> Void

    func makeUIViewController(context: Context) -> TraySheetSeamController {
        TraySheetSeamController()
    }

    func updateUIViewController(_ controller: TraySheetSeamController, context: Context) {
        controller.driver.onMaximumCardHeight = onMaximumCardHeight
        controller.driver.attach(from: controller)
        controller.driver.update(cardHeight: cardHeight, dimsBackground: dimsBackground)
    }
}

/// An invisible controller that attaches its driver to the sheet once it joins the hierarchy.
final class TraySheetSeamController: UIViewController {

    let driver = TraySheetDriver()

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        driver.attach(from: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        driver.attach(from: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // SwiftUI can configure the sheet once more as the presentation lands.
        driver.reclaimIfNeeded()
    }
}
