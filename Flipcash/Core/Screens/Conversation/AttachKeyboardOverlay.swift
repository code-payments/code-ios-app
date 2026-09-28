//
//  AttachKeyboardOverlay.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import PhotosUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.attach-overlay")

/// What the panel and cards drawn over the keyboard hand back to the screen.
struct AttachOverlayActions {
    var onCash: () -> Void
    var onCamera: () -> Void
    var onPhotos: () -> Void
    var onCameraCapture: (ChatCameraCapture) -> Void
    var onCameraCancel: () -> Void
    var onPhotosAdd: ([PhotosPickerItem], ChatPhotoPreloader<PhotosPickerItem>) -> Void
    var onPhotosBack: () -> Void
    var onAllPhotos: (() -> Void)? = nil
}

/// Draws the attach panel and its cards over the keyboard while the composer keeps focus, as
/// ChatGPT does: in the keyboard's own window when ``KeyboardOverlayHost`` finds it, else over a
/// keyboard-coloured input view swapped in under the field.
///
/// The SwiftUI is hosted in a full-screen container laid over the app's window, so it shares the
/// bar's window coordinates. The container takes touches only on the panel and the card; the keys
/// they leave uncovered and the app beside them keep theirs.
@MainActor
final class AttachKeyboardOverlay {

    private let model: ConversationBarModel
    private let locator: any KeyboardWindowLocating

    /// How the overlay is drawn, while it is.
    private(set) var mode: AttachOverlayMode?

    private weak var screen: ChatScreenViewController?
    private var container: AttachOverlayContainer?
    private var host: UIHostingController<AnyView>?
    private var backdrop: AttachInputBackdrop?
    private var observers: [any NSObjectProtocol] = []

    init(model: ConversationBarModel, locator: any KeyboardWindowLocating = KeyboardOverlayHost()) {
        self.model = model
        self.locator = locator
    }

    /// Plans how `+` opens the panel and, when it goes over the keyboard, puts the overlay up with
    /// `items` as its rows. Returns the mode chosen; ``AttachOverlayMode/dismissKeyboard`` leaves the
    /// caller to take the keyboard down.
    func begin(
        screen: ChatScreenViewController,
        items: [AttachMenuItem],
        composer: ComposerModel,
        actions: AttachOverlayActions
    ) -> AttachOverlayMode {
        if let mode { return mode }
        let plan = AttachOverlayPlan(
            locator: locator,
            keyboardHeight: screen.keyboardOverlap,
            canReplaceInputView: screen.canReplaceComposerInputView
        )
        logger.info("Attach panel opening", metadata: [
            "mode": "\(plan.mode.rawValue)",
            "keyboardHeight": "\(screen.keyboardOverlap)",
            "keyboardWindowFound": "\(plan.keyboardWindow != nil)",
            "canReplaceInputView": "\(screen.canReplaceComposerInputView)",
        ])
        guard plan.mode.drawsOverKeyboard, let appWindow = screen.view.window else { return .dismissKeyboard }

        self.screen = screen
        // Before the switch: swapping the input view in announces the keyboard showing again, which
        // must not read as the keyboard taking a card's place.
        model.attachCard.closesOnKeyboardShow = false
        let container = makeContainer(appWindow: appWindow, composer: composer, actions: actions)
        switch plan.mode {
        case .keyboardWindow:
            guard let window = plan.keyboardWindow else { return refuse() }
            install(container, in: window)
        case .inputView:
            let backdrop = AttachInputBackdrop(height: screen.keyboardOverlap)
            backdrop.onWindow = { [weak self] window in
                guard let self, let container = self.container else { return }
                self.install(container, in: window)
            }
            guard screen.setComposerInputView(backdrop) else {
                logger.info("Attach panel input view refused", metadata: [:])
                return refuse()
            }
            self.backdrop = backdrop
        case .dismissKeyboard:
            return .dismissKeyboard
        }

        mode = plan.mode
        model.overKeyboard.activate(items: items)
        // A tap on the transcript reaches the app's window, not the overlay, and would lower the
        // keyboard; while the menu is up it only closes the menu.
        screen.setTranscriptShield(
            isActive: { [weak self] in self?.container?.dismissesOnOutsideTouch() ?? false },
            onTap: { [weak self] in self?.container?.onOutsideTouch() }
        )
        observe()
        return plan.mode
    }

    /// Undoes a begin that can't draw over the keyboard after all, leaving the bar to draw the panel.
    private func refuse() -> AttachOverlayMode {
        model.attachCard.closesOnKeyboardShow = true
        container = nil
        host = nil
        return .dismissKeyboard
    }

    /// Takes the overlay down once nothing is left in it, putting the system keyboard back under the
    /// field if an input view stood in for it.
    func end() {
        guard mode != nil else { return }
        mode = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        screen?.setTranscriptShield(isActive: { false }, onTap: nil)
        container?.isEnding = true
        container?.removeFromSuperview()
        container = nil
        host = nil
        if backdrop != nil {
            screen?.setComposerInputView(nil)
            backdrop = nil
        }
        model.attachCard.closesOnKeyboardShow = true
        model.overKeyboard.deactivate()
    }

    /// Takes the panel and card down at once: the keyboard went, or the app left the foreground.
    func abort() {
        guard mode != nil else { return }
        logger.info("Attach overlay aborted", metadata: [:])
        model.resetAttach()
        end()
    }

    /// Hands the photo card to the bar, with the keyboard down and the full picker opening: a sheet
    /// can't be presented from the keyboard's window.
    func handOffToBar() {
        guard mode != nil else { return }
        model.overKeyboard.opensLibraryInBar = true
        end()
        screen?.dismissKeyboard()
    }

    private func makeContainer(
        appWindow: UIWindow,
        composer: ComposerModel,
        actions: AttachOverlayActions
    ) -> AttachOverlayContainer {
        let container = AttachOverlayContainer()
        container.appWindow = appWindow
        // The keyboard's window does not carry the app's appearance.
        container.overrideUserInterfaceStyle = appWindow.traitCollection.userInterfaceStyle
        container.onWindowLost = { [weak self] in self?.reattach() }
        container.dismissesOnOutsideTouch = { [weak self] in
            guard let model = self?.model else { return false }
            return model.attachPanel.isOpen && !model.attachCard.isOpen
        }
        container.onOutsideTouch = { [weak self] in
            self?.model.attachPanel.animate { $0.dismiss() }
        }

        let root = AttachOverlayRoot(
            model: model,
            composer: composer,
            actions: actions,
            report: { [weak container] region, rect in container?.hitRects[region] = rect },
            onFinished: { [weak self] in self?.end() },
            onAbort: { [weak self] in self?.abort() }
        )
        let host = UIHostingController(rootView: AnyView(root))
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        host.view.frame = container.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(host.view)
        self.host = host
        self.container = container
        return container
    }

    private func install(_ container: AttachOverlayContainer, in window: UIWindow) {
        guard let appWindow = container.appWindow else { return }
        // Through the screen: the keyboard's window is in another scene, and converting straight
        // from the app's window yields an infinite rect.
        let onScreen = appWindow.convert(appWindow.bounds, to: appWindow.screen.coordinateSpace)
        let frame = window.convert(onScreen, from: window.screen.coordinateSpace)
        container.frame = frame.origin.x.isFinite && frame.origin.y.isFinite ? frame : window.bounds
        if container.superview === window {
            window.bringSubviewToFront(container)
        } else {
            window.addSubview(container)
        }
    }

    /// Puts the overlay back on top of a keyboard whose view tree was rebuilt, or takes it down when
    /// the keyboard's window has gone.
    private func reattach() {
        // A turn later, so UIKit has finished swapping the tree out.
        DispatchQueue.main.async { [weak self] in
            guard let self, let mode = self.mode, let container = self.container, !container.isEnding else { return }
            let window: UIWindow? = switch mode {
            case .keyboardWindow:   self.locator.keyboardWindow()
            case .inputView:        self.backdrop?.window
            case .dismissKeyboard:  nil
            }
            guard let window else {
                self.abort()
                return
            }
            self.install(container, in: window)
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        let refresh: [Notification.Name] = [UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidChangeFrameNotification]
        for name in refresh {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reattach() }
            })
        }
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.abort() }
        })
        // The input view swap announces the keyboard going and coming, so only the keyboard's own
        // window takes a hide as the keyboard leaving. Focus loss covers the swap.
        observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.mode == .keyboardWindow else { return }
                self?.abort()
            }
        })
    }
}

/// The parts of the overlay that take touches.
enum AttachOverlayRegion: Hashable {
    case panel
    case card
}

/// A full-screen layer over the keyboard that takes touches only on the panel and the card.
final class AttachOverlayContainer: UIView {

    /// The app window the overlay is laid over, whose coordinates the SwiftUI inside uses.
    weak var appWindow: UIWindow?
    /// The panel's and card's frames, in this view's coordinates.
    var hitRects: [AttachOverlayRegion: CGRect] = [:]
    /// Set as the overlay is taken down, so leaving the window is not taken for a rebuilt keyboard.
    var isEnding = false
    /// Fired when the keyboard's view tree is rebuilt out from under the overlay.
    var onWindowLost: () -> Void = {}
    /// Whether a touch outside the panel and card is taken to dismiss, instead of passing through.
    var dismissesOnOutsideTouch: () -> Bool = { false }
    /// Fired by a touch outside the panel and card while `dismissesOnOutsideTouch` holds.
    var onOutsideTouch: () -> Void = {}

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard hitRects.values.contains(where: { $0.contains(point) }) else {
            // The touch is swallowed, not typed: it only closes the menu, as with the keyboard down.
            return dismissesOnOutsideTouch() ? self : nil
        }
        return super.hitTest(point, with: event)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onOutsideTouch()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil, !isEnding {
            onWindowLost()
        }
    }
}

/// The input view that stands in for the keyboard when its window can't be reached: the keyboard's
/// own backdrop at the keyboard's height, so the composer stays where it was.
final class AttachInputBackdrop: UIInputView {

    /// Fired with the window the backdrop lands in, which the overlay is laid over.
    var onWindow: (UIWindow) -> Void = { _ in }

    init(height: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: height), inputViewStyle: .keyboard)
        allowsSelfSizing = false
        autoresizingMask = [.flexibleWidth]
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            onWindow(window)
        }
    }
}

/// The overlay's content: the attach surface in window coordinates, the menu straddling the
/// composer's bottom edge and the cards standing on the screen's bottom over the keys.
private struct AttachOverlayRoot: View {

    let model: ConversationBarModel
    let composer: ComposerModel
    let actions: AttachOverlayActions
    let report: (AttachOverlayRegion, CGRect?) -> Void
    let onFinished: () -> Void
    let onAbort: () -> Void

    @State private var bounds: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if model.attachSurfaceIsMounted {
                AttachSurface(
                    model: model,
                    items: model.overKeyboard.items,
                    plus: model.overKeyboard.plusFrame,
                    card: AttachOverlayLayout.cardFrame(in: CGRect(origin: .zero, size: bounds), height: model.attachCard.height),
                    landing: model.attachCard.landingChipFrame,
                    menuPlacement: .straddlesPlus,
                    selectionLimit: AttachMenuItem.photosSelectionLimit(attachedCount: composer.chips.count),
                    actions: actions,
                    report: report
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { bounds = $0 }
        // Everything has gone: the overlay comes down and the bar takes over again.
        .onChange(of: model.attachSurfaceIsMounted) { _, isMounted in
            if !isMounted {
                onFinished()
            }
        }
        // The field losing focus takes the keyboard, and with it what was drawn over it.
        .onChange(of: model.isComposing) { _, isComposing in
            if !isComposing {
                onAbort()
            }
        }
    }
}
