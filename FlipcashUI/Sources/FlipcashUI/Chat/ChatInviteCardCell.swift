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
/// When `isLeaving` arrives the card plays its pop (``Pop``) in place. The owner keeps the row in
/// the transcript for that long and deletes it afterwards, so the plain `deleteItems` removes a
/// card that is already gone.
public final class ChatInviteCardCell: UICollectionViewCell {

    public static let reuseIdentifier = "ChatInviteCardCell"

    /// The card's exit: grows to `peak`, then shrinks to nothing while fading out.
    public enum Pop {
        public static let peak: CGFloat = 1.08
        public static let duration: TimeInterval = 0.28
        /// Where in the duration the card is at its peak.
        static let peakFraction: Double = 0.4
    }

    /// Who the card is from. No shared constant names the app as a sender, so this is the one place.
    static let senderName = "Flipcash"

    /// Called when the Invite People button is tapped.
    var onInvite: (() -> Void)?

    /// Everything the pop scales: the sender's face and name travel with the bubble.
    private let popHost = UIView()
    private let card = BubbleBackgroundView()
    private let senderName = UILabel()
    private let senderAvatar = ChatAuthorAvatarView()
    private let content: any UIView & UIContentView
    private var widthConstraint: NSLayoutConstraint!
    private var isPopping = false

    public override init(frame: CGRect) {
        content = UIHostingConfiguration {
            ShareProfileWidgetView(username: nil, state: nil, onShare: {})
        }
        .margins(.all, 0)
        .makeContentView()
        super.init(frame: frame)

        popHost.translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        contentView.addSubview(popHost)
        popHost.addSubview(card)

        // The sender line is laid out as the transcript lays out an incoming group message: the
        // name 4pt above the bubble, the face in the leading gutter beside the bubble's top.
        senderName.translatesAutoresizingMaskIntoConstraints = false
        senderName.font = .default(size: 12, weight: .medium)
        senderName.textColor = UIColor(Color.textMain.opacity(0.5))
        senderName.text = Self.senderName
        popHost.addSubview(senderName)
        senderAvatar.translatesAutoresizingMaskIntoConstraints = false
        senderAvatar.configureAsFlipcash()
        popHost.addSubview(senderAvatar)
        let bubbleLeading = ChatColumnCell.rowInset + ChatColumnCell.authorGutterWidth

        widthConstraint = card.widthAnchor.constraint(equalToConstant: ChatShareProfileCell.designedWidth)
        NSLayoutConstraint.activate([
            widthConstraint,
            popHost.topAnchor.constraint(equalTo: contentView.topAnchor),
            popHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            popHost.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            popHost.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            senderName.topAnchor.constraint(equalTo: popHost.topAnchor),
            senderName.leadingAnchor.constraint(equalTo: popHost.leadingAnchor, constant: bubbleLeading),
            card.topAnchor.constraint(equalTo: senderName.bottomAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: popHost.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: popHost.leadingAnchor, constant: bubbleLeading),
            senderAvatar.leadingAnchor.constraint(equalTo: popHost.leadingAnchor, constant: ChatColumnCell.rowInset),
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
        resetPop()
    }

    /// - Parameter maxWidth: the widest the card may be; the Share Profile widget's width caps it.
    func configure(groupName: String, isLeaving: Bool, maxWidth: CGFloat) {
        widthConstraint.constant = min(ChatShareProfileCell.designedWidth, maxWidth - ChatColumnCell.authorGutterWidth)
        card.apply(
            fill: UIColor.white.withAlphaComponent(0.02),
            radii: BubbleBackgroundView.radii(isFromSelf: false, groupedAbove: false, groupedBelow: false),
            identity: ChatItem.inviteCard(groupName: "", isLeaving: false).id
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

        if isLeaving {
            pop()
        } else {
            resetPop()
        }
    }

    private func pop() {
        guard !isPopping else { return }
        isPopping = true
        isUserInteractionEnabled = false
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animateKeyframes(withDuration: Pop.duration, delay: 0, options: [.calculationModeLinear]) {
            if !reduceMotion {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: Pop.peakFraction) {
                    self.popHost.transform = CGAffineTransform(scaleX: Pop.peak, y: Pop.peak)
                }
            }
            UIView.addKeyframe(withRelativeStartTime: reduceMotion ? 0 : Pop.peakFraction, relativeDuration: reduceMotion ? 1 : 1 - Pop.peakFraction) {
                // Not exactly zero: a singular transform is dropped by Core Animation.
                if !reduceMotion { self.popHost.transform = CGAffineTransform(scaleX: 0.001, y: 0.001) }
                self.popHost.alpha = 0
            }
        }
    }

    private func resetPop() {
        guard isPopping else { return }
        isPopping = false
        isUserInteractionEnabled = true
        popHost.layer.removeAllAnimations()
        popHost.transform = .identity
        popHost.alpha = 1
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
