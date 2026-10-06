//
//  ChatMediaCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore
import Kingfisher

/// A recycled cell for a photo row: the photo at the transcript's bubble width and a clamped aspect,
/// a reply's quote laid over its top-leading corner, its caption as a text bubble directly under it,
/// and the reaction pills, in a `ChatColumnCell`.
///
/// The photo draws from, in order: the local image of a pending send this device staged, the
/// resolved download URL (fading in over the BlurHash), or the BlurHash alone. A BlurHash-only row —
/// see ``isBlurhashOnly(_:canReact:)`` — draws nothing else, takes no tap, and hides its reactions.
public final class ChatMediaCell: ChatColumnCell {

    public static let reuseIdentifier = "ChatMediaCell"

    /// The gap between the photo and its caption bubble: the transcript's tight row gap, since the
    /// two read as one run.
    static let captionGap: CGFloat = 5
    private static let captionInset: CGFloat = 12
    private static let captionPadding: CGFloat = 9
    private static let fadeDuration: TimeInterval = 0.25
    /// The progress capsule's inset from the photo's bottom-right corner.
    private static let progressInset: CGFloat = 10
    /// The quote's gap from the photo's top and leading edges. Tighter than a text reply's surround:
    /// at the photo's corner a wider gap leaves the panel a corner that reads as square.
    static let quoteInset: CGFloat = 4
    /// The share of the photo's width the quote may take, so some of the photo always shows beside it.
    static let quoteMaxWidthFraction: CGFloat = 0.8
    /// Near-opaque, so the quote reads over any photo, light or dark.
    private static let quoteGroundAlpha: CGFloat = 0.85

    private let stack = UIStackView()
    private let imageBubble = BubbleBackgroundView()
    let imageView = UIImageView()
    /// Shown over the BlurHash when an encrypted photo's bytes fail to decrypt or check out.
    let unavailableLabel = UILabel()
    /// Shows how far an outgoing photo's send has got, until it is sent or fails.
    let progressOverlay = ChatPhotoProgressOverlay()
    /// A reply's quote, drawn over the photo. A sibling of the photo rather than its subview, so it
    /// stays its own accessibility element and its tap never reaches the photo's.
    let quotePanel = ChatQuotePanelView()
    let captionBubble = BubbleBackgroundView()
    let captionLabel = UILabel()
    let reactionRow = ReactionPillRowView()
    let imageTap = UITapGestureRecognizer()

    private var imageWidthConstraint: NSLayoutConstraint!
    private var imageHeightConstraint: NSLayoutConstraint!
    private var captionMaxWidthConstraint: NSLayoutConstraint!
    private var reactionRowWidthConstraint: NSLayoutConstraint!

    /// The row the image view is currently drawing, so a pending row that confirms keeps its local
    /// image under the download instead of dropping back to the BlurHash.
    private var drawnRowID: String?

    /// Whether the row `configure` last ran with draws only its BlurHash.
    private(set) var blurhashOnly = false

    /// Fired when the viewer taps the photo. Never fires for a BlurHash-only or a failed row.
    var onImageTap: (() -> Void)?
    /// Called with the quoted row's stable id when the viewer taps the quote.
    var onQuoteTap: ((String) -> Void)? {
        get { quotePanel.onTap }
        set { quotePanel.onTap = newValue }
    }
    /// Fired when the viewer taps a reaction pill — the argument is the toggled emoji.
    var onReactionTap: ((String) -> Void)?
    /// Fired on a long-press of a reaction pill, to open the reactors sheet scoped to that emoji.
    var onReactionLongPress: ((String) -> Void)?
    /// Fired when the trailing "+" is tapped, to open the picker.
    var onReactionAdd: (() -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageBubble.addSubview(imageView)
        imageBubble.isAccessibilityElement = true
        imageBubble.accessibilityLabel = "Photo"
        unavailableLabel.text = ChatMediaStrings.undecryptable
        unavailableLabel.font = .default(size: 14, weight: .medium)
        unavailableLabel.textColor = .white
        unavailableLabel.textAlignment = .center
        unavailableLabel.numberOfLines = 0
        unavailableLabel.isHidden = true
        unavailableLabel.translatesAutoresizingMaskIntoConstraints = false
        imageBubble.addSubview(unavailableLabel)
        progressOverlay.translatesAutoresizingMaskIntoConstraints = false
        imageBubble.addSubview(progressOverlay)
        imageTap.addTarget(self, action: #selector(imageTapped))
        imageBubble.addGestureRecognizer(imageTap)

        captionLabel.font = .default(size: 16, weight: .medium)
        captionLabel.textColor = .white
        captionLabel.numberOfLines = 0
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionBubble.addSubview(captionLabel)
        captionBubble.isHidden = true

        stack.axis = .vertical
        stack.spacing = Self.captionGap
        stack.addArrangedSubview(imageBubble)
        stack.addArrangedSubview(captionBubble)

        quotePanel.ground = UIColor(Color.backgroundMain).withAlphaComponent(Self.quoteGroundAlpha)
        quotePanel.isHidden = true
        quotePanel.translatesAutoresizingMaskIntoConstraints = false
        stack.addSubview(quotePanel)

        installColumn(content: stack, accessory: reactionRow)
        reactionRow.onToggle = { [weak self] emoji in self?.onReactionTap?(emoji) }
        reactionRow.onLongPress = { [weak self] emoji in self?.onReactionLongPress?(emoji) }
        reactionRow.onAdd = { [weak self] in self?.onReactionAdd?() }

        imageWidthConstraint = imageBubble.widthAnchor.constraint(equalToConstant: 240)
        // Below required so the photo yields to the cell's self-sizing height instead of fighting it.
        imageHeightConstraint = imageBubble.heightAnchor.constraint(equalToConstant: 240)
        imageHeightConstraint.priority = UILayoutPriority(999)
        captionMaxWidthConstraint = captionBubble.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        reactionRowWidthConstraint = reactionRow.widthAnchor.constraint(equalToConstant: 240)

        NSLayoutConstraint.activate([
            imageWidthConstraint,
            imageHeightConstraint,
            captionMaxWidthConstraint,
            reactionRowWidthConstraint,

            imageView.topAnchor.constraint(equalTo: imageBubble.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageBubble.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageBubble.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageBubble.bottomAnchor),

            progressOverlay.widthAnchor.constraint(equalToConstant: ChatPhotoProgressOverlay.size.width),
            progressOverlay.heightAnchor.constraint(equalToConstant: ChatPhotoProgressOverlay.size.height),
            progressOverlay.trailingAnchor.constraint(equalTo: imageBubble.trailingAnchor, constant: -Self.progressInset),
            progressOverlay.bottomAnchor.constraint(equalTo: imageBubble.bottomAnchor, constant: -Self.progressInset),

            unavailableLabel.centerYAnchor.constraint(equalTo: imageBubble.centerYAnchor),
            unavailableLabel.leadingAnchor.constraint(equalTo: imageBubble.leadingAnchor, constant: Self.captionInset),
            unavailableLabel.trailingAnchor.constraint(equalTo: imageBubble.trailingAnchor, constant: -Self.captionInset),

            quotePanel.topAnchor.constraint(equalTo: imageBubble.topAnchor, constant: Self.quoteInset),
            quotePanel.leadingAnchor.constraint(equalTo: imageBubble.leadingAnchor, constant: Self.quoteInset),
            quotePanel.widthAnchor.constraint(lessThanOrEqualTo: imageBubble.widthAnchor, multiplier: Self.quoteMaxWidthFraction),
            quotePanel.bottomAnchor.constraint(lessThanOrEqualTo: imageBubble.bottomAnchor, constant: -Self.quoteInset),

            captionLabel.topAnchor.constraint(equalTo: captionBubble.topAnchor, constant: Self.captionPadding),
            captionLabel.bottomAnchor.constraint(equalTo: captionBubble.bottomAnchor, constant: -Self.captionPadding),
            captionLabel.leadingAnchor.constraint(equalTo: captionBubble.leadingAnchor, constant: Self.captionInset),
            captionLabel.trailingAnchor.constraint(equalTo: captionBubble.trailingAnchor, constant: -Self.captionInset),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Scopes the row's touch target to the photo, caption, and pills, like the cash card: the cell
    /// spans the full transcript width, and a tap beside the photo should not land on it.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        stack.convert(stack.bounds, to: self).contains(point)
            || (!reactionRow.isHidden && reactionRow.convert(reactionRow.bounds, to: self).contains(point))
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        showUnavailable(false)
        progressOverlay.bind(nil, suppressed: false, animated: false)
        drawnRowID = nil
        reactionRow.prepareForReuse()
    }

    /// Whether a photo draws only its BlurHash: the server withheld it, or the viewer is previewing a
    /// group they have not joined — the one reason `canReact` is false. Such a row is never fetched.
    static func isBlurhashOnly(_ media: ChatMediaContent, canReact: Bool) -> Bool {
        media.isRedacted || !canReact
    }

    /// - Parameters:
    ///   - maxWidth: the transcript's widest bubble, which the photo always spans.
    ///   - localImage: the picked image of a pending send this device staged, or nil.
    ///   - progress: the send progress of a pending photo this device staged, or nil.
    ///   - remote: where the photo downloads from, or nil until it is resolved.
    ///   - quoteThumbnail: where a quoted photo's thumbnail loads from, or nil.
    public func configure(
        with message: ChatMessage,
        maxWidth: CGFloat,
        localImage: UIImage?,
        progress: ChatPhotoSendProgress? = nil,
        remote: ChatMediaLocation?,
        quoteThumbnail: ChatMediaLocation? = nil,
        authorImageData: Data? = nil
    ) {
        guard case .media(let media) = message.content else { return }
        let blurhashOnly = Self.isBlurhashOnly(media, canReact: message.canReact)
        self.blurhashOnly = blurhashOnly

        let size = ChatMediaBubbleSizing.size(
            imageWidth: Double(media.width),
            imageHeight: Double(media.height),
            maxWidth: Double(maxWidth)
        )
        imageWidthConstraint.constant = size.width
        imageHeightConstraint.constant = size.height
        // The same row losing its progress is a confirmed send, which fades; a new row starts clean.
        progressOverlay.bind(progress, suppressed: message.isFailed, animated: drawnRowID == message.id)
        drawImage(
            for: message.id,
            blobID: media.blobID,
            blurhash: media.blurhash,
            localImage: blurhashOnly ? nil : localImage,
            remote: blurhashOnly ? nil : remote,
            size: CGSize(width: size.width, height: size.height)
        )
        imageTap.isEnabled = !blurhashOnly && !message.isFailed

        let caption = media.caption.flatMap { $0.isEmpty ? nil : $0 }
        captionLabel.text = caption
        captionBubble.isHidden = caption == nil
        captionMaxWidthConstraint.constant = maxWidth

        let isFromSelf = message.sender == .me
        let fill = BubbleBackgroundView.fill(isFromSelf: isFromSelf)
        imageBubble.apply(
            fill: fill,
            radii: BubbleBackgroundView.radii(
                isFromSelf: isFromSelf,
                groupedAbove: message.joinsBubbleAbove,
                groupedBelow: caption != nil || message.joinsBubbleBelow
            ),
            identity: message.id
        )
        captionBubble.apply(
            fill: fill,
            radii: BubbleBackgroundView.radii(isFromSelf: isFromSelf, groupedAbove: true, groupedBelow: message.joinsBubbleBelow),
            identity: message.id
        )
        stack.alignment = isFromSelf ? .trailing : .leading

        if let quote = message.quote {
            quotePanel.configure(with: quote, thumbnail: quoteThumbnail)
            quotePanel.cornerRadii = ChatQuotePanelView.photoOverlayRadii(
                photoTopLeading: imageBubble.radii.topLeading,
                inset: Self.quoteInset
            )
            quotePanel.isHidden = false
        } else {
            quotePanel.clear()
            quotePanel.isHidden = true
        }

        reactionRowWidthConstraint.constant = maxWidth
        reactionRow.layoutWidth = maxWidth
        reactionRow.hugsTrailingEdge = isFromSelf
        reactionRow.configure(pills: blurhashOnly ? [] : message.reactions, canReact: message.canReact && !blurhashOnly)
        reactionRow.isHidden = blurhashOnly
        updateColumn(for: message, authorImageData: authorImageData)
    }

    private func drawImage(for rowID: String, blobID: BlobID?, blurhash: String?, localImage: UIImage?, remote: ChatMediaLocation?, size: CGSize) {
        let isSameRow = drawnRowID == rowID
        drawnRowID = rowID
        if !isSameRow { showUnavailable(false) }

        if let localImage {
            imageView.kf.cancelDownloadTask()
            imageView.image = localImage
            return
        }

        let preview = BlurHashCache.shared.image(for: blurhash)
        guard let remote else {
            imageView.kf.cancelDownloadTask()
            imageView.image = preview
            return
        }

        // Whatever this row already shows — its local image, or the photo itself on a reconfigure —
        // stays under the load, so only a BlurHash is ever faded over.
        let placeholder = isSameRow ? (imageView.image ?? preview) : preview
        let processor = DownsamplingImageProcessor(size: size)
        imageView.kf.setImage(
            with: ChatMediaImageSource.source(blobID: blobID, location: remote),
            placeholder: placeholder,
            options: ChatMediaImageSource.options(processor: processor) + [
                .scaleFactor(traitCollection.displayScale),
                .transition(.fade(Self.fadeDuration)),
            ]
        ) { [weak self] result in
            ChatMediaImageSource.persist(result, processor: processor)
            if case .failure(let error) = result, ChatMediaImageSource.isUndecryptable(error) {
                self?.showUnavailable(true)
            }
        }
    }

    /// Marks the photo as one that can't be shown: an encrypted blob that failed to authenticate or
    /// wasn't the length its sender declared. It keeps its BlurHash and takes no tap.
    private func showUnavailable(_ unavailable: Bool) {
        unavailableLabel.isHidden = !unavailable
        imageBubble.accessibilityLabel = unavailable ? ChatMediaStrings.undecryptable : "Photo"
        if unavailable { imageTap.isEnabled = false }
    }

    @objc private func imageTapped() {
        onImageTap?()
    }
}

extension ChatMediaCell: BubbleCarrying {
    /// The photo and its caption, not the cell: the cell spans the full row.
    var liftPreviewView: UIView { stack }

    var liftPreviewMaskingPath: UIBezierPath? {
        let path = UIBezierPath()
        for bubble in [imageBubble, captionBubble] where !bubble.isHidden {
            let shape = bubble.maskingPath
            shape.apply(CGAffineTransform(translationX: bubble.frame.minX, y: bubble.frame.minY))
            path.append(shape)
        }
        return path
    }

    func flashAttention(startedAt start: CFTimeInterval) {
        imageBubble.flashAttention(startedAt: start)
        if !captionBubble.isHidden { captionBubble.flashAttention(startedAt: start) }
    }
}
#endif
