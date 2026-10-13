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
    }
}

/// A full-screen photo, zoomed in from the tapped transcript row: pinch or double-tap to zoom, swipe
/// down or close to put it back, tap to hide or show the buttons, and share once the photo itself
/// has loaded.
public final class ChatMediaViewerController: UIViewController, UIScrollViewDelegate {

    private static let maximumZoomScale: CGFloat = 4
    private static let doubleTapZoomScale: CGFloat = 2.5

    private let request: ChatMediaViewerRequest
    private let onShare: (UIImage) -> Void

    let scrollView = UIScrollView()
    let imageView = UIImageView()
    let shareButton = UIButton(configuration: .plain())
    let closeButton = UIButton(configuration: .plain())

    /// Whether a single tap has put the close and share buttons away.
    private(set) var areControlsHidden = false

    /// The photo itself, once drawn — never the placeholder, so share never hands out a BlurHash.
    private var loadedImage: UIImage? {
        didSet { shareButton.isEnabled = loadedImage != nil }
    }

    /// - Parameter onShare: presents the system share sheet for the photo.
    public init(request: ChatMediaViewerRequest, onShare: @escaping (UIImage) -> Void) {
        self.request = request
        self.onShare = onShare
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
        configure(shareButton, symbol: "square.and.arrow.up", label: "Share", action: #selector(shareTapped))

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
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            shareButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            shareButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
        ])

        loadImage()
    }

    private func configure(_ button: UIButton, symbol: String, label: String, action: Selector) {
        button.configuration?.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        button.configuration?.baseForegroundColor = .white
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
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
                // Best-effort: the placeholder stays up and share stays off.
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
        let target = Self.doubleTapTargetScale(scrollView.zoomScale, scrollView.minimumZoomScale)
        guard target > scrollView.minimumZoomScale else {
            scrollView.setZoomScale(target, animated: true)
            return
        }
        let point = recognizer.location(in: imageView)
        let size = CGSize(width: scrollView.bounds.width / target, height: scrollView.bounds.height / target)
        scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }

    // MARK: - Controls

    @objc private func singleTapped() {
        setControlsHidden(!areControlsHidden, animated: true)
    }

    /// Fades the close and share buttons out or back in; hidden buttons take no touches and drop out
    /// of VoiceOver.
    func setControlsHidden(_ hidden: Bool, animated: Bool) {
        areControlsHidden = hidden
        for button in [closeButton, shareButton] {
            button.isUserInteractionEnabled = !hidden
            button.accessibilityElementsHidden = hidden
        }
        let fade = { [closeButton, shareButton] in
            closeButton.alpha = hidden ? 0 : 1
            shareButton.alpha = hidden ? 0 : 1
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

    @objc private func shareTapped() {
        guard let loadedImage else { return }
        onShare(loadedImage)
    }
}
#endif
