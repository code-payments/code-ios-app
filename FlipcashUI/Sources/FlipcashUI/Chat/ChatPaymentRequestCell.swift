//
//  ChatPaymentRequestCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// A recycled cell for a group payment request widget: the request card in bubble chrome. A tap on
/// the row opens the request's details.
public final class ChatPaymentRequestCell: ChatColumnCell {

    public static let reuseIdentifier = "ChatPaymentRequestCell"

    /// The designed card width; a narrower transcript caps it.
    static let designedWidth: CGFloat = 290

    private static let padding: CGFloat = 16

    private let card = BubbleBackgroundView()
    private let reactionRow = ReactionPillRowView()
    private let content: any UIView & UIContentView
    private var cardWidthConstraint: NSLayoutConstraint!
    private var reactionRowWidthConstraint: NSLayoutConstraint!
    private var shown: ChatPaymentRequestContent.Card??

    public override init(frame: CGRect) {
        // Made with the content type `draw` sets later: a hosting content view traps when handed a
        // configuration of a different content type.
        content = UIHostingConfiguration { PaymentRequestCard(content: nil) }
            .margins(.all, Self.padding)
            .makeContentView()
        super.init(frame: frame)

        card.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        installColumn(content: card, accessory: reactionRow)
        reactionRow.onToggle = { [weak self] emoji in self?.onReactionTap?(emoji) }
        reactionRow.onLongPress = { [weak self] emoji in self?.onReactionLongPress?(emoji) }
        reactionRow.onAdd = { [weak self] in self?.onReactionAdd?() }
        reactionRow.onBoost = { [weak self] in self?.onReactionBoost?() }

        cardWidthConstraint = card.widthAnchor.constraint(equalToConstant: Self.designedWidth)
        reactionRowWidthConstraint = reactionRow.widthAnchor.constraint(equalToConstant: Self.designedWidth)
        NSLayoutConstraint.activate([
            cardWidthConstraint,
            reactionRowWidthConstraint,
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Fired when the viewer taps a reaction pill — the argument is the toggled emoji.
    var onReactionTap: ((String) -> Void)?
    /// Fired on a long-press of a reaction pill, to open the reactors sheet scoped to that emoji.
    var onReactionLongPress: ((String) -> Void)?
    /// Fired when the trailing "+" is tapped, to open the picker.
    var onReactionAdd: (() -> Void)?
    /// Called when the viewer taps the leading "$" to pay for a reaction.
    var onReactionBoost: (() -> Void)?

    /// Scopes the row's touch target to the card, not the full-width cell.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        card.convert(card.bounds, to: self).contains(point) || reactionRow.convert(reactionRow.bounds, to: self).contains(point)
            || authorAvatarContains(point)
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        shown = nil
        reactionRow.prepareForReuse()
    }

    /// - Parameter maxWidth: the widest the card may be; the designed width caps it from above.
    public func configure(with message: ChatMessage, maxWidth: CGFloat, authorImageData: Data? = nil) {
        guard case .paymentRequest(let request) = message.content else { return }
        let width = min(Self.designedWidth, maxWidth)
        cardWidthConstraint.constant = width
        reactionRowWidthConstraint.constant = width

        card.apply(
            fill: BubbleBackgroundView.fill(isFromSelf: message.sender == .me),
            radii: BubbleBackgroundView.radii(
                isFromSelf: message.sender == .me,
                groupedAbove: message.joinsBubbleAbove,
                groupedBelow: message.joinsBubbleBelow
            ),
            identity: message.id
        )
        reactionRow.layoutWidth = width
        reactionRow.hugsTrailingEdge = message.sender == .me
        reactionRow.configure(pills: message.reactions, canReact: message.canReact, canBoost: message.canBoost)
        updateColumn(for: message, authorImageData: authorImageData)

        // A reconfigure in place (a grouping or reaction change) keeps the card it drew.
        guard shown != .some(request.card) else { return }
        shown = .some(request.card)
        content.configuration = UIHostingConfiguration { PaymentRequestCard(content: request.card) }
            .margins(.all, Self.padding)
        accessibilityTraits.insert(.button)
    }
}

extension ChatPaymentRequestCell: BubbleCarrying {
    /// The card, not the cell: the cell spans the full row.
    var liftPreviewView: UIView { card }
    var liftPreviewMaskingPath: UIBezierPath? { card.maskingPath }

    func flashAttention(startedAt start: CFTimeInterval) { card.flashAttention(startedAt: start) }
}
#endif
