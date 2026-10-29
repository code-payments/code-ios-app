//
//  ChatMediaViewerController.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import Observation
import FlipcashCore
import Kingfisher

/// What the transcript hands its owner when a photo is tapped: the photo to show and the view it
/// zooms out of.
public struct ChatMediaViewerRequest {

    /// The tapped row's stable id.
    public let messageID: String
    /// The photo's blob, which keys its download in the image cache.
    public let blobID: BlobID?
    /// The staged image of a send this device has not confirmed yet, drawn instead of downloading.
    public let localImage: UIImage?
    /// Where the photo downloads from, or nil for a pending send.
    public let remote: ChatMediaLocation?
    /// Whatever the row drew when it was tapped, shown while the full photo loads.
    public let placeholder: UIImage?
    /// The on-screen view the photo zooms out of and back into, looked up on each use because the
    /// row's cell can be recycled while the viewer is up.
    public let sourceView: () -> UIView?
    /// Whether the row takes reactions, by the same rule the transcript uses.
    public let canReact: Bool
    /// Whether the row's context menu offers Reply, so the viewer does too.
    public let canReply: Bool
    /// Whether the row's context menu offers Forward, so the viewer does too.
    public let canForward: Bool

    /// Nil when the row may not open: not a photo, BlurHash-only (see
    /// ``ChatMediaCell/isBlurhashOnly(_:canReact:)``), a failed send whose tap is the retry, or a
    /// photo with neither a staged image nor a resolved URL yet.
    public init?(
        message: ChatMessage,
        localImage: UIImage?,
        remote: ChatMediaLocation?,
        placeholder: UIImage?,
        sourceView: @escaping () -> UIView?
    ) {
        guard case .media(let media) = message.content,
              !ChatMediaCell.isBlurhashOnly(media, canReact: message.canReact),
              !message.isFailed,
              localImage != nil || remote != nil else { return nil }
        self.messageID = message.id
        self.blobID = media.blobID
        self.localImage = localImage
        self.remote = remote
        self.placeholder = placeholder
        self.sourceView = sourceView
        self.canReact = message.canReact
        self.canReply = message.actions.contains(.reply)
        self.canForward = message.actions.contains(.forward)
    }
}

/// A full-screen photo, zoomed in from the tapped transcript row: pinch or double-tap to zoom, swipe
/// down or close to put it back. It opens with no buttons; a tap shows or hides them. The buttons react,
/// reply, save to Photos and forward, with save waiting for the photo itself to load.
public final class ChatMediaViewerController: UIViewController, UIScrollViewDelegate {

    private static let maximumZoomScale: CGFloat = 4
    private static let doubleTapZoomScale: CGFloat = 2.5

    private let request: ChatMediaViewerRequest
    private let onReply: () -> Void
    private let onForward: () -> Void
    private let onSave: (UIImage, Data?) async throws -> Void
    /// The photo's bytes as sent, read at save time; nil falls back to the drawn image.
    var originalData: () -> Data?
    private let onReact: (String) -> Void
    private let onMoreReactions: () -> Void
    private let reactionEntries: () -> [ReactionStrip.Entry]
    /// The user's own reaction emoji the React button currently shows, in strip order.
    private var ownReactionEmoji: [String] = []
    /// What the React button's chip stack currently draws; empty while it shows the face icon.
    private(set) var reactChips: [String] = []

    let scrollView = UIScrollView()
    let imageView = UIImageView()
    let closeButton = UIButton(configuration: .plain())
    let reactButton = UIButton(configuration: .plain())
    let replyButton = UIButton(configuration: .plain())
    let saveButton = UIButton(configuration: .plain())
    let forwardButton = UIButton(configuration: .plain())
    /// The glass capsules behind each button pair, or plain translucent views before iOS 26.
    let leadingPill = ChatMediaViewerController.makePill()
    let trailingPill = ChatMediaViewerController.makePill()

    /// The views a tap shows and hides.
    private var chrome: [UIView] { [closeButton, leadingPill, trailingPill] }

    /// Whether Reduce Motion is on. Settable so tests can drive both modes.
    var reducesMotion: () -> Bool = { UIAccessibility.isReduceMotionEnabled }

    /// Whether the buttons are away. The photo opens with them hidden; a single tap toggles them.
    private(set) var areControlsHidden = true

    private var isSaving = false

    /// The reaction strip above the React button while it is open, and the full-screen view that
    /// catches a tap outside it.
    private(set) var reactionStrip: ReactionStripView?
    private var reactionDismissCatcher: UIControl?

    /// The photo itself, once drawn, never the placeholder, so save never writes a BlurHash.
    private var loadedImage: UIImage? {
        didSet {
            saveButton.isEnabled = loadedImage != nil
        }
    }

    /// - Parameters:
    ///   - onReply: puts the composer into reply mode for the photo's message. Runs after the viewer dismisses.
    ///   - onForward: opens the message-link share for the photo's message. Runs after the viewer dismisses.
    ///   - onSave: writes the photo to the library, throwing when it can't. Gets the original bytes when held.
    ///   - onReact: toggles the picked emoji on the photo's message, the call the context-menu strip makes.
    ///   - onMoreReactions: opens the full reaction picker. Runs after the viewer dismisses.
    ///   - reactionEntries: the emoji the strip offers; empty means there is no strip.
    public init(
        request: ChatMediaViewerRequest,
        onReply: @escaping () -> Void,
        onForward: @escaping () -> Void,
        onSave: @escaping (UIImage, Data?) async throws -> Void,
        onReact: @escaping (String) -> Void,
        onMoreReactions: @escaping () -> Void,
        reactionEntries: @escaping () -> [ReactionStrip.Entry]
    ) {
        self.request = request
        self.onReply = onReply
        self.onForward = onForward
        self.onSave = onSave
        self.originalData = { [blobID = request.blobID] in ChatMediaImageSource.originalData(blobID: blobID) }
        self.onReact = onReact
        self.onMoreReactions = onMoreReactions
        self.reactionEntries = reactionEntries
        super.init(nibName: nil, bundle: nil)

        let zoom = UIViewController.Transition.ZoomOptions()
        // A zoomed-in photo pans instead; the swipe down only dismisses at the fitted size.
        zoom.interactiveDismissShouldBegin = { [weak self] _ in
            guard let self else { return true }
            return scrollView.zoomScale <= scrollView.minimumZoomScale
        }
        preferredTransition = .zoom(options: zoom) { [sourceView = request.sourceView] _ in sourceView() }
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        // The photo sits on black, so the glass, strip and glyphs always take the dark variant.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = Self.maximumZoomScale
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Photo"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        configure(closeButton, icon: .crossMedium, label: "Close", action: #selector(closeTapped))
        configure(reactButton, icon: .emojiAddReaction, label: "React", action: #selector(reactTapped))
        configure(replyButton, icon: .arrowShareLeft, label: "Reply", action: #selector(replyTapped))
        configure(saveButton, icon: Self.saveIcon, label: "Save", action: #selector(saveTapped))
        configure(forwardButton, icon: .arrowShareRight, label: "Forward", action: #selector(forwardTapped))

        if #available(iOS 26, *) {
            var glass = UIButton.Configuration.glass()
            glass.image = closeButton.configuration?.image
            glass.baseForegroundColor = .white
            glass.cornerStyle = .capsule
            closeButton.configuration = glass
        } else {
            closeButton.backgroundColor = Self.chromeFill
            closeButton.layer.cornerCurve = .continuous
        }
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        reactButton.isHidden = !request.canReact
        replyButton.isHidden = !request.canReply
        forwardButton.isHidden = !request.canForward
        install(leadingPill, buttons: [reactButton, replyButton])
        install(trailingPill, buttons: [saveButton, forwardButton])
        // A pill with no buttons left would be an empty capsule.
        leadingPill.isHidden = [reactButton, replyButton].allSatisfy(\.isHidden)
        trailingPill.isHidden = [saveButton, forwardButton].allSatisfy(\.isHidden)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Pinned to the frame, so at scale 1 the photo fits the screen and zooming grows it.
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            leadingPill.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            leadingPill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            trailingPill.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            trailingPill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])

        updateReactButton(entries: reactionEntries())
        observeReactionEntries()
        loadedImage = nil
        setControlsHidden(true, animated: false)
        loadImage()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard #unavailable(iOS 26) else { return }
        closeButton.layer.cornerRadius = closeButton.bounds.height / 2
        for pill in [leadingPill, trailingPill] {
            pill.layer.cornerRadius = pill.bounds.height / 2
        }
    }

    private static let chromeFill = UIColor(white: 0.12, alpha: 0.72)

    private static let saveIcon: Icon = .arrowWallDown

    /// Draws `icon` as a 22pt template glyph, since a button configuration draws an asset at its own size.
    private static func chromeIcon(_ icon: Icon) -> UIImage {
        let size = CGSize(width: 22, height: 22)
        return UIGraphicsImageRenderer(size: size)
            .image { _ in UIImage.icon(icon).draw(in: CGRect(origin: .zero, size: size)) }
            .withRenderingMode(.alwaysTemplate)
    }

    private func configure(_ button: UIButton, icon: Icon, label: String, action: Selector) {
        button.configuration?.image = Self.chromeIcon(icon)
        button.configuration?.baseForegroundColor = .white
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        button.configurationUpdateHandler = { button in
            button.alpha = button.isEnabled ? 1 : 0.4
        }
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private static func makePill() -> UIView {
        if #available(iOS 26, *) {
            let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glass.cornerConfiguration = .capsule()
            return glass
        }
        let pill = UIView()
        pill.backgroundColor = chromeFill
        pill.layer.cornerCurve = .continuous
        return pill
    }

    private func install(_ pill: UIView, buttons: [UIButton]) {
        let content = (pill as? UIVisualEffectView)?.contentView ?? pill
        pill.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        view.addSubview(pill)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            pill.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    /// Draws the staged image, or the placeholder under the download. The transcript caches only its
    /// downsampled copy, so the full-size photo downloads here, over the copy the cell already drew.
    private func loadImage() {
        if let localImage = request.localImage {
            imageView.image = localImage
            loadedImage = localImage
            return
        }
        imageView.image = request.placeholder
        loadedImage = nil
        guard let remote = request.remote else { return }
        imageView.kf.setImage(
            with: ChatMediaImageSource.source(blobID: request.blobID, location: remote),
            placeholder: request.placeholder,
            options: ChatMediaImageSource.options()
        ) { [weak self] result in
            ChatMediaImageSource.persist(result)
            switch result {
            case .success(let value):
                self?.loadedImage = value.image
            case .failure:
                // Best-effort: the placeholder stays up and zoom and save stay off.
                break
            }
        }
    }

    // MARK: - Zoom

    /// The scale a double-tap lands on from `current`: in to the double-tap scale from the fitted
    /// size, and back out to fitted from anywhere else.
    static func doubleTapTargetScale(_ current: CGFloat, _ minimum: CGFloat) -> CGFloat {
        current > minimum ? minimum : doubleTapZoomScale
    }

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        toggleZoom(about: recognizer.location(in: imageView), animated: true)
    }

    /// Zooms to the double-tap scale centered on `point` (in the image view's space), or back to the
    /// fitted size when already zoomed.
    func toggleZoom(about point: CGPoint, animated: Bool) {
        // Reduce Motion swaps the scale animation for a crossfade between the two zoom states.
        let slides = animated && !reducesMotion()
        let apply = { [self] in
            let target = Self.doubleTapTargetScale(scrollView.zoomScale, scrollView.minimumZoomScale)
            guard target > scrollView.minimumZoomScale else {
                scrollView.setZoomScale(target, animated: slides)
                return
            }
            let size = CGSize(width: scrollView.bounds.width / target, height: scrollView.bounds.height / target)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: slides)
        }
        if animated && !slides {
            UIView.transition(with: scrollView, duration: 0.2, options: .transitionCrossDissolve, animations: apply)
        } else {
            apply()
        }
    }

    // MARK: - Controls

    @objc private func singleTapped() {
        setControlsHidden(!areControlsHidden, animated: true)
    }

    /// Fades the buttons out or back in; hidden buttons take no touches and drop out of VoiceOver.
    func setControlsHidden(_ hidden: Bool, animated: Bool) {
        areControlsHidden = hidden
        if hidden { dismissReactionStrip(animated: false) }
        for view in chrome {
            view.isUserInteractionEnabled = !hidden
            view.accessibilityElementsHidden = hidden
        }
        let fade = { [chrome] in
            for view in chrome { view.alpha = hidden ? 0 : 1 }
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: fade)
        } else {
            fade()
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func reactTapped() {
        if reactionStrip != nil {
            dismissReactionStrip(animated: true)
        } else {
            showReactionStrip()
        }
    }

    /// Opens the strip just above the React button, with a full-screen catcher behind it so a tap
    /// outside dismisses it without reacting.
    func showReactionStrip() {
        let entries = reactionEntries()
        guard reactionStrip == nil, !entries.isEmpty else { return }

        let catcher = UIControl()
        catcher.translatesAutoresizingMaskIntoConstraints = false
        catcher.addTarget(self, action: #selector(reactionCatcherTapped), for: .touchUpInside)
        // Under Close, so one tap on Close still closes the viewer while the strip is up.
        view.insertSubview(catcher, belowSubview: closeButton)

        let strip = ReactionStripView()
        strip.configure(entries: entries)
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.onSelect = { [weak self] emoji in
            self?.dismissReactionStrip(animated: true)
            self?.onReact(emoji)
        }
        strip.onAdd = { [weak self] in
            self?.dismissReactionStrip(animated: false)
            self?.dismiss(animated: true) { self?.onMoreReactions() }
        }
        view.addSubview(strip)
        NSLayoutConstraint.activate([
            catcher.topAnchor.constraint(equalTo: view.topAnchor),
            catcher.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            catcher.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            catcher.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            strip.leadingAnchor.constraint(equalTo: leadingPill.leadingAnchor),
            strip.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            strip.bottomAnchor.constraint(equalTo: leadingPill.topAnchor, constant: -12),
        ])
        reactionStrip = strip
        reactionDismissCatcher = catcher
        reactButton.accessibilityLabel = "Close reactions"
        strip.alpha = 0
        UIView.animate(withDuration: 0.2) { strip.alpha = 1 }
    }

    /// Re-reads the entries whenever what `reactionEntries` reads changes, so the React button's emoji
    /// and, while it is open, the strip's highlights follow the message's live reactions.
    private func observeReactionEntries() {
        _ = withObservationTracking {
            reactionEntries()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshReactionChrome()
            }
        }
    }

    private func refreshReactionChrome() {
        observeReactionEntries()
        let fresh = reactionEntries()
        updateReactButton(entries: fresh)
        guard let strip = reactionStrip else { return }
        if fresh.isEmpty {
            dismissReactionStrip(animated: true)
        } else {
            strip.configure(entries: fresh)
        }
    }

    /// The most emoji the React button draws before it folds the rest into "+N".
    static let reactButtonEmojiLimit = 3

    /// What the React button shows for the user's own reactions: nothing to draw for none, up to
    /// three emoji, or the first two and the count of the rest.
    static func reactGlyph(for own: [String]) -> (emoji: [String], overflow: Int) {
        if own.count <= reactButtonEmojiLimit { return (own, 0) }
        return (Array(own.prefix(reactButtonEmojiLimit - 1)), own.count - (reactButtonEmojiLimit - 1))
    }

    static func reactAccessibilityLabel(for own: [String]) -> String {
        switch own.count {
        case 0: "React"
        case 1: "React, you reacted \(own[0])"
        default: "React, you reacted \(own.dropLast().joined(separator: ", ")) and \(own[own.count - 1])"
        }
    }

    /// Swaps the face icon for the user's own reaction emoji, overlapped tightly, when they have any.
    private func updateReactButton(entries: [ReactionStrip.Entry]) {
        let own = entries.filter(\.highlighted).map(\.emoji)
        if reactionStrip == nil { reactButton.accessibilityLabel = Self.reactAccessibilityLabel(for: own) }
        guard own != ownReactionEmoji else { return }
        ownReactionEmoji = own
        guard !own.isEmpty else {
            reactChips = []
            reactButton.configuration?.image = Self.reactSymbol
            return
        }
        reactChips = Self.reactChipLabels(for: own)
        reactButton.configuration?.image = Self.reactChipStack(reactChips)
    }

    /// The chips the React button draws: each own emoji, or the first two and a "+N" chip.
    static func reactChipLabels(for own: [String]) -> [String] {
        let glyph = reactGlyph(for: own)
        return glyph.emoji + (glyph.overflow > 0 ? ["+\(glyph.overflow)"] : [])
    }

    static let reactChipDiameter: CGFloat = 28
    static let reactChipRing: CGFloat = 2
    /// How much of each chip the next one covers, about a fifth of its width, plus the ring, so each emoji stays readable.
    static let reactChipOverlap: CGFloat = 6
    /// Opaque, matching the glass's dark tint, so a chip and its ring cut cleanly into the one below.
    static let reactChipColor = UIColor(white: 0.14, alpha: 1)

    /// Avatar-stack of circular chips, first leftmost and later ones on top.
    static func reactChipStack(_ labels: [String]) -> UIImage {
        let d = reactChipDiameter, ring = reactChipRing
        let step = d - reactChipOverlap
        let size = CGSize(width: d + step * CGFloat(max(labels.count - 1, 0)) + ring * 2, height: d + ring * 2)
        return UIGraphicsImageRenderer(size: size).image { _ in
            for (index, label) in labels.enumerated() {
                let rect = CGRect(x: ring + step * CGFloat(index), y: ring, width: d, height: d)
                reactChipColor.setFill()
                UIBezierPath(ovalIn: rect.insetBy(dx: -ring, dy: -ring)).fill()
                let isCount = label.hasPrefix("+")
                let font = isCount ? UIFont.systemFont(ofSize: 13, weight: .semibold) : UIFont.systemFont(ofSize: 17)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let textSize = (label as NSString).size(withAttributes: attributes)
                (label as NSString).draw(
                    at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
                    withAttributes: attributes
                )
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    static let reactSymbol = chromeIcon(.emojiAddReaction)

    func dismissReactionStrip(animated: Bool) {
        guard let strip = reactionStrip else { return }
        let catcher = reactionDismissCatcher
        reactionStrip = nil
        reactionDismissCatcher = nil
        reactButton.accessibilityLabel = Self.reactAccessibilityLabel(for: ownReactionEmoji)
        catcher?.removeFromSuperview()
        guard animated else { strip.removeFromSuperview(); return }
        UIView.animate(withDuration: 0.15, animations: { strip.alpha = 0 }) { _ in strip.removeFromSuperview() }
    }

    @objc private func reactionCatcherTapped() {
        dismissReactionStrip(animated: true)
    }

    @objc private func replyTapped() {
        dismiss(animated: true) { [onReply] in onReply() }
    }

    @objc private func forwardTapped() {
        dismiss(animated: true) { [onForward] in onForward() }
    }

    @objc private func saveTapped() {
        guard let image = loadedImage, !isSaving else { return }
        isSaving = true
        let original = originalData()
        Task { [weak self, onSave] in
            do {
                try await onSave(image, original)
                self?.showSaved()
            } catch {
                self?.showSaveFailure()
            }
            self?.isSaving = false
        }
    }

    /// Swaps the save glyph for a checkmark for a moment, the way the Access Key's save button shows success.
    private func showSaved() {
        saveButton.configuration?.image = Self.chromeIcon(.checkmark1)
        saveButton.accessibilityLabel = "Saved"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.saveButton.configuration?.image = Self.chromeIcon(Self.saveIcon)
            self?.saveButton.accessibilityLabel = "Save"
        }
    }

    /// The same alert the Access Key's save raises when Photos refuses it. The app's SwiftUI dialog
    /// would draw under this modal, so it is a system alert here.
    private func showSaveFailure() {
        let alert = UIAlertController(
            title: "Failed to Save",
            message: "Please allow Flipcash access to Photos in Settings in order to save this photo.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Open Settings", style: .destructive) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        present(alert, animated: true)
    }
}
#endif
