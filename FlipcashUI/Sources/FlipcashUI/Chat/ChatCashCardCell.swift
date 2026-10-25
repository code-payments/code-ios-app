//
//  ChatCashCardCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore
import Kingfisher

/// A recycled cell for a cash payment row: a card (shared `BubbleBackgroundView` chrome) with the
/// token name + optional coin icon in the top-left and a centered "You sent / You received" caption
/// above the amount, hosted in a `ChatColumnCell`. The card's width is supplied by
/// the owner, as `ChatMessageCell`/`ChatLinkMessageCell` take theirs, so it tracks the transcript
/// width instead of a fixed footprint. `configure(with:maxWidth:)` is the only input; the strings,
/// and icon URL all arrive on the `ChatMessage`.
public final class ChatCashCardCell: ChatColumnCell {

    public static let reuseIdentifier = "ChatCashCardCell"

    /// A cash card's fixed height; a group card sizes to its lines instead. Width tracks `maxWidth`.
    static let cardHeight: CGFloat = 170

    private let card = BubbleBackgroundView()
    private let reactionRow = ReactionPillRowView()
    private let coinIcon = UIImageView()
    private let tokenLabel = UILabel()
    private let captionLabel = UILabel()
    private let amountLabel = UILabel()
    private let eachLabel = UILabel()
    // A card in a group carries its token under the amount and who was paid at its foot, instead
    // of the token in the top-left corner.
    private let tokenRow = UIStackView()
    private let centerCoinIcon = UIImageView()
    private let centerTokenLabel = UILabel()
    private let centerTokenRow = UIStackView()
    private let recipientsLabel = UILabel()
    private let centerStack = UIStackView()
    private var cardWidthConstraint: NSLayoutConstraint!
    // A cash card is a fixed height with its lines centred; a group card's four or five lines size
    // it instead, so each set is active for one kind only.
    private var cashCardConstraints: [NSLayoutConstraint] = []
    private var groupCardConstraints: [NSLayoutConstraint] = []
    private var reactionRowWidthConstraint: NSLayoutConstraint!

    /// Dim the card while pressed so the tap-to-open-currency-info affordance reads as a button.
    /// Driven by the collection view's selection machinery (`shouldHighlightItemAt`), not a gesture.
    public override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: 0.15) {
                self.card.alpha = self.isHighlighted ? 0.6 : 1
            }
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)

        card.translatesAutoresizingMaskIntoConstraints = false

        configureCircle(coinIcon, diameter: 13)
        tokenLabel.font = .default(size: 12, weight: .bold)
        tokenLabel.textColor = UIColor.white.withAlphaComponent(0.5)

        tokenRow.addArrangedSubview(coinIcon)
        tokenRow.addArrangedSubview(tokenLabel)
        tokenRow.spacing = 4
        tokenRow.alignment = .center
        tokenRow.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(tokenRow)

        captionLabel.font = .default(size: 12, weight: .bold)
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.5)

        amountLabel.font = .default(size: 38, weight: .bold)
        amountLabel.textColor = .white
        amountLabel.numberOfLines = 1
        amountLabel.adjustsFontSizeToFitWidth = true
        amountLabel.minimumScaleFactor = 0.5
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        eachLabel.font = .default(size: 12, weight: .bold)
        eachLabel.textColor = UIColor.white.withAlphaComponent(0.5)

        configureCircle(centerCoinIcon, diameter: 20)
        centerTokenLabel.font = .default(size: 12, weight: .bold)
        centerTokenLabel.textColor = .white
        centerTokenRow.addArrangedSubview(centerCoinIcon)
        centerTokenRow.addArrangedSubview(centerTokenLabel)
        centerTokenRow.spacing = 6
        centerTokenRow.alignment = .center

        recipientsLabel.font = .default(size: 12, weight: .bold)
        recipientsLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        recipientsLabel.lineBreakMode = .byTruncatingMiddle
        recipientsLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(recipientsLabel)

        [captionLabel, amountLabel, eachLabel, centerTokenRow].forEach(centerStack.addArrangedSubview)
        centerStack.axis = .vertical
        centerStack.spacing = 4
        centerStack.alignment = .center
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(centerStack)

        installColumn(content: card, accessory: reactionRow)
        reactionRow.onToggle = { [weak self] emoji in self?.onReactionTap?(emoji) }
        reactionRow.onLongPress = { [weak self] emoji in self?.onReactionLongPress?(emoji) }
        reactionRow.onAdd = { [weak self] in self?.onReactionAdd?() }
        reactionRow.onBoost = { [weak self] in self?.onReactionBoost?() }

        // Below required so the card height yields to the cell's self-sizing height instead of fighting it.
        let cardHeight = card.heightAnchor.constraint(equalToConstant: Self.cardHeight)
        cardHeight.priority = UILayoutPriority(999)

        cashCardConstraints = [
            cardHeight,
            centerStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ]
        groupCardConstraints = [
            centerStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            recipientsLabel.topAnchor.constraint(equalTo: centerStack.bottomAnchor, constant: 24),
        ]

        cardWidthConstraint = card.widthAnchor.constraint(equalToConstant: 232)
        reactionRowWidthConstraint = reactionRow.widthAnchor.constraint(equalToConstant: 232)

        NSLayoutConstraint.activate([
            cardWidthConstraint,
            reactionRowWidthConstraint,

            tokenRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 11),
            tokenRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),

            centerStack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            centerStack.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 8),

            recipientsLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            recipientsLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            recipientsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 16),
            recipientsLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),
            centerStack.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 16),
            centerStack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),
        ])
        NSLayoutConstraint.activate(cashCardConstraints)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Scopes the row's touch target to the card, not the cell. The cell spans the full transcript
    /// width, so without this the selection machinery opens currency info from a tap in the dead
    /// space beside the card — the same reason the retry gesture on text rows hugs the bubble.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        card.convert(card.bounds, to: self).contains(point) || reactionRow.convert(reactionRow.bounds, to: self).contains(point)
            || authorAvatarContains(point)
    }

    /// Fired when the viewer taps a reaction pill — the argument is the toggled emoji.
    var onReactionTap: ((String) -> Void)?
    /// Fired on a long-press of a reaction pill, to open the reactors sheet scoped to that emoji.
    var onReactionLongPress: ((String) -> Void)?
    /// Fired when the trailing "+" is tapped, to open the picker.
    var onReactionAdd: (() -> Void)?
    /// Called when the viewer taps the leading "$" to pay for a reaction.
    var onReactionBoost: (() -> Void)?

    private func configureCircle(_ imageView: UIImageView, diameter: CGFloat) {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = diameter / 2
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: diameter),
            imageView.heightAnchor.constraint(equalToConstant: diameter),
        ])
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        coinIcon.kf.cancelDownloadTask()
        coinIcon.image = nil
        centerCoinIcon.kf.cancelDownloadTask()
        centerCoinIcon.image = nil
        reactionRow.prepareForReuse()
    }

    /// - Parameter maxWidth: the card's width, in points. The owner derives it from the collection
    ///   view's width: 0.64 of the row between the column insets, matching Android's cash card.
    public func configure(with message: ChatMessage, maxWidth: CGFloat, authorImageData: Data? = nil) {
        guard case .cash(let cash) = message.content else { return }
        cardWidthConstraint.constant = maxWidth
        reactionRowWidthConstraint.constant = maxWidth
        tokenLabel.text = cash.token
        captionLabel.text = cash.group?.caption ?? ChatCashContent.caption(isFromSelf: message.sender == .me, isTip: cash.isTip)
        amountLabel.text = cash.amount
        eachLabel.text = cash.group?.each
        eachLabel.isHidden = cash.group?.each == nil
        amountLabel.accessibilityValue = message.sentAt?.formattedChatMessageTime()

        coinIcon.isHidden = cash.iconURL == nil
        coinIcon.kf.setImage(with: cash.iconURL)
        let isGroup = cash.group != nil
        tokenRow.isHidden = isGroup
        centerTokenRow.isHidden = !isGroup
        centerTokenLabel.text = cash.token
        centerCoinIcon.isHidden = cash.iconURL == nil
        if isGroup { centerCoinIcon.kf.setImage(with: cash.iconURL) }
        recipientsLabel.text = cash.group?.recipients
        recipientsLabel.isHidden = !isGroup
        NSLayoutConstraint.deactivate(isGroup ? cashCardConstraints : groupCardConstraints)
        NSLayoutConstraint.activate(isGroup ? groupCardConstraints : cashCardConstraints)
        centerStack.setCustomSpacing(isGroup ? 12 : 4, after: captionLabel)
        centerStack.setCustomSpacing(8, after: eachLabel)

        card.apply(
            fill: BubbleBackgroundView.fill(isFromSelf: message.sender == .me),
            radii: BubbleBackgroundView.radii(
                isFromSelf: message.sender == .me,
                groupedAbove: message.joinsBubbleAbove,
                groupedBelow: message.joinsBubbleBelow
            ),
            identity: message.id
        )
        reactionRow.layoutWidth = maxWidth
        reactionRow.hugsTrailingEdge = message.sender == .me
        reactionRow.configure(pills: message.reactions, canReact: message.canReact, canBoost: message.canBoost)
        updateColumn(for: message, authorImageData: authorImageData)

        // Resting alpha lives here, not just in prepareForReuse: an in-place reconfigure (a new
        // message flipping this row's grouping) re-runs configure without prepareForReuse, so this is
        // the single place that restores the press dim to match the current highlight state.
        card.alpha = isHighlighted ? 0.6 : 1
    }
}

extension ChatCashCardCell: BubbleCarrying {
    /// The card, not the cell: the cell spans the full row, so lifting it would raise a
    /// full-width rectangle out of the transcript.
    var liftPreviewView: UIView { card }
    var liftPreviewMaskingPath: UIBezierPath? { card.maskingPath }

    func flashAttention(startedAt start: CFTimeInterval) { card.flashAttention(startedAt: start) }
}

#Preview("Cash cards") {
    let layout = UICollectionViewFlowLayout()
    layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
    layout.minimumLineSpacing = 4

    let samples: [ChatMessage] = [
        ChatMessage(id: "1", content: .cash(ChatCashContent(amount: "$5.00", token: "Cash")), sender: .me),
        ChatMessage(id: "2", content: .cash(ChatCashContent(amount: "$12.50", token: "Cash")), sender: .other),
        ChatMessage(id: "3", content: .cash(ChatCashContent(
            amount: "$1.00", token: "Cash",
            group: .init(caption: "You sent", each: "~$0.33 each", recipients: "to Alex Morgan and 2 Others")
        )), sender: .me),
        ChatMessage(id: "4", content: .cash(ChatCashContent(
            amount: "$6.00", token: "Cash",
            group: .init(caption: "Alex sent", each: "$1.00 each", recipients: "to You and 5 Others")
        )), sender: .other),
    ]

    return ChatCashCardCellPreviewController(messages: samples, layout: layout)
}

private final class ChatCashCardCellPreviewController: UICollectionViewController {
    private let messages: [ChatMessage]

    init(messages: [ChatMessage], layout: UICollectionViewLayout) {
        self.messages = messages
        super.init(collectionViewLayout: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = .black
        collectionView.register(ChatCashCardCell.self, forCellWithReuseIdentifier: ChatCashCardCell.reuseIdentifier)
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        messages.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChatCashCardCell.reuseIdentifier, for: indexPath) as! ChatCashCardCell
        cell.configure(with: messages[indexPath.item], maxWidth: (collectionView.bounds.width - 24) * 0.64)
        return cell
    }
}
#endif
