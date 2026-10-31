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
/// so it has no sender, receipt or reactions.
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
    private var isFading = false

    public override init(frame: CGRect) {
        content = UIHostingConfiguration {
            ShareProfileWidgetView(username: nil, state: nil, onShare: {})
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
        NSLayoutConstraint.activate([
            widthConstraint,
            fadeHost.topAnchor.constraint(equalTo: contentView.topAnchor),
            fadeHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            fadeHost.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            fadeHost.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            senderName.topAnchor.constraint(equalTo: fadeHost.topAnchor),
            senderName.leadingAnchor.constraint(equalTo: fadeHost.leadingAnchor, constant: bubbleLeading),
            card.topAnchor.constraint(equalTo: senderName.bottomAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: fadeHost.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: fadeHost.leadingAnchor, constant: bubbleLeading),
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

    /// - Parameter maxWidth: the widest the card may be; the Share Profile widget's width caps it.
    func configure(groupName: String, maxWidth: CGFloat) {
        widthConstraint.constant = min(ChatShareProfileCell.designedWidth, maxWidth - ChatColumnCell.authorGutterWidth)
        card.apply(
            fill: UIColor.white.withAlphaComponent(0.02),
            radii: BubbleBackgroundView.radii(isFromSelf: false, groupedAbove: false, groupedBelow: false),
            identity: ChatItem.inviteCard(groupName: "").id
        )
        content.configuration = UIHostingConfiguration {
            ShareProfileWidgetView(
                username: nil,
                state: nil,
                onShare: { [weak self] in self?.onInvite?() },
                override: .init(
                    title: Copy.title,
                    subtitle: Copy.subtitle(groupName: groupName),
                    buttonTitle: Copy.button,
                    avatar: nil
                )
            )
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

extension ChatInviteCardCell {
    enum Copy {
        static let title = "Your Group Is Ready"
        static let button = "Invite People"

        static func subtitle(groupName: String) -> String {
            "Invite people to join \(groupName)"
        }
    }
}
#endif
