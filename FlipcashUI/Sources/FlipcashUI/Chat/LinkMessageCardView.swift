//
//  LinkMessageCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The message card: a link to one message, `app.flipcash.com/chat/{id}/m/{seq}`, drawn as the
/// message when this viewer may read it and as what they are missing when they may not.
///
/// SwiftUI content hosted in a UIKit view, like ``LinkGroupCardView``. Only the Join, Buy and
/// Request buttons take a tap of their own; the rest of the card is the link the bubble already
/// carries.
final class LinkMessageCardView: UIView {

    /// Called when the card's button (Join, Buy or Request) is tapped.
    var onAction: (() -> Void)?

    /// The button's frame in window coordinates, or `.null` while the card draws none.
    private var actionFrame = CGRect.null

    /// Whether `point`, in this view's coordinates, is on the card's button.
    func hasButton(at point: CGPoint) -> Bool {
        guard let window, !actionFrame.isNull else { return false }
        return actionFrame.contains(convert(point, to: window))
    }

    /// Called when the content's height at the card's width changes.
    var onHeightChange: (() -> Void)?

    private var shown: (state: LinkCard.Message.State?, loading: Bool)?

    /// The card's outline, set by the row from the card's place in its bubble run.
    var cornerRadii = BubbleBackgroundView.standaloneRadii {
        didSet {
            guard cornerRadii != oldValue else { return }
            renderContent()
        }
    }

    private let content: any UIView & UIContentView
    /// The content's height at the card's actual width, for the reason ``LinkGroupCardView`` pins its own.
    private var fittedHeight: NSLayoutConstraint!

    override init(frame: CGRect) {
        // Made with the content type `renderContent` sets later: a hosting content view traps when
        // handed a configuration of a different content type.
        content = UIHostingConfiguration { LinkMessageCardContent(state: nil, loading: false) }
            .margins(.all, 0)
            .makeContentView()
        super.init(frame: frame)
        backgroundColor = .clear
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        fittedHeight = content.heightAnchor.constraint(equalToConstant: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if fit() { onHeightChange?() }
    }

    @discardableResult
    private func fit() -> Bool {
        guard bounds.width > 0 else {
            fittedHeight.isActive = false
            return false
        }
        let height = content.systemLayoutSizeFitting(
            CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height.rounded(.up)
        guard !fittedHeight.isActive || abs(fittedHeight.constant - height) > 0.5 else { return false }
        fittedHeight.constant = height
        fittedHeight.isActive = true
        return true
    }

    func prepareForReuse() {
        shown = nil
    }

    /// Draws `state`; nil while the lookup has not answered.
    /// - Returns: whether this changed what the card draws, and with it the card's height.
    @discardableResult
    func configure(with state: LinkCard.Message.State?, loading: Bool) -> Bool {
        if let shown, shown.state == state, shown.loading == loading { return false }
        shown = (state, loading)
        renderContent()
        fit()
        return true
    }

    private func renderContent() {
        let display = shown
        let radii = cornerRadii
        actionFrame = .null
        content.configuration = UIHostingConfiguration {
            LinkMessageCardContent(
                state: display?.state,
                loading: display?.loading ?? false,
                cornerRadii: radii,
                onAction: { [weak self] in self?.onAction?() },
                onActionFrame: { [weak self] in self?.actionFrame = $0 }
            )
        }
        .margins(.all, 0)
    }
}

/// The card's body, from the message card component set (node 11396:118): eight faces on one
/// panel. Drawn by ``LinkMessageCardView`` wherever a message link appears in a transcript.
struct LinkMessageCardContent: View {

    /// Nil while nothing is known.
    let state: LinkCard.Message.State?
    /// Whether the lookup is still out. Unresolved and unavailable draw the same skeleton, so it
    /// does not change the face; the host uses it to know the card is settled.
    let loading: Bool
    var cornerRadii = RectangleCornerRadii(
        topLeading: LinkCardMetrics.radius,
        bottomLeading: LinkCardMetrics.radius,
        bottomTrailing: LinkCardMetrics.radius,
        topTrailing: LinkCardMetrics.radius
    )
    var onAction: () -> Void = {}
    var onActionFrame: ((CGRect) -> Void)? = nil

    /// Values this card adds to ``LinkCardMetrics``, from node 11493:201.
    enum Layout {
        static let padding: CGFloat = 12
        static let spacing: CGFloat = 6
        static let avatar: CGFloat = 20
        static let excerptLines = 4
        static let redactedBlur: CGFloat = 6
        static let panelOpacity: Double = 0.08
        static let skeletonOpacity: Double = 0.12
        static let skeletonBar: CGFloat = 10
        static let footerTop: CGFloat = 4
        /// The second skeleton bar's share of the first's width.
        static let skeletonShortFraction: CGFloat = 0.55
    }

    /// Copy, Title Case where it is a button.
    enum Copy {
        static let flipcash = "Flipcash"
        static let message = "Message"
        static let publicGroup = "Public group"
        static let privateGroup = "Private group"
        static let directMessage = "Direct message"
        static let open = "Open"
        static let join = "Join"
        static let buy = "Buy"
        static let request = "Request"
        static let directLocked = "Only the two people in this chat can read it."
        /// Drawn under the blur in place of text the viewer may not read. Never message text.
        static let redactedFiller = "This message is hidden until you meet the requirement to read it."
        static func groupLocked(_ title: String) -> String { "Only members of \(title) can read this message." }
        static func reactions(_ count: Int) -> String { count == 1 ? "1 reaction" : "\(count) reactions" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            faces
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(Layout.panelOpacity))
        .clipShape(UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous))
        .overlay {
            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                .strokeBorder(Color.white.opacity(LinkCardMetrics.borderOpacity))
        }
    }

    @ViewBuilder private var faces: some View {
        switch state {
        case .resolved(let message):
            header(avatarID: message.avatarID, name: message.chatTitle, kind: nil)
            byline("\(message.authorName) · \(message.time)")
            excerpt(message.excerpt, blurred: false)
            footer(message.reactionCount > 0 ? Copy.reactions(message.reactionCount) : nil, showsOpen: true)

        case .gatedReadable(let message):
            header(avatarID: message.avatarID, name: message.chatTitle, kind: Copy.publicGroup)
            byline("\(message.authorName) · \(message.time)")
            excerpt(message.excerpt, blurred: false)
            button(Copy.join)

        case .gatedRedacted(let redacted):
            header(avatarID: redacted.chatTitle, name: redacted.chatTitle, kind: Copy.publicGroup)
            excerpt(Copy.redactedFiller, blurred: true)
            footer(redacted.requirement, showsOpen: false)
            button(Copy.buy)

        case .lockedGroup(let group):
            header(avatarID: group.avatarID, name: group.title, kind: Copy.privateGroup, imageData: group.imageData, blurHash: group.blurHash)
            dimBody(Copy.groupLocked(group.title))
            footer([group.memberCount, group.hostName.map { "Hosted by \($0)" }].compactMap { $0 }.joined(separator: " · "), showsOpen: false)
            button(Copy.request)

        case .lockedDirect:
            header(avatarID: Copy.directMessage, name: Copy.directMessage, kind: nil)
            dimBody(Copy.directLocked)

        case .cash(let cash):
            header(avatarID: cash.chatTitle, name: cash.chatTitle, kind: nil)
            byline("\(cash.authorName) \(cash.verb == .tipped ? "tipped" : "sent")")
            Text(cash.amount)
                .font(.default(size: 24, weight: .semibold))
                .foregroundStyle(Color.textMain)
                .frame(maxWidth: .infinity, alignment: .leading)
            footer(nil, showsOpen: true)

        case .unavailable, nil:
            header(avatarID: Copy.flipcash, name: Copy.flipcash, kind: Copy.message)
            skeleton
        }
    }

    private func header(avatarID: String, name: String, kind: String?, imageData: Data? = nil, blurHash: String? = nil) -> some View {
        HStack(spacing: Layout.spacing) {
            ContactAvatarView(id: avatarID, displayName: name, imageData: imageData, blurhash: blurHash, size: Layout.avatar)
            Text(name)
                .font(.default(size: 12, weight: .semibold))
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
            if let kind {
                Text(kind)
                    .font(.default(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }

    private func byline(_ text: String) -> some View {
        Text(text)
            .font(.default(size: 12, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The message body, up to four lines. A redacted body is blurred filler: the model carries no
    /// text for it, and it is hidden from accessibility and never selectable.
    @ViewBuilder private func excerpt(_ text: String, blurred: Bool) -> some View {
        let body = Text(text)
            .font(.default(size: 16, weight: .medium))
            .foregroundStyle(Color.textMain)
            .lineLimit(Layout.excerptLines)
            .frame(maxWidth: .infinity, alignment: .leading)
        if blurred {
            body
                .blur(radius: Layout.redactedBlur)
                .clipped()
                .accessibilityHidden(true)
        } else {
            body
        }
    }

    private func dimBody(_ text: String) -> some View {
        Text(text)
            .font(.default(size: 15, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func footer(_ text: String?, showsOpen: Bool) -> some View {
        if text != nil || showsOpen {
            HStack(spacing: 8) {
                Text(text ?? "")
                    .font(.default(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsOpen {
                    Text(Copy.open)
                        .font(.default(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textMain)
                }
            }
            .padding(.top, Layout.footerTop)
        }
    }

    private func button(_ title: String) -> some View {
        Button(title, action: onAction)
            .buttonStyle(.filledCompact)
            .accessibilityIdentifier("message-card-cta")
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onActionFrame?($0) }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            RoundedRectangle(cornerRadius: Layout.skeletonBar / 2)
                .fill(Color.white.opacity(Layout.skeletonOpacity))
                .frame(height: Layout.skeletonBar)
            RoundedRectangle(cornerRadius: Layout.skeletonBar / 2)
                .fill(Color.white.opacity(Layout.skeletonOpacity))
                .frame(height: Layout.skeletonBar)
                .containerRelativeFrame(.horizontal) { width, _ in width * Layout.skeletonShortFraction }
        }
        .padding(.vertical, Layout.footerTop)
    }
}
#endif
