//
//  ChatMediaViewerController.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
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
        self.canReply = message.actions.contains(.reply)
        self.canForward = message.actions.contains(.forward)
    }
}

/// A full-screen photo, zoomed in from the tapped transcript row: pinch or double-tap to zoom, swipe
/// down or close to put it back. It opens with no buttons; a tap shows or hides them. The buttons zoom,
/// reply, save to Photos and forward, with zoom and save waiting for the photo itself to load.
public final class ChatMediaViewerController: UIViewController, UIScrollViewDelegate {

    private static let maximumZoomScale: CGFloat = 4
    private static let doubleTapZoomScale: CGFloat = 2.5

    private let request: ChatMediaViewerRequest
    private let onReply: () -> Void
    private let onForward: () -> Void
    private let onSave: (UIImage) async throws -> Void

    let scrollView = UIScrollView()
    let imageView = UIImageView()
    let closeButton = UIButton(configuration: .plain())
    let zoomButton = UIButton(configuration: .plain())
    let replyButton = UIButton(configuration: .plain())
    let saveButton = UIButton(configuration: .plain())
    let forwardButton = UIButton(configuration: .plain())
    let leadingPill = UIView()
    let trailingPill = UIView()

    /// The views a tap shows and hides.
    private var chrome: [UIView] { [closeButton, leadingPill, trailingPill] }

    /// Whether the buttons are away. The photo opens with them hidden; a single tap toggles them.
    private(set) var areControlsHidden = true

    private var isSaving = false

    /// The photo itself, once drawn, never the placeholder, so save never writes a BlurHash.
    private var loadedImage: UIImage? {
        didSet {
            saveButton.isEnabled = loadedImage != nil
            zoomButton.isEnabled = loadedImage != nil
        }
    }

    /// - Parameters:
    ///   - onReply: puts the composer into reply mode for the photo's message. Runs after the viewer dismisses.
    ///   - onForward: opens the message-link share for the photo's message. Runs after the viewer dismisses.
    ///   - onSave: writes the photo to the library, throwing when it can't.
    public init(
        request: ChatMediaViewerRequest,
        onReply: @escaping () -> Void,
        onForward: @escaping () -> Void,
        onSave: @escaping (UIImage) async throws -> Void
    ) {
        self.request = request
        self.onReply = onReply
        self.onForward = onForward
        self.onSave = onSave
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

        configure(closeButton, symbol: "xmark", label: "Close", action: #selector(closeTapped))
        configure(zoomButton, symbol: "plus.magnifyingglass", label: "Zoom", action: #selector(zoomTapped))
        configure(replyButton, symbol: "arrowshape.turn.up.left", label: "Reply", action: #selector(replyTapped))
        configure(saveButton, symbol: "square.and.arrow.down", label: "Save", action: #selector(saveTapped))
        configure(forwardButton, symbol: "arrowshape.turn.up.right", label: "Forward", action: #selector(forwardTapped))

        closeButton.backgroundColor = Self.chromeFill
        closeButton.layer.cornerCurve = .continuous
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        replyButton.isHidden = !request.canReply
        forwardButton.isHidden = !request.canForward
        install(leadingPill, buttons: [zoomButton, replyButton])
        install(trailingPill, buttons: [saveButton, forwardButton])
        // A pill with no buttons left would be an empty capsule.
        leadingPill.isHidden = [zoomButton, replyButton].allSatisfy(\.isHidden)
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

        loadedImage = nil
        setControlsHidden(true, animated: false)
        loadImage()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        closeButton.layer.cornerRadius = closeButton.bounds.height / 2
        for pill in [leadingPill, trailingPill] {
            pill.layer.cornerRadius = pill.bounds.height / 2
        }
    }

    private static let chromeFill = UIColor(white: 0.12, alpha: 0.72)

    private func configure(_ button: UIButton, symbol: String, label: String, action: Selector) {
        button.configuration?.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        button.configuration?.baseForegroundColor = .white
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        button.configurationUpdateHandler = { button in
            button.alpha = button.isEnabled ? 1 : 0.4
        }
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func install(_ pill: UIView, buttons: [UIButton]) {
        pill.backgroundColor = Self.chromeFill
        pill.layer.cornerCurve = .continuous
        pill.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(stack)
        view.addSubview(pill)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12),
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

    @objc private func zoomTapped() {
        guard loadedImage != nil else { return }
        toggleZoom(about: CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY), animated: true)
    }

    /// Zooms to the double-tap scale centered on `point` (in the image view's space), or back to the
    /// fitted size when already zoomed.
    func toggleZoom(about point: CGPoint, animated: Bool) {
        let target = Self.doubleTapTargetScale(scrollView.zoomScale, scrollView.minimumZoomScale)
        guard target > scrollView.minimumZoomScale else {
            scrollView.setZoomScale(target, animated: animated)
            return
        }
        let size = CGSize(width: scrollView.bounds.width / target, height: scrollView.bounds.height / target)
        scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: animated)
    }

    // MARK: - Controls

    @objc private func singleTapped() {
        setControlsHidden(!areControlsHidden, animated: true)
    }

    /// Fades the buttons out or back in; hidden buttons take no touches and drop out of VoiceOver.
    func setControlsHidden(_ hidden: Bool, animated: Bool) {
        areControlsHidden = hidden
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

    @objc private func replyTapped() {
        dismiss(animated: true) { [onReply] in onReply() }
    }

    @objc private func forwardTapped() {
        dismiss(animated: true) { [onForward] in onForward() }
    }

    @objc private func saveTapped() {
        guard let image = loadedImage, !isSaving else { return }
        isSaving = true
        Task { [weak self, onSave] in
            do {
                try await onSave(image)
                self?.showSaved()
            } catch {
                self?.showSaveFailure()
            }
            self?.isSaving = false
        }
    }

    /// Swaps the save glyph for a checkmark for a moment, the way the Access Key's save button shows success.
    private func showSaved() {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        saveButton.configuration?.image = UIImage(systemName: "checkmark", withConfiguration: config)
        saveButton.accessibilityLabel = "Saved"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.saveButton.configuration?.image = UIImage(systemName: "square.and.arrow.down", withConfiguration: config)
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
