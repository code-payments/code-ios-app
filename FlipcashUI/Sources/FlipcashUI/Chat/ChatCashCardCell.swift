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

/// A recycled cell for a cash payment row: a card (shared `BubbleBackgroundView` chrome) with its
/// lines centred top to bottom — caption, amount, the total on a group send to two or more, the
/// token's icon and name, and who was on the other side — hosted in a `ChatColumnCell`. The card's
/// width is supplied by the owner, as `ChatMessageCell`/`ChatLinkMessageCell` take theirs, so it
/// tracks the transcript width; its height follows its lines. `configure(with:maxWidth:)` is the
/// only input; the strings and icon URL all arrive on the `ChatMessage`.
public final class ChatCashCardCell: ChatColumnCell {

    public static let reuseIdentifier = "ChatCashCardCell"

    private static let amountFont = UIFont.default(size: 38, weight: .bold)
    // Medium weight at half the amount's size, in the caption's colour, on the amount's line.
    private static let eachFont = UIFont.default(size: amountFont.pointSize / 2, weight: .medium)
    // The "~" before the smallest of uneven parts: the amount's weight at 70% of its size.
    private static let approximateFont = UIFont.default(size: (amountFont.pointSize * 0.7).rounded(), weight: .bold)
    /// The card's secondary lines; the Send Back footer uses it too.
    static let secondaryColor = UIColor.white.withAlphaComponent(0.5)

    // Vertical spacing, per "Spacing values" in docs/specs/cash-bubbles.md. Frame gaps, so both
    // apps give the same content the same card height.
    /// Above the caption and below the counterpart.
    private static let verticalInset: CGFloat = 16
    /// Between the caption, the money block, and the counterpart.
    private static let blockSpacing: CGFloat = 12
    /// From the amount, or the total when there is one, down to the token row.
    private static let tokenSpacing: CGFloat = 6

    private let card = BubbleBackgroundView()
    private let reactionRow = ReactionPillRowView()
    private let captionLabel = UILabel()
    private let amountLabel = UILabel()
    private let totalLabel = UILabel()
    private let coinIcon = UIImageView()
    private let tokenLabel = UILabel()
    private let tokenRow = UIStackView()
    private let counterpartLabel = UILabel()
    private let centerStack = UIStackView()
    private let sendBackRow = SendBackRowView()
    /// What this cell last drew, so a line that arrives on a card already on screen (the Send Back
    /// row, the counterpart, the token icon) can animate in while one known at first draw does not.
    private var drawn: Drawn?
    private struct Drawn {
        let id: String
        let sendBack: ChatCashContent.SendBack?
        let counterpart: String?
        let iconURL: URL?
    }
    /// The layer animation key a late-arriving line's fade runs under; read by tests.
    static let lateArrivalKey = "cashCardLateArrival"
    /// Whether the last configure faded the Send Back row in; read by tests.
    private(set) var didAnimateSendBackIn = false
    /// The counterpart line's gap to the card's foot, or to the Send Back row when one is drawn.
    private var counterpartToCardBottom: NSLayoutConstraint!
    private var counterpartToSendBackRow: NSLayoutConstraint!
    private var cardWidthConstraint: NSLayoutConstraint!
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

        captionLabel.font = .default(size: 12, weight: .bold)
        captionLabel.textColor = Self.secondaryColor

        amountLabel.font = Self.amountFont
        amountLabel.textColor = .white
        amountLabel.numberOfLines = 1
        amountLabel.adjustsFontSizeToFitWidth = true
        amountLabel.minimumScaleFactor = 0.5
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        totalLabel.font = .default(size: 12, weight: .bold)
        totalLabel.textColor = Self.secondaryColor

        configureCircle(coinIcon, diameter: 20)
        tokenLabel.font = .default(size: 12, weight: .bold)
        tokenLabel.textColor = .white
        tokenRow.addArrangedSubview(coinIcon)
        tokenRow.addArrangedSubview(tokenLabel)
        tokenRow.spacing = 6
        tokenRow.alignment = .center

        counterpartLabel.font = .default(size: 12, weight: .bold)
        counterpartLabel.textColor = Self.secondaryColor
        counterpartLabel.lineBreakMode = .byTruncatingMiddle
        counterpartLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(counterpartLabel)

        [captionLabel, amountLabel, totalLabel, tokenRow].forEach(centerStack.addArrangedSubview)
        centerStack.axis = .vertical
        centerStack.spacing = 4
        centerStack.alignment = .center
        centerStack.setCustomSpacing(Self.blockSpacing, after: captionLabel)
        centerStack.setCustomSpacing(Self.tokenSpacing, after: totalLabel)
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(centerStack)

        sendBackRow.translatesAutoresizingMaskIntoConstraints = false
        sendBackRow.addTarget(self, action: #selector(sendBackTapped), for: .touchUpInside)
        card.addSubview(sendBackRow)

        installColumn(content: card, accessory: reactionRow)
        reactionRow.onToggle = { [weak self] emoji in self?.onReactionTap?(emoji) }
        reactionRow.onLongPress = { [weak self] emoji in self?.onReactionLongPress?(emoji) }
        reactionRow.onAdd = { [weak self] in self?.onReactionAdd?() }
        reactionRow.onBoost = { [weak self] in self?.onReactionBoost?() }

        cardWidthConstraint = card.widthAnchor.constraint(equalToConstant: 232)
        reactionRowWidthConstraint = reactionRow.widthAnchor.constraint(equalToConstant: 232)

        NSLayoutConstraint.activate([
            cardWidthConstraint,
            reactionRowWidthConstraint,

            centerStack.topAnchor.constraint(equalTo: card.topAnchor, constant: Self.verticalInset),
            centerStack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            centerStack.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 16),
            centerStack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),

            counterpartLabel.topAnchor.constraint(equalTo: centerStack.bottomAnchor, constant: Self.blockSpacing),
            counterpartLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            counterpartLabel.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 16),
            counterpartLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),

            sendBackRow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            sendBackRow.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            sendBackRow.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        counterpartToCardBottom = counterpartLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Self.verticalInset)
        counterpartToSendBackRow = counterpartLabel.bottomAnchor.constraint(equalTo: sendBackRow.topAnchor, constant: -Self.verticalInset)
        counterpartToCardBottom.isActive = true
    }

    @objc private func sendBackTapped() {
        onSendBack?()
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
    /// Called when the receiver taps Send Back on a DM's opening payment.
    var onSendBack: (() -> Void)?

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
        reactionRow.prepareForReuse()
        drawn = nil
    }

    /// - Parameter maxWidth: the card's width, in points. The owner derives it from the collection
    ///   view's width: 0.64 of the row between the column insets, matching Android's cash card.
    public func configure(with message: ChatMessage, maxWidth: CGFloat, authorImageData: Data? = nil) {
        guard case .cash(let cash) = message.content else { return }
        cardWidthConstraint.constant = maxWidth
        reactionRowWidthConstraint.constant = maxWidth
        captionLabel.text = cash.lines?.caption ?? ChatCashContent.caption(isFromSelf: message.sender == .me, isTip: cash.isTip)

        let total = cash.lines?.total
        amountLabel.attributedText = Self.amountLine(cash.amount, part: cash.lines?.part)
        amountLabel.accessibilityValue = message.sentAt?.formattedChatMessageTime()
        totalLabel.text = total
        totalLabel.isHidden = total == nil
        // The total sits tight under the amount, the closest pair of lines on the card.
        centerStack.setCustomSpacing(total == nil ? Self.tokenSpacing : 0, after: amountLabel)

        // A line that arrives on a card already drawn fades in while the transcript's reflow spring
        // grows the card to fit it (send-back spec); one known at first draw appears as is.
        let previous = drawn?.id == message.id ? drawn : nil
        drawn = Drawn(id: message.id, sendBack: cash.sendBack, counterpart: cash.lines?.counterpart, iconURL: cash.iconURL)

        tokenLabel.text = cash.token
        coinIcon.isHidden = cash.iconURL == nil
        coinIcon.kf.setImage(with: cash.iconURL)
        if let previous, previous.iconURL == nil, cash.iconURL != nil { Self.fadeIn(coinIcon) }
        counterpartLabel.text = cash.lines?.counterpart
        counterpartLabel.isHidden = cash.lines == nil
        if let previous, let counterpart = cash.lines?.counterpart, previous.counterpart != counterpart {
            Self.fadeIn(counterpartLabel)
        }
        applySendBack(cash.sendBack, previous: previous)

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

    /// Fades `view`'s new content in over the reflow spring's duration, under `lateArrivalKey`.
    private static func fadeIn(_ view: UIView) {
        // An opacity animation, not a CATransition: Core Animation files a transition under its own
        // `transition` key, whatever key it is given.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = ChatMotion.reflow.duration
        view.layer.add(fade, forKey: lateArrivalKey)
    }

    /// Whether `state` arrives on a card this cell has already drawn for message `id`: the same
    /// message, a different Send Back state, and a row to show. A first draw, or a cell reused for
    /// another message, has nothing to animate from.
    static func sendBackArrivesLate(
        drawn: (id: String, state: ChatCashContent.SendBack?)?,
        id: String,
        state: ChatCashContent.SendBack?
    ) -> Bool {
        guard let drawn, drawn.id == id, let state else { return false }
        return drawn.state != state
    }

    /// Shows the Send Back row for `state`, or none. Read from the message on every configure, so a
    /// reused cell never keeps another row's spinner.
    ///
    /// A row or footer that arrives on a card already drawn (the status check resolving, a return
    /// landing) fades in while the transcript's reflow spring grows the card to fit it. One known
    /// when the card is first drawn appears with no animation.
    private func applySendBack(_ state: ChatCashContent.SendBack?, previous: Drawn?) {
        let arrivesLate = previous.map { previous in
            Self.sendBackArrivesLate(drawn: (previous.id, previous.sendBack), id: previous.id, state: state)
        } ?? false
        didAnimateSendBackIn = arrivesLate
        sendBackRow.isHidden = state == nil
        if let state { sendBackRow.apply(state) }
        if arrivesLate {
            UIView.performWithoutAnimation { sendBackRow.alpha = 0 }
            ChatMotion.reflow.animate { [sendBackRow] in sendBackRow.alpha = 1 }
        }
        // Deactivate before activating, so the two never hold the label at once.
        counterpartToCardBottom.isActive = false
        counterpartToSendBackRow.isActive = false
        (state == nil ? counterpartToCardBottom : counterpartToSendBackRow).isActive = true
    }

    /// The amount, followed by a smaller " each" when it is one person's part of a group send, and
    /// led by a smaller "~" when it is the smallest of uneven parts. One string, so the runs share
    /// a baseline and the label's auto-size shrinks them together, and "each" never wraps.
    private static func amountLine(_ amount: String, part: ChatCashContent.Lines.Part?) -> NSAttributedString {
        let line = NSMutableAttributedString()
        if part == .approximateEach {
            line.append(NSAttributedString(string: "~", attributes: [.font: approximateFont, .foregroundColor: UIColor.white]))
        }
        line.append(NSAttributedString(string: amount, attributes: [.font: amountFont, .foregroundColor: UIColor.white]))
        if part != nil {
            line.append(NSAttributedString(string: " each", attributes: [.font: eachFont, .foregroundColor: secondaryColor]))
        }
        return line
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
        ChatMessage(id: "1", content: .cash(ChatCashContent(
            amount: "$5.00", token: "Cash",
            lines: .init(caption: "You sent", counterpart: "to Noah Parker")
        )), sender: .me),
        ChatMessage(id: "2", content: .cash(ChatCashContent(
            amount: "$12.50", token: "Cash",
            lines: .init(caption: "You received", counterpart: "from Noah Parker")
        )), sender: .other),
        ChatMessage(id: "3", content: .cash(ChatCashContent(
            amount: "$1.00", token: "Cash",
            lines: .init(caption: "You sent", total: "$3.00 total", part: .each, counterpart: "to Alex Morgan and 2 others")
        )), sender: .me),
        ChatMessage(id: "4", content: .cash(ChatCashContent(
            amount: "$1.00", token: "Cash",
            lines: .init(caption: "You and 5 others received", total: "$6.00 total", part: .each, counterpart: "from Alex")
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
