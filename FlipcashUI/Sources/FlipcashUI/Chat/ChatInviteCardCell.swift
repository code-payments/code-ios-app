//
//  ChatInviteCardCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The "Your Group Is Ready" card at the head of a group the viewer is alone in: an incoming-bubble
/// card with a title, a line naming the group and a full-width Invite People button. Not a message,
/// so it has no sender, receipt or reactions. In the ``ChatInviteCardStyle/emptyState`` style it
/// drops the bubble and the sender and centres the same three parts (node 13729:642).
///
/// When the row is deleted the controller calls ``fadeOut()`` on the cell as the batch starts, so the
/// card fades (``Fade``) while the rows below slide up into its space on the batch update's spring.
public final class ChatInviteCardCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatInviteCardCell"

    /// The card's exit: a fade, with no scale.
    public enum Fade {
        public static let duration: TimeInterval = 0.2
    }

    /// Who the card is from. No shared constant names the app as a sender, so this is the one place.
    static let senderName = "Flipcash"

    /// Called when the Invite People button is tapped.
    var onInvite: (() -> Void)?

    /// Everything the fade covers: the sender's face and name travel with the bubble.
    private let fadeHost = UIView()
    private let card = BubbleBackgroundView()
    private let senderName = UILabel()
    private let senderAvatar = ChatAuthorAvatarView()
    private let content: any UIView & UIContentView
    private var widthConstraint: NSLayoutConstraint!
    /// The bubble's place: under the sender's name, past the author gutter.
    private var bubbleConstraints: [NSLayoutConstraint] = []
    /// The empty state's place: centred, clear of the header.
    private var emptyStateConstraints: [NSLayoutConstraint] = []
    private var isFading = false

    /// The empty state's widest, and how far below the header it starts (node 13729:658).
    static let emptyStateWidth: CGFloat = 338
    static let emptyStateTopInset: CGFloat = 20

    public override init(frame: CGRect) {
        // `configure` must set a configuration whose root view is this same type: a
        // UIHostingContentView traps when its root view type changes.
        content = UIHostingConfiguration {
            InviteCardContent(
                style: .incomingBubble,
                copy: ChatInviteCardCopy(style: .incomingBubble, groupName: ""),
                onInvite: {}
            )
        }
        .margins(.all, 0)
        .makeContentView()
        super.init(frame: frame)

        fadeHost.translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        contentView.addSubview(fadeHost)
        fadeHost.addSubview(card)

        // The sender line is laid out as the transcript lays out an incoming group message: the
        // name 4pt above the bubble, the face in the leading gutter beside the bubble's top.
        senderName.translatesAutoresizingMaskIntoConstraints = false
        senderName.font = .default(size: 12, weight: .medium)
        senderName.textColor = UIColor(Color.textMain.opacity(0.5))
        senderName.text = Self.senderName
        fadeHost.addSubview(senderName)
        senderAvatar.translatesAutoresizingMaskIntoConstraints = false
        senderAvatar.configureAsFlipcash()
        fadeHost.addSubview(senderAvatar)
        let bubbleLeading = ChatColumnCell.rowInset + ChatColumnCell.authorGutterWidth

        widthConstraint = card.widthAnchor.constraint(equalToConstant: ChatShareProfileCell.designedWidth)
        bubbleConstraints = [
            card.topAnchor.constraint(equalTo: senderName.bottomAnchor, constant: 4),
            card.leadingAnchor.constraint(equalTo: fadeHost.leadingAnchor, constant: bubbleLeading),
        ]
        emptyStateConstraints = [
            card.topAnchor.constraint(equalTo: fadeHost.topAnchor, constant: Self.emptyStateTopInset),
            card.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ]
        NSLayoutConstraint.activate(bubbleConstraints)
        NSLayoutConstraint.activate([
            widthConstraint,
            fadeHost.topAnchor.constraint(equalTo: contentView.topAnchor),
            fadeHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            fadeHost.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            fadeHost.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            senderName.topAnchor.constraint(equalTo: fadeHost.topAnchor),
            senderName.leadingAnchor.constraint(equalTo: fadeHost.leadingAnchor, constant: bubbleLeading),
            card.bottomAnchor.constraint(equalTo: fadeHost.bottomAnchor),
            senderAvatar.leadingAnchor.constraint(equalTo: fadeHost.leadingAnchor, constant: ChatColumnCell.rowInset),
            senderAvatar.topAnchor.constraint(equalTo: card.topAnchor),
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Scopes the touch target to the card, not the full-width cell.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        card.convert(card.bounds, to: self).contains(point)
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        resetFade()
    }

    /// - Parameter maxWidth: the widest the card may be; the Share Profile widget's width caps the
    ///   bubble, and ``emptyStateWidth`` the empty state.
    func configure(groupName: String, style: ChatInviteCardStyle = .incomingBubble, maxWidth: CGFloat) {
        let copy = ChatInviteCardCopy(style: style, groupName: groupName)
        let isEmptyState = style == .emptyState
        senderName.isHidden = isEmptyState
        senderAvatar.isHidden = isEmptyState
        NSLayoutConstraint.deactivate(isEmptyState ? bubbleConstraints : emptyStateConstraints)
        NSLayoutConstraint.activate(isEmptyState ? emptyStateConstraints : bubbleConstraints)
        widthConstraint.constant = isEmptyState
            ? min(Self.emptyStateWidth, maxWidth)
            : min(ChatShareProfileCell.designedWidth, maxWidth - ChatColumnCell.authorGutterWidth)
        // The empty state is the row's content alone: no base, wash or hairline (node 13729:642).
        card.apply(
            fill: UIColor.white.withAlphaComponent(0.02),
            radii: BubbleBackgroundView.radii(isFromSelf: false, groupedAbove: false, groupedBelow: false),
            bare: isEmptyState,
            identity: ChatItem.inviteCard(groupName: "").id
        )
        let onInvite: () -> Void = { [weak self] in self?.onInvite?() }
        content.configuration = UIHostingConfiguration {
            InviteCardContent(style: style, copy: copy, onInvite: onInvite)
        }
        .margins(.all, 0)
    }

    func fadeOut() {
        guard !isFading else { return }
        isFading = true
        isUserInteractionEnabled = false
        UIView.animate(withDuration: Fade.duration, delay: 0, options: [.curveEaseOut]) {
            self.fadeHost.alpha = 0
        }
    }

    private func resetFade() {
        guard isFading else { return }
        isFading = false
        isUserInteractionEnabled = true
        fadeHost.layer.removeAllAnimations()
        fadeHost.alpha = 1
    }
}

/// The card's SwiftUI content for either style. One root type for both, so the cell can switch
/// style on reuse without changing its hosting view's root type.
private struct InviteCardContent: View {

    let style: ChatInviteCardStyle
    let copy: ChatInviteCardCopy
    let onInvite: () -> Void

    var body: some View {
        switch style {
        case .emptyState:
            GroupReadyEmptyStateView(copy: copy, onInvite: onInvite)
        case .incomingBubble:
            ShareProfileWidgetView(
                username: nil,
                state: nil,
                onShare: onInvite,
                override: .init(
                    title: copy.title,
                    subtitle: copy.subtitle,
                    buttonTitle: copy.button,
                    avatar: nil
                )
            )
        }
    }
}

/// The group-ready card as the Group Money shell draws it: no bubble, a centred title and line, and
/// a white Invite People button (node 13729:658).
private struct GroupReadyEmptyStateView: View {

    let copy: ChatInviteCardCopy
    let onInvite: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(copy.title)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
            Text(copy.subtitle)
                .font(.appTextBody)
                .foregroundStyle(Color.textSecondary)
            Button(copy.button, action: onInvite)
                .buttonStyle(.filledCompact)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityIdentifier("group-ready-invite-button")
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}
#endif
