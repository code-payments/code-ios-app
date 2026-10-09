//
//  ChatShareProfileCell.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The signed-in user's own profile card, taken from the session so a widget naming them needs no
/// lookup. The widget's username decides whose card it is; this only answers for the viewer's own.
public struct OwnProfileCard: Equatable, Sendable {
    public let username: Username
    public let resolved: LinkCard.User.Resolved

    public init(username: Username, resolved: LinkCard.User.Resolved) {
        self.username = username
        self.resolved = resolved
    }
}

/// A recycled cell for a shared-profile widget (node 10588:1979): a bubble-chrome card with the
/// person's avatar, name and handle above a full-width Share button.
///
/// The widget carries only a handle, so the card asks its ``LinkCardSource`` for the person the way
/// a person link card does, and draws the handle alone until the answer lands. The card's width is
/// supplied by the owner, as the other card cells take theirs.
public final class ChatShareProfileCell: ChatColumnCell {

    public static let reuseIdentifier = "ChatShareProfileCell"

    /// The designed card width; a narrower transcript caps it.
    static let designedWidth: CGFloat = 290

    /// Where the card looks the person up. Set before ``configure(with:maxWidth:authorImageData:)``,
    /// which is where the card subscribes.
    weak var linkCardSource: (any LinkCardSource)?

    /// Called when the Share button is tapped, with the card being shared and the person's display
    /// name, nil until the lookup resolves one.
    var onShare: ((LinkCard.User, String?) -> Void)?

    private let card = BubbleBackgroundView()
    private let reactionRow = ReactionPillRowView()
    private let content: any UIView & UIContentView
    private var cardWidthConstraint: NSLayoutConstraint!
    private var reactionRowWidthConstraint: NSLayoutConstraint!
    private var subscription: Task<Void, Never>?
    private var shown: LinkCard.User?
    private var shownOwn: OwnProfileCard?

    /// The viewer's own profile: a widget naming the same handle is drawn from it, with no lookup.
    /// Set before ``configure(with:maxWidth:authorImageData:)``.
    var ownProfile: OwnProfileCard?

    public override init(frame: CGRect) {
        // Made with the content type `draw` sets later: a hosting content view traps when handed a
        // configuration of a different content type.
        content = UIHostingConfiguration {
            ShareProfileWidgetView(username: nil, state: nil, onShare: {})
        }
        .margins(.all, 0)
        .makeContentView()
        super.init(frame: frame)

        card.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        installColumn(content: card, accessory: reactionRow)
        reactionRow.onToggle = { [weak self] emoji in self?.onReactionTap?(emoji) }
        reactionRow.onLongPress = { [weak self] emoji in self?.onReactionLongPress?(emoji) }
        reactionRow.onAdd = { [weak self] in self?.onReactionAdd?() }

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

    /// Scopes the row's touch target to the card, not the full-width cell.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        card.convert(card.bounds, to: self).contains(point) || reactionRow.convert(reactionRow.bounds, to: self).contains(point)
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        subscription?.cancel()
        subscription = nil
        shown = nil
        shownOwn = nil
        reactionRow.prepareForReuse()
    }

    /// - Parameter maxWidth: the widest the card may be; the designed width caps it from above.
    public func configure(with message: ChatMessage, maxWidth: CGFloat, authorImageData: Data? = nil) {
        guard case .shareProfile(let profile) = message.content else { return }
        let width = min(Self.designedWidth, maxWidth)
        cardWidthConstraint.constant = width
        reactionRowWidthConstraint.constant = width

        card.apply(
            fill: UIColor.white.withAlphaComponent(0.02),
            radii: BubbleBackgroundView.radii(
                isFromSelf: message.sender == .me,
                groupedAbove: message.joinsBubbleAbove,
                groupedBelow: message.joinsBubbleBelow
            ),
            identity: message.id
        )
        reactionRow.layoutWidth = width
        reactionRow.hugsTrailingEdge = message.sender == .me
        reactionRow.configure(pills: message.reactions, canReact: message.canReact)
        updateColumn(for: message, authorImageData: authorImageData)

        // A reconfigure in place (a grouping or reaction change) keeps the subscription it has.
        guard shown != profile || shownOwn != ownProfile else { return }
        shown = profile
        shownOwn = ownProfile
        subscription?.cancel()
        subscription = nil

        // The viewer's own handle is answered from the session profile: no lookup, no loading state.
        if let own = ownProfile, case .username(let username) = profile.identity, username == own.username {
            draw(profile, state: .resolved(own.resolved))
            return
        }

        let source = linkCardSource
        let known = source?.known(.user(profile))
        draw(profile, state: Self.userState(known))

        guard let source else { return }
        // Subscribed here rather than inside the task: an answer landing before the task first runs
        // would be yielded to nobody.
        let states = source.states(for: .user(profile))
        subscription = Task { [weak self] in
            for await state in states {
                guard let self, !Task.isCancelled else { return }
                draw(profile, state: Self.userState(state))
            }
        }
    }

    private static func userState(_ state: LinkCard.State?) -> LinkCard.User.State? {
        switch state {
        case .user(let user): user
        case .cash, .token, .group, .web, nil: nil
        }
    }

    private static func displayName(_ state: LinkCard.User.State?) -> String? {
        switch state {
        case .resolved(let resolved): resolved.displayName.isEmpty ? nil : resolved.displayName
        case .notFound, nil: nil
        }
    }

    private func draw(_ profile: LinkCard.User, state: LinkCard.User.State?) {
        content.configuration = UIHostingConfiguration {
            ShareProfileWidgetView(username: profile.linkedHandle, state: state) { [weak self] in
                self?.onShare?(profile, Self.displayName(state))
            }
        }
        .margins(.all, 0)
    }
}

extension ChatShareProfileCell: BubbleCarrying {
    /// The card, not the cell: the cell spans the full row.
    var liftPreviewView: UIView { card }
    var liftPreviewMaskingPath: UIBezierPath? { card.maskingPath }

    func flashAttention(startedAt start: CFTimeInterval) { card.flashAttention(startedAt: start) }
}

/// The widget's body: avatar, name and handle stacked and centered above a full-width Share button.
///
/// Until the lookup answers, or when it finds nobody, the handle stands in as the name and the
/// handle line is dropped, so the card never shows a blank.
struct ShareProfileWidgetView: View {

    /// The `@handle` the widget names.
    let username: String?
    /// The lookup's answer; nil while it is out.
    let state: LinkCard.User.State?
    let onShare: () -> Void

    /// Named so Android can copy them one for one (node 10588:1979).
    enum Layout {
        static let padding: CGFloat = 12
        /// Between the identity block and the button.
        static let sectionGap: CGFloat = 18
        /// Between the avatar and the name.
        static let avatarGap: CGFloat = 12
        static let avatar: CGFloat = 64
        /// Between the name and the handle.
        static let lineGap: CGFloat = 2
        static let handleOpacity: Double = 0.5
        /// The avatar monogram's strength, muted per the design.
        static let initialsOpacity: Double = 0.4
        static let iconGap: CGFloat = 4
    }

    enum Copy {
        static let share = "Share"
    }

    var body: some View {
        VStack(spacing: Layout.sectionGap) {
            VStack(spacing: Layout.avatarGap) {
                avatarView
                VStack(spacing: Layout.lineGap) {
                    Text(name)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(2)
                    if let handle {
                        Text(handle)
                            .font(.appTextCaption)
                            .foregroundStyle(Color.textMain)
                            .opacity(Layout.handleOpacity)
                            .lineLimit(1)
                    }
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Button(action: onShare) {
                HStack(spacing: Layout.iconGap) {
                    Image(systemName: "square.and.arrow.up")
                    Text(Copy.share)
                }
            }
            .buttonStyle(.filledCompact)
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity)
    }

    private var resolved: LinkCard.User.Resolved? {
        if case .resolved(let user)? = state { user } else { nil }
    }

    private var name: String { resolved?.displayName ?? username ?? "" }

    private var handle: String? { resolved?.handle }

    private var avatarView: some View {
        ContactAvatarView(
            id: resolved?.avatarID ?? username ?? "",
            displayName: resolved?.displayName ?? "",
            imageData: resolved?.imageData,
            blurhash: resolved?.blurHash,
            size: Layout.avatar,
            // The design mutes the monogram to 40% (node 10588:1979), unlike the app's other avatars.
            initialsColor: Color.textMain.opacity(Layout.initialsOpacity)
        )
        .accessibilityHidden(true)
    }
}

#if DEBUG
private func sampleUser(name: String, handle: String?) -> LinkCard.User.State {
    .resolved(LinkCard.User.Resolved(
        userID: UUID(),
        isOwn: false,
        displayName: name,
        handle: handle,
        joined: nil,
        imageData: nil,
        blurHash: nil
    ))
}

#Preview("Share profile widget") {
    VStack(spacing: 16) {
        ShareProfileWidgetView(username: "@brad_burnham_2", state: sampleUser(name: "Brad Burnham", handle: "@brad_burnham_2"), onShare: {})
        ShareProfileWidgetView(username: "@brad_burnham_2", state: nil, onShare: {})
        ShareProfileWidgetView(username: "@brad_burnham_2", state: .notFound, onShare: {})
    }
    .frame(width: 290)
    .background(Color.white.opacity(0.02))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.backgroundMain)
}
#endif
#endif
