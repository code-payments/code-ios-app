//
//  LinkCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// The card slot in a link bubble: one frame, one set of proportions, whichever kind of card the
/// message carries.
///
/// The kinds are laid out by the same rectangle on purpose. A transcript mixing a cash link and
/// a token link should read as one column of cards rather than two card sizes, and the bubble above
/// it switches on whether there is a card at all — not on which one. A group card has the same
/// width, and takes the same proportions as its minimum rather than its size: it carries a title,
/// a member count, a rule and a button, which run taller than the bill and grow with Dynamic Type.
///
/// Every kind is built once and kept, hidden, rather than swapped in per dequeue: this sits in a
/// recycled row, and a transcript that alternates kinds would otherwise allocate a card per scroll.
///
/// This is also where a card's lookup lives. It paints whatever the source already knows, shimmers
/// if that is nothing, and then follows the source's stream for as long as the row holds this card.
@MainActor
final class LinkCardView: UIView {

    /// The proportions of the wallet's bill: 224pt of card across 328pt of usable width — its own
    /// height at full width less two screen insets on a 375pt phone. A chat bubble is a good deal
    /// narrower than that, and scaling the height with the width is what keeps a card a card there
    /// rather than a tall panel.
    private static let aspectRatio: CGFloat = 224.0 / 328.0

    private let cashView = LinkCashCardView()
    private let tokenView = LinkTokenCardView()
    private let groupView = LinkGroupCardView()

    /// Height at exactly the proportions, for a cash or token card.
    private var fixedHeight: NSLayoutConstraint!
    /// Height at least the proportions, for a group card, whose content may need more.
    private var minimumHeight: NSLayoutConstraint!
    /// Lets the group card's content set the slot's height. Only while a group card is showing: a
    /// hidden view still takes part in layout, and the group content's own height would otherwise
    /// hold every other kind of card open past its proportions.
    private var groupBottom: NSLayoutConstraint!

    /// The subscription to the card currently shown. Cancelled before every reconfigure and on
    /// reuse: cells recycle, and a task outliving its card would paint one link's answer onto
    /// another link's row.
    private var subscription: Task<Void, Never>?

    /// Called when a group card's "Start Chatting" button is tapped.
    var onGroupStart: (() -> Void)?

    /// Called when an answer arriving after ``configure(with:source:)`` changes the card's height,
    /// so the row holding it can be measured again. Only a group card's height follows its content.
    var onHeightChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        for card in [cashView, tokenView] as [UIView] {
            card.translatesAutoresizingMaskIntoConstraints = false
            card.isHidden = true
            addSubview(card)
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: topAnchor),
                card.bottomAnchor.constraint(equalTo: bottomAnchor),
                card.leadingAnchor.constraint(equalTo: leadingAnchor),
                card.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        groupView.translatesAutoresizingMaskIntoConstraints = false
        groupView.isHidden = true
        groupView.onStart = { [weak self] in self?.onGroupStart?() }
        groupView.onHeightChange = { [weak self] in self?.onHeightChange?() }
        addSubview(groupView)
        groupBottom = groupView.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            groupView.topAnchor.constraint(equalTo: topAnchor),
            groupView.leadingAnchor.constraint(equalTo: leadingAnchor),
            groupView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // The card's proportions, not its size. One of the two is always live, including while
        // collapsed: a card with no width has no height either, so this stays consistent with the
        // bubble's zero-size constraints rather than fighting them.
        fixedHeight = heightAnchor.constraint(equalTo: widthAnchor, multiplier: Self.aspectRatio)
        minimumHeight = heightAnchor.constraint(greaterThanOrEqualTo: widthAnchor, multiplier: Self.aspectRatio)
        fixedHeight.isActive = true
    }

    /// Switches the slot between the fixed proportions of a cash or token card and the minimum of a
    /// group card.
    private func setGroupShown(_ shown: Bool) {
        groupView.isHidden = !shown
        guard groupBottom.isActive != shown else { return }
        if shown {
            fixedHeight.isActive = false
            minimumHeight.isActive = true
            groupBottom.isActive = true
        } else {
            groupBottom.isActive = false
            minimumHeight.isActive = false
            fixedHeight.isActive = true
        }
    }

    func prepareForReuse() {
        subscription?.cancel()
        subscription = nil
        cashView.prepareForReuse()
        tokenView.prepareForReuse()
        groupView.prepareForReuse()
        setGroupShown(false)
    }

    /// Shows `card` and keeps it up to date from `source`.
    ///
    /// Paints once from ``LinkCardSource/known(_:)`` — the answer if the link has been looked at
    /// this session, the unresolved card under a shimmer if it has not — and then subscribes either
    /// way. A known card subscribes too, because what arrives later is not only the first answer: a
    /// claim settling on this device, or the re-ask of a link still showing as claimable, reaches
    /// the row through the same stream. Its first element repeats what is already painted, which
    /// costs a redraw of values that have not changed.
    ///
    /// With no source the card paints unresolved and asks nothing, which is what a preview or a
    /// test that does not care about resolution gets.
    func configure(with card: LinkCard, source: (any LinkCardSource)?) {
        subscription?.cancel()
        subscription = nil

        let known = source?.known(card)
        show(card, state: known, loading: known == nil && source != nil)

        guard let source else { return }
        // Subscribed here rather than inside the task: a task body does not run until the caller
        // suspends, and an answer that lands in that gap would be yielded to nobody.
        let states = source.states(for: card)
        subscription = Task { [weak self] in
            for await state in states {
                guard let self, !Task.isCancelled else { return }
                if show(card, state: state, loading: false) { onHeightChange?() }
            }
        }
    }

    /// Hands `state` to the view for `card`'s kind. A state of another kind, or none at all, is
    /// the unresolved card: the source keys each kind separately, so this is unreachable, and
    /// drawing the link's own identity is the right answer if it ever is reached.
    /// - Returns: whether the card's height may have changed.
    @discardableResult
    private func show(_ card: LinkCard, state: LinkCard.State?, loading: Bool) -> Bool {
        switch card {
        case .cash:
            cashView.isHidden = false
            tokenView.isHidden = true
            setGroupShown(false)
            cashView.configure(with: Self.cashState(state), loading: loading)
            return false

        case .token(let token):
            cashView.isHidden = true
            tokenView.isHidden = false
            setGroupShown(false)
            tokenView.configure(with: token, state: Self.tokenState(state), loading: loading)
            return false

        case .group:
            cashView.isHidden = true
            tokenView.isHidden = true
            setGroupShown(true)
            return groupView.configure(with: Self.groupState(state), loading: loading)
        }
    }

    private static func cashState(_ state: LinkCard.State?) -> LinkCard.Cash.State {
        switch state {
        case .cash(let cash):       cash
        case .token, .group, nil:   .unresolved
        }
    }

    private static func tokenState(_ state: LinkCard.State?) -> LinkCard.Token.State {
        switch state {
        case .token(let token):     token
        case .cash, .group, nil:    .unresolved
        }
    }

    /// Nil while nothing is known, which the group card draws as its shimmer when a lookup is out.
    private static func groupState(_ state: LinkCard.State?) -> LinkCard.Group.State? {
        switch state {
        case .group(let group):     group
        case .cash, .token, nil:    nil
        }
    }
}
#endif
