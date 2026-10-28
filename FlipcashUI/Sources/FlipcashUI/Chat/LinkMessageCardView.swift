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
import Kingfisher

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

    /// Where a photo message's thumbnail downloads from; nil draws every photo as its BlurHash.
    var loadPhoto: (@MainActor (LinkCard.Message.Photo) async -> ChatMediaLocation?)?

    /// The card's chat avatar: its monogram identity, the bytes already held, and how to fetch them.
    var chatAvatar: LinkMessageCardContent.ChatAvatar?

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
        let loadPhoto = loadPhoto
        let chatAvatar = chatAvatar
        actionFrame = .null
        content.configuration = UIHostingConfiguration {
            LinkMessageCardContent(
                state: display?.state,
                loading: display?.loading ?? false,
                cornerRadii: radii,
                loadPhoto: loadPhoto,
                chatAvatar: chatAvatar,
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
    var loadPhoto: (@MainActor (LinkCard.Message.Photo) async -> ChatMediaLocation?)? = nil
    var chatAvatar: ChatAvatar? = nil
    var onAction: () -> Void = {}
    var onActionFrame: ((CGRect) -> Void)? = nil

    /// The header's picture of the card's chat. Nil draws a fixed monogram.
    struct ChatAvatar {
        /// Monogram colour and identity: the chat id.
        let id: String
        /// The bytes already in memory, drawn on the first frame.
        let cached: Data?
        let load: @MainActor () async -> Data?
    }

    @State private var loadedAvatar: Data?

    /// Values this card adds to ``LinkCardMetrics``, from node 11493:201.
    enum Layout {
        static let padding = EdgeInsets(top: 12, leading: 14, bottom: 13, trailing: 14)
        /// Between the card's groups: identity, body, footer, button.
        static let spacing: CGFloat = 10
        /// Between the name and meta lines of the identity block.
        static let identitySpacing: CGFloat = 2
        static let avatar: CGFloat = 32
        static let avatarGap: CGFloat = 10
        static let excerptLines = 4
        static let excerptLineSpacing: CGFloat = 3
        static let redactedBlur: CGFloat = 6
        static let panelOpacity: Double = 0.08
        static let excerptOpacity: Double = 0.88
        static let secondaryOpacity: Double = 0.6
        static let chevronOpacity: Double = 0.42
        static let skeletonOpacity: Double = 0.12
        static let skeletonBar: CGFloat = 10
        /// The second skeleton bar's share of the first's width.
        static let skeletonShortFraction: CGFloat = 0.55
        /// The identity block's placeholder bars' share of the card's width.
        static let skeletonNameFraction: CGFloat = 0.45
        static let skeletonMetaFraction: CGFloat = 0.25
        static let photo: CGFloat = 56
        static let photoRadius: CGFloat = 8
    }

    /// Copy, Title Case where it is a button.
    enum Copy {
        static let privateGroup = "Private group"
        static let directMessage = "Direct message"
        static let deleted = "This message was deleted."
        static let settled = "Settled on Solana"
        static func cashVerb(_ verb: LinkCard.Message.Cash.Verb) -> String {
            switch verb {
            case .sent: "sent"
            case .tipped: "tipped"
            case .cashLink: "sent a cash link"
            }
        }
        static func byline(_ author: String, _ time: String) -> String { "\(author) · \(time)" }
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
        .task(id: chatAvatar?.id) {
            loadedAvatar = await chatAvatar?.load()
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
            chatIdentity(name: message.chatTitle, meta: Copy.byline(message.authorName, message.time))
            excerpt(message.excerpt, blurred: false, photo: message.photo)
            footer(message.reactionCount > 0 ? Copy.reactions(message.reactionCount) : nil)

        case .gatedReadable(let message):
            chatIdentity(name: message.chatTitle, meta: Copy.byline(message.authorName, message.time))
            excerpt(message.excerpt, blurred: false, photo: message.photo)
            button(Copy.join)

        case .gatedRedacted(let redacted):
            chatIdentity(name: redacted.chatTitle, meta: Copy.byline(redacted.authorName, redacted.time))
            excerpt(Copy.redactedFiller, blurred: true, photo: redacted.photoBlurHash.map { .init(blobID: nil, sealed: nil, blurHash: $0) })
            footer(redacted.requirement)
            button(Copy.buy)

        case .lockedGroup(let group):
            chatIdentity(name: group.title, meta: Copy.privateGroup, fallbackData: group.imageData, blurHash: group.blurHash)
            dimBody(Copy.groupLocked(group.title))
            footer([group.memberCount, group.hostName.map { "Hosted by \($0)" }].compactMap { $0 }.joined(separator: " · "))
            button(Copy.request)

        case .lockedDirect:
            identity(avatarID: Copy.directMessage, name: Copy.directMessage, meta: nil, opens: false)
            dimBody(Copy.directLocked)

        case .cash(let cash):
            chatIdentity(name: cash.chatTitle, meta: Copy.byline("\(cash.authorName) \(Copy.cashVerb(cash.verb))", cash.time))
            Text(cash.amount)
                .font(.default(size: 24, weight: .semibold))
                .foregroundStyle(Color.textMain)
                .frame(maxWidth: .infinity, alignment: .leading)
            footer(cash.claim?.caption ?? Copy.settled)

        case .deleted(let deleted):
            chatIdentity(name: deleted.chatTitle, meta: nil)
            dimBody(Copy.deleted)

        case .unavailable, nil:
            skeletonIdentity
            skeleton
        }
    }

    /// The identity block for a known chat: its avatar once loaded, its monogram until then.
    private func chatIdentity(name: String, meta: String?, fallbackData: Data? = nil, blurHash: String? = nil) -> some View {
        identity(
            avatarID: chatAvatar?.id ?? name,
            name: name,
            meta: meta,
            imageData: loadedAvatar ?? chatAvatar?.cached ?? fallbackData,
            blurHash: blurHash
        )
    }

    /// The avatar beside the chat's name over one meta line, with a chevron when the card opens.
    private func identity(avatarID: String, name: String, meta: String?, imageData: Data? = nil, blurHash: String? = nil, opens: Bool = true) -> some View {
        HStack(spacing: Layout.avatarGap) {
            ContactAvatarView(id: avatarID, displayName: name, imageData: imageData, blurhash: blurHash, size: Layout.avatar)
            VStack(alignment: .leading, spacing: Layout.identitySpacing) {
                Text(name)
                    .font(.default(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                if let meta {
                    Text(meta)
                        .font(.default(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(Layout.secondaryOpacity))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if opens {
                Image.icon(.chevronRightMedium)
                    .iconSize(16)
                    .foregroundStyle(Color.white.opacity(Layout.chevronOpacity))
                    .accessibilityHidden(true)
            }
        }
    }

    /// The message body, up to four lines. A redacted body is blurred filler: the model carries no
    /// text for it, and it is hidden from accessibility and never selectable.
    @ViewBuilder private func excerpt(_ text: String, blurred: Bool, photo: LinkCard.Message.Photo? = nil) -> some View {
        if let photo, text.isEmpty {
            MessageCardPhoto(photo: photo, load: loadPhoto)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let photo {
            HStack(alignment: .top, spacing: Layout.avatarGap) {
                excerptText(text, blurred: blurred)
                MessageCardPhoto(photo: photo, load: loadPhoto)
            }
        } else {
            excerptText(text, blurred: blurred)
        }
    }

    @ViewBuilder private func excerptText(_ text: String, blurred: Bool) -> some View {
        let body = Text(Self.flattened(text))
            .font(.default(size: 15, weight: .medium))
            .foregroundStyle(Color.white.opacity(Layout.excerptOpacity))
            .lineSpacing(Layout.excerptLineSpacing)
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

    /// `text` with each line break and the whitespace around it folded to one space, so blank
    /// lines do not spend the excerpt's four lines.
    static func flattened(_ text: String) -> String {
        text.replacing(/\s*\n\s*/, with: " ")
    }

    private func dimBody(_ text: String) -> some View {
        Text(text)
            .font(.default(size: 15, weight: .medium))
            .foregroundStyle(Color.white.opacity(Layout.secondaryOpacity))
            .lineSpacing(Layout.excerptLineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func footer(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.default(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(Layout.secondaryOpacity))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func button(_ title: String) -> some View {
        Button(title, action: onAction)
            .buttonStyle(.filledCompact)
            .accessibilityIdentifier("message-card-cta")
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onActionFrame?($0) }
    }

    /// The identity block before anything is known: a gray circle and two gray bars.
    private var skeletonIdentity: some View {
        HStack(spacing: Layout.avatarGap) {
            Circle()
                .fill(Color.white.opacity(Layout.skeletonOpacity))
                .frame(width: Layout.avatar, height: Layout.avatar)
            VStack(alignment: .leading, spacing: Layout.identitySpacing * 3) {
                skeletonBar(fraction: Layout.skeletonNameFraction)
                skeletonBar(fraction: Layout.skeletonMetaFraction)
            }
        }
        .accessibilityHidden(true)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Layout.spacing / 2) {
            skeletonBar(fraction: 1)
            skeletonBar(fraction: Layout.skeletonShortFraction)
        }
        .accessibilityHidden(true)
    }

    private func skeletonBar(fraction: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Layout.skeletonBar / 2)
            .fill(Color.white.opacity(Layout.skeletonOpacity))
            .frame(height: Layout.skeletonBar)
            .containerRelativeFrame(.horizontal) { width, _ in width * fraction }
    }
}
/// A photo message's thumbnail: its BlurHash, faded to the photo once it downloads. A photo
/// with no blob — the viewer is below the chat's rules — stays its BlurHash.
private struct MessageCardPhoto: View {
    let photo: LinkCard.Message.Photo
    let load: (@MainActor (LinkCard.Message.Photo) async -> ChatMediaLocation?)?

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shown = image ?? BlurHashCache.shared.image(for: photo.blurHash)
        ZStack {
            Color.white.opacity(LinkMessageCardContent.Layout.skeletonOpacity)
            if let shown {
                Image(uiImage: shown).resizable().scaledToFill()
            }
        }
        .frame(width: LinkMessageCardContent.Layout.photo, height: LinkMessageCardContent.Layout.photo)
        .clipShape(RoundedRectangle(cornerRadius: LinkMessageCardContent.Layout.photoRadius, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: image)
        .accessibilityHidden(true)
        .task(id: photo) { await fetch() }
    }

    private func fetch() async {
        guard let blobID = photo.blobID, let load, let location = await load(photo) else { return }
        let side = LinkMessageCardContent.Layout.photo * displayScale
        let processor = DownsamplingImageProcessor(size: CGSize(width: side, height: side))
        let source = ChatMediaImageSource.source(blobID: blobID, location: location)
        let result = await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: source, options: ChatMediaImageSource.options(processor: processor)) {
                continuation.resume(returning: $0)
            }
        }
        ChatMediaImageSource.persist(result, processor: processor)
        if case .success(let value) = result, !Task.isCancelled { image = value.image }
    }
}
#endif
