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

    /// How far each photo behind a card stack's front one turns, alternating sides.
    static let stackFanAngle: CGFloat = 4 * .pi / 180
    /// The photos fanned behind a card stack's front photo, nearest first.
    let stackCards: [UIImageView] = [UIImageView(), UIImageView()]
    /// How wide a stack card's outline is, in the conversation's background colour, so photos that
    /// look alike still read as separate cards.
    static let stackOutlineWidth: CGFloat = 3
    /// The front photo's shadow over the cards behind it, shaped to the photo.
    var stackShadow: UIView { stackShadowView }
    /// The front photo's outline, drawn over its edge.
    var stackOutline: UIView { stackOutlineView }
    private let stackShadowView = StackShadowView()
    private let stackOutlineView = StackOutlineView()
    /// A card stack's "5 photos" pill, over the front photo's top-trailing corner.
    let stackCountLabel = UILabel()
    private let stackCountPill = CapsuleBlurView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    /// Keeps a reply's quote panel, which shares the top edge, clear of the count pill while it shows.
    private lazy var quoteClearOfPill = quotePanel.trailingAnchor.constraint(
        lessThanOrEqualTo: stackCountPill.leadingAnchor, constant: -Self.quoteInset
    )

    private let stack = UIStackView()
    let imageBubble = BubbleBackgroundView()
    let imageView = UIImageView()
    /// Shown over the BlurHash when an encrypted photo's bytes fail to decrypt or check out.
    let unavailableLabel = UILabel()
    /// Shows how far an outgoing photo's send has got, until it is sent or fails.
    let progressOverlay = ChatPhotoProgressOverlay()
    /// A reply's quote, drawn over the photo. A sibling of the photo rather than its subview, so it
    /// stays its own accessibility element and its tap never reaches the photo's.
    let quotePanel = ChatQuotePanelView()
    /// The caption, drawn by the same view a text message uses, so its links, mention pills, Flipcash
    /// card, taps and chrome are the text bubble's own.
    let captionBubble = LinkableBubbleView()
    /// The card of a caption with words around its Flipcash link, under the text before it: the
    /// view a text message's card row uses. Hidden when the caption is not split.
    let captionCardBubble = LinkableBubbleView()
    /// The text after a split caption's card. Hidden when the caption is not split.
    let captionTrailingBubble = LinkableBubbleView()
    /// An emoji-only caption: the view a text message of one to three emoji uses, drawn bare and
    /// enlarged with no bubble. Mutually exclusive with ``captionBubble``.
    let captionEmoji = ChatBubbleView()
    let reactionRow = ReactionPillRowView()
    let imageTap = UITapGestureRecognizer()

    private var imageWidthConstraint: NSLayoutConstraint!
    private var imageHeightConstraint: NSLayoutConstraint!
    /// The back cards' heights, a little under the front photo's so their turned corners stay in the frame.
    private var stackCardHeightConstraints: [NSLayoutConstraint] = []
    private var captionMaxWidthConstraint: NSLayoutConstraint!
    /// Holds a bare caption card open at the bubble's full width, as `ChatLinkMessageCell` does.
    private var captionCardWidthConstraint: NSLayoutConstraint!
    private var captionEmojiMaxWidthConstraint: NSLayoutConstraint!
    private var captionCardMaxWidthConstraint: NSLayoutConstraint!
    private var captionCardFillConstraint: NSLayoutConstraint!
    private var captionTrailingMaxWidthConstraint: NSLayoutConstraint!
    private var captionCardMessage: ChatMessage?
    /// Every view a caption can draw into, in the order they stack under the photo.
    private var captionBubbles: [LinkableBubbleView] { [captionBubble, captionCardBubble, captionTrailingBubble] }
    private var captionMessage: ChatMessage?
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
    /// Called when the viewer taps the leading "$" to pay for a reaction.
    var onReactionBoost: (() -> Void)?

    /// Fired when the viewer taps an `@handle` in the caption, with the handle it names.
    var onMentionTap: ((Username) -> Void)? {
        didSet { captionBubbles.forEach { $0.onMentionTap = onMentionTap } }
    }
    /// Fired when the viewer taps a link in the caption.
    var onOpenURL: ((URL) -> Void)? {
        didSet { captionBubbles.forEach { $0.onOpenURL = onOpenURL } }
    }
    /// Fired when the viewer taps the card the caption drew in place of its link.
    var onLinkCardTap: ((LinkCard) -> Void)? {
        didSet { captionBubbles.forEach { $0.onLinkCardTap = onLinkCardTap } }
    }
    weak var linkCardSource: (any LinkCardSource)? {
        didSet { captionBubbles.forEach { $0.linkCardSource = linkCardSource } }
    }

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

        captionBubbles.forEach { $0.isHidden = true }
        captionEmoji.isHidden = true
        // The transcript self-sizes on invalidation, so a card that grows after its preview
        // lands re-measures its row, and a link-only caption going bare re-measures its width.
        captionBubble.onCardHeightChange = { [weak self] in self?.contentView.invalidateIntrinsicContentSize() }
        for bubble in captionBubbles {
            bubble.onCardHeightChange = { [weak self] in self?.contentView.invalidateIntrinsicContentSize() }
            bubble.onBareChange = { [weak self] in
                self?.applyCaptionBareness()
                self?.contentView.invalidateIntrinsicContentSize()
            }
        }

        for (position, card) in stackCards.enumerated() {
            card.contentMode = .scaleAspectFill
            card.clipsToBounds = true
            card.layer.cornerRadius = BubbleBackgroundView.baseRadius
            card.layer.cornerCurve = .continuous
            card.backgroundColor = .secondarySystemFill
            card.layer.borderWidth = Self.stackOutlineWidth
            card.layer.borderColor = UIColor(Color.backgroundMain).cgColor
            card.isHidden = true
            card.isAccessibilityElement = false
            card.translatesAutoresizingMaskIntoConstraints = false
            card.transform = CGAffineTransform(rotationAngle: position == 0 ? -Self.stackFanAngle : Self.stackFanAngle)
        }
        stackCountLabel.font = .default(size: 13, weight: .semibold)
        stackCountLabel.textColor = .white
        stackCountLabel.translatesAutoresizingMaskIntoConstraints = false
        stackCountPill.contentView.addSubview(stackCountLabel)
        stackCountPill.clipsToBounds = true
        stackCountPill.layer.cornerCurve = .continuous
        stackCountPill.isHidden = true
        stackCountPill.isUserInteractionEnabled = false
        stackCountPill.translatesAutoresizingMaskIntoConstraints = false
        imageBubble.addSubview(stackCountPill)

        stack.axis = .vertical
        stack.spacing = Self.captionGap
        stack.addArrangedSubview(imageBubble)
        stack.addArrangedSubview(captionBubble)
        stack.addArrangedSubview(captionCardBubble)
        stack.addArrangedSubview(captionTrailingBubble)
        stack.addArrangedSubview(captionEmoji)

        // Behind the front photo, the farther card lowest.
        for card in stackCards {
            stack.insertSubview(card, at: 0)
        }
        stackShadowView.shape = { [unowned self] in imageBubble.maskingPath }
        stackShadow.isHidden = true
        stackShadow.translatesAutoresizingMaskIntoConstraints = false
        stack.insertSubview(stackShadow, belowSubview: imageBubble)
        stackOutlineView.shape = { [unowned self] in imageBubble.maskingPath }
        stackOutline.isHidden = true
        stackOutline.translatesAutoresizingMaskIntoConstraints = false
        imageBubble.insertSubview(stackOutline, aboveSubview: imageView)

        quotePanel.ground = UIColor(Color.backgroundMain).withAlphaComponent(Self.quoteGroundAlpha)
        quotePanel.isHidden = true
        quotePanel.translatesAutoresizingMaskIntoConstraints = false
        stack.addSubview(quotePanel)

        installColumn(content: stack, accessory: reactionRow)
        reactionRow.onToggle = { [weak self] emoji in self?.onReactionTap?(emoji) }
        reactionRow.onLongPress = { [weak self] emoji in self?.onReactionLongPress?(emoji) }
        reactionRow.onAdd = { [weak self] in self?.onReactionAdd?() }
        reactionRow.onBoost = { [weak self] in self?.onReactionBoost?() }

        imageWidthConstraint = imageBubble.widthAnchor.constraint(equalToConstant: 240)
        // Below required so the photo yields to the cell's self-sizing height instead of fighting it.
        imageHeightConstraint = imageBubble.heightAnchor.constraint(equalToConstant: 240)
        imageHeightConstraint.priority = UILayoutPriority(999)
        captionMaxWidthConstraint = captionBubble.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        captionEmojiMaxWidthConstraint = captionEmoji.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        captionCardWidthConstraint = captionBubble.widthAnchor.constraint(equalToConstant: 240)
        captionCardWidthConstraint.priority = .defaultHigh
        captionCardMaxWidthConstraint = captionCardBubble.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        captionCardFillConstraint = captionCardBubble.widthAnchor.constraint(equalToConstant: 240)
        captionCardFillConstraint.priority = .defaultHigh
        captionTrailingMaxWidthConstraint = captionTrailingBubble.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        reactionRowWidthConstraint = reactionRow.widthAnchor.constraint(equalToConstant: 240)

        NSLayoutConstraint.activate([
            imageWidthConstraint,
            imageHeightConstraint,
            captionMaxWidthConstraint,
            captionEmojiMaxWidthConstraint,
            captionCardMaxWidthConstraint,
            captionTrailingMaxWidthConstraint,
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

            stackCountLabel.topAnchor.constraint(equalTo: stackCountPill.contentView.topAnchor, constant: 4),
            stackCountLabel.bottomAnchor.constraint(equalTo: stackCountPill.contentView.bottomAnchor, constant: -4),
            stackCountLabel.leadingAnchor.constraint(equalTo: stackCountPill.contentView.leadingAnchor, constant: 10),
            stackCountLabel.trailingAnchor.constraint(equalTo: stackCountPill.contentView.trailingAnchor, constant: -10),
            stackCountPill.trailingAnchor.constraint(equalTo: imageBubble.trailingAnchor, constant: -Self.progressInset),
            stackCountPill.topAnchor.constraint(equalTo: imageBubble.topAnchor, constant: Self.progressInset),

            quotePanel.topAnchor.constraint(equalTo: imageBubble.topAnchor, constant: Self.quoteInset),
            quotePanel.leadingAnchor.constraint(equalTo: imageBubble.leadingAnchor, constant: Self.quoteInset),
            quotePanel.widthAnchor.constraint(lessThanOrEqualTo: imageBubble.widthAnchor, multiplier: Self.quoteMaxWidthFraction),
            quotePanel.bottomAnchor.constraint(lessThanOrEqualTo: imageBubble.bottomAnchor, constant: -Self.quoteInset),
        ])
        for overlay in [stackShadow, stackOutline] {
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: imageBubble.topAnchor),
                overlay.leadingAnchor.constraint(equalTo: imageBubble.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: imageBubble.trailingAnchor),
                overlay.bottomAnchor.constraint(equalTo: imageBubble.bottomAnchor),
            ])
        }
        for card in stackCards {
            let height = card.heightAnchor.constraint(equalToConstant: 240)
            stackCardHeightConstraints.append(height)
            NSLayoutConstraint.activate([
                card.centerXAnchor.constraint(equalTo: imageBubble.centerXAnchor),
                card.centerYAnchor.constraint(equalTo: imageBubble.centerYAnchor),
                card.widthAnchor.constraint(equalTo: imageBubble.widthAnchor),
                height,
            ])
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Scopes the row's touch target to the photo, caption, and pills, like the cash card: the cell
    /// spans the full transcript width, and a tap beside the photo should not land on it.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        stack.convert(stack.bounds, to: self).contains(point)
            || (!reactionRow.isHidden && reactionRow.convert(reactionRow.bounds, to: self).contains(point))
            || authorAvatarContains(point)
    }

    /// A bare caption card runs to the full bubble width, as in a text row; a person card hugs its
    /// own width, as `ChatLinkMessageCell` decides.
    private func applyCaptionBareness() {
        captionCardWidthConstraint.isActive = captionBubble.isBare
            && ChatLinkMessageCell.cardFillsWidth(captionMessage?.linkPreview?.card)
        captionCardFillConstraint.isActive = captionCardBubble.isBare
            && ChatLinkMessageCell.cardFillsWidth(captionCardMessage?.linkPreview?.card)
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        captionMessage = nil
        captionCardMessage = nil
        captionBubbles.forEach { $0.prepareForReuse() }
        captionEmoji.isHidden = true
        captionCardWidthConstraint.isActive = false
        captionCardFillConstraint.isActive = false
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        showUnavailable(false)
        progressOverlay.bind(nil, suppressed: false, animated: false)
        drawnRowID = nil
        reactionRow.prepareForReuse()
        drawStack([])
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
    ///   - stackImages: the picked images of a stack's photos this device is sending, by message id.
    ///   - stackProgress: the send progress of each photo behind a stack's front, nil once confirmed.
    ///   - remote: where the photo downloads from, or nil until it is resolved.
    ///   - quoteThumbnail: where a quoted photo's thumbnail loads from, or nil.
    ///   - captionWidth: the width a caption's card is held to, or nil for the transcript's bubble
    ///     width. A message card sits at the cash card's width, as in a text row.
    public func configure(
        with message: ChatMessage,
        maxWidth: CGFloat,
        localImage: UIImage?,
        progress: ChatPhotoSendProgress? = nil,
        stackImages: [String: UIImage] = [:],
        stackProgress: [ChatPhotoSendProgress?] = [],
        remote: ChatMediaLocation?,
        quoteThumbnail: ChatMediaLocation? = nil,
        authorImageData: Data? = nil,
        captionWidth: CGFloat? = nil
    ) {
        guard case .media(let media) = message.content else { return }
        imageBubble.accessibilityValue = message.sentAt?.formattedChatMessageTime()
        let blurhashOnly = Self.isBlurhashOnly(media, canReact: message.canReact)
        self.blurhashOnly = blurhashOnly

        let size = ChatMediaBubbleSizing.size(
            imageWidth: Double(media.width),
            imageHeight: Double(media.height),
            maxWidth: Double(maxWidth)
        )
        imageHeightConstraint.constant = size.height
        layOutStackFan(frame: CGSize(width: size.width, height: size.height), isStack: media.stackPhotos.count > 1)
        // The same row losing its progress is a confirmed send, which fades; a new row starts clean.
        progressOverlay.bind(progress, behind: stackProgress, suppressed: message.isFailed, animated: drawnRowID == message.id)
        drawImage(
            for: message.id,
            blobID: media.blobID,
            blurhash: media.blurhash,
            localImage: blurhashOnly ? nil : localImage,
            remote: blurhashOnly ? nil : remote,
            size: CGSize(width: size.width, height: size.height)
        )
        imageTap.isEnabled = !blurhashOnly && !message.isFailed
        drawStack(media.stackPhotos, localImages: blurhashOnly ? [:] : stackImages)

        let caption = media.caption.flatMap { $0.isEmpty ? nil : $0 }
        let emojiCaption = caption != nil && media.captionIsEmojiOnly
        let captionMax = captionWidth ?? maxWidth
        // A caption split around its Flipcash card draws the text path's rows: the words before the
        // card, the card, the words after it. Only the card is held to the card's width.
        let splitRows = emojiCaption ? [] : media.captionRows
        let isSplit = !splitRows.isEmpty
        captionMaxWidthConstraint.constant = isSplit ? maxWidth : captionMax
        captionCardWidthConstraint.constant = captionMax
        captionCardMaxWidthConstraint.constant = captionMax
        captionCardFillConstraint.constant = captionMax
        captionTrailingMaxWidthConstraint.constant = maxWidth
        captionEmojiMaxWidthConstraint.constant = maxWidth
        captionBubbles.forEach { $0.prepareForReuse(); $0.isHidden = true }
        captionMessage = nil
        captionCardMessage = nil
        captionEmoji.isHidden = true
        if isSplit {
            for (position, row) in splitRows.enumerated() {
                let isLast = position == splitRows.count - 1
                let rowMessage = ChatMessage(
                    id: message.id,
                    text: row.text,
                    sender: message.sender,
                    joinsBubbleAbove: true,
                    joinsBubbleBelow: isLast ? message.joinsBubbleBelow : true,
                    linkPreview: row.preview,
                    isEdited: isLast && message.isEdited
                )
                let bubble: LinkableBubbleView
                switch row.kind {
                case .leadingText:
                    bubble = captionBubble
                    captionMessage = rowMessage
                case .card:
                    bubble = captionCardBubble
                    captionCardMessage = rowMessage
                case .trailingText:
                    bubble = captionTrailingBubble
                }
                bubble.configure(with: rowMessage)
                bubble.isHidden = false
            }
            captionCardWidthConstraint.isActive = false
            applyCaptionBareness()
        } else if let caption {
            // The caption is a text message's body in the same place: an emoji-only one draws as the
            // text path's bare emoji, anything else through the text bubble, from a text row of its
            // own words, preview, and bubble-run position.
            let captionRow = ChatMessage(
                id: message.id,
                text: caption,
                sender: message.sender,
                joinsBubbleAbove: !emojiCaption,
                joinsBubbleBelow: message.joinsBubbleBelow,
                isEmojiOnly: emojiCaption,
                linkPreview: emojiCaption ? nil : media.captionPreview,
                isEdited: message.isEdited
            )
            captionMessage = captionRow
            if emojiCaption {
                captionBubble.isHidden = true
                captionEmoji.configure(with: captionRow)
                captionEmoji.isHidden = false
                captionCardWidthConstraint.isActive = false
            } else {
                captionBubble.configure(with: captionRow)
                captionBubble.isHidden = false
                applyCaptionBareness()
            }
        }
        // A failed row's whole column is the retry target, so the caption's link taps stand down.
        captionBubbles.forEach { $0.isUserInteractionEnabled = !message.isFailed }

        let isFromSelf = message.sender == .me
        let fill = BubbleBackgroundView.fill(isFromSelf: isFromSelf)
        imageBubble.apply(
            fill: fill,
            radii: BubbleBackgroundView.radii(
                isFromSelf: isFromSelf,
                groupedAbove: message.joinsBubbleAbove,
                groupedBelow: (caption != nil && !emojiCaption) || message.joinsBubbleBelow
            ),
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
        reactionRow.configure(pills: blurhashOnly ? [] : message.reactions, canReact: message.canReact && !blurhashOnly, canBoost: message.canBoost)
        reactionRow.isHidden = blurhashOnly
        updateColumn(for: message, authorImageData: authorImageData)
    }

    /// Fans the photos after the front one behind it and counts the set, or clears both for a photo
    /// drawn alone. A card behind shows its picked image while this device sends it, the photo once
    /// it is in the memory cache, else its BlurHash: only its edges show, so it never downloads on
    /// its own.
    private func drawStack(_ photos: [ChatMediaStackPhoto], localImages: [String: UIImage] = [:]) {
        let behind = photos.dropFirst()
        for (position, card) in stackCards.enumerated() {
            guard position < behind.count else {
                card.isHidden = true
                card.image = nil
                continue
            }
            let photo = behind[behind.startIndex + position]
            card.image = localImages[photo.messageID]
                ?? (photo.isRedacted ? nil : photo.blobID.flatMap(ChatMediaImageSource.cachedImage(blobID:)))
                ?? BlurHashCache.shared.image(for: photo.blurhash)
            card.isHidden = false
        }
        stackCountPill.isHidden = photos.count < 2
        stackShadow.isHidden = photos.count < 2
        stackOutline.isHidden = photos.count < 2
        quoteClearOfPill.isActive = photos.count >= 2
        stackCountLabel.text = photos.count < 2 ? nil : ChatMediaStrings.stackCount(photos.count)
        imageBubble.accessibilityLabel = photos.count < 2 ? "Photo" : ChatMediaStrings.stackCount(photos.count)
    }

    /// Fits a stack in the frame a single photo takes, so its row keeps a photo's height and gaps:
    /// the front photo keeps the full height and narrows, centered, leaving room either side for the
    /// turned cards, which keep the timestamp reveal and avatar gutter clear.
    private func layOutStackFan(frame: CGSize, isStack: Bool) {
        let fan = isStack ? Self.stackFan(in: frame, angle: Self.stackFanAngle) : nil
        imageWidthConstraint.constant = fan?.photo.width ?? frame.width
        for height in stackCardHeightConstraints { height.constant = fan?.card.height ?? frame.height }
        let inset = (frame.width - (fan?.photo.width ?? frame.width)) / 2
        stack.isLayoutMarginsRelativeArrangement = fan != nil
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)
    }

    /// The front photo's and each back card's size for a stack in `frame`: both as wide as the
    /// front, the photo at the full height, and a card short enough that, turned by `angle`, its
    /// corners just meet the frame's edges. Nil when the frame is too narrow or flat to fan.
    static func stackFan(in frame: CGSize, angle: CGFloat) -> (photo: CGSize, card: CGSize)? {
        let cosine = cos(angle), sine = abs(sin(angle))
        let determinant = cosine * cosine - sine * sine
        guard frame.width > 0, frame.height > 0, determinant > 0 else { return nil }
        let width = (frame.width * cosine - frame.height * sine) / determinant
        let cardHeight = (frame.height * cosine - frame.width * sine) / determinant
        guard width > 0, cardHeight > 0 else { return nil }
        return (CGSize(width: width, height: frame.height), CGSize(width: width, height: cardHeight))
    }

    private func drawImage(for rowID: String, blobID: BlobID?, blurhash: String?, localImage: UIImage?, remote: ChatMediaLocation?, size: CGSize) {
        let isSameRow = drawnRowID == rowID
        drawnRowID = rowID
        if !isSameRow { showUnavailable(false) }
        // The upload is flattened onto white (`ChatMediaEncoder.render`); a local image keeps its
        // alpha, so it needs the same white under it to match what everyone else sees.
        imageView.backgroundColor = localImage == nil ? nil : .white

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
        let bubbles: [(frame: CGRect, shape: UIBezierPath)] = [
            (imageBubble.frame, imageBubble.maskingPath),
            (captionBubble.frame, captionBubble.maskingPath),
            (captionCardBubble.frame, captionCardBubble.maskingPath),
            (captionTrailingBubble.frame, captionTrailingBubble.maskingPath),
        ]
        let hidden = [imageBubble.isHidden, captionBubble.isHidden, captionCardBubble.isHidden, captionTrailingBubble.isHidden]
        for (bubble, hidden) in zip(bubbles, hidden) where !hidden {
            bubble.shape.apply(CGAffineTransform(translationX: bubble.frame.minX, y: bubble.frame.minY))
            path.append(bubble.shape)
        }
        return path
    }

    func flashAttention(startedAt start: CFTimeInterval) {
        imageBubble.flashAttention(startedAt: start)
        for bubble in captionBubbles where !bubble.isHidden { bubble.flashAttention(startedAt: start) }
        if !captionEmoji.isHidden { captionEmoji.flashAttention(startedAt: start) }
    }
}
#endif

/// The soft shadow a card stack's front photo casts on the cards behind it, following `shape`.
private final class StackShadowView: UIView {
    var shape: (() -> UIBezierPath)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.7
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = shape?().cgPath
    }
}

/// A card stack's front-photo outline in the conversation's background colour, following `shape`.
/// The stroke straddles the shape and the bubble's mask clips its outer half, so it is drawn at
/// twice the visible width.
private final class StackOutlineView: UIView {
    var shape: (() -> UIBezierPath)?
    private let stroke = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        stroke.fillColor = UIColor.clear.cgColor
        stroke.strokeColor = UIColor(Color.backgroundMain).cgColor
        stroke.lineWidth = ChatMediaCell.stackOutlineWidth * 2
        stroke.actions = ["path": NSNull()]
        layer.addSublayer(stroke)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        stroke.frame = bounds
        stroke.path = shape?().cgPath
    }
}

/// A blur that rounds itself to a capsule whenever its own height settles.
private final class CapsuleBlurView: UIVisualEffectView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
