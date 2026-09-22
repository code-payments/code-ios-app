//
//  LinkGroupCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The group-invite card: the chat's picture, title, member count and entry rule, drawn in place of
/// an `app.flipcash.com/chat/{id}` link, with a button into the chat.
///
/// Built from the chat's public record only. The roster is private to members whatever the group's
/// mode, so there are no member avatars here and no names.
///
/// SwiftUI content hosted in a UIKit view, for the same reason as ``ChatGroupCardCell``: the picture
/// is the same `ContactAvatarView` the chat's own head card draws. The content does not take touches.
/// The whole card is one tap target, the row's, and the button is the label of what that tap does:
/// it routes through the chat link, whose screen offers the join or the buy itself.
final class LinkGroupCardView: UIView {

    private let content: any UIView & UIContentView
    private let shimmer = LinkCardShimmerView(
        ground: UIColor(Color.backgroundRow),
        highlight: UIColor.white.withAlphaComponent(0.06)
    )

    override init(frame: CGRect) {
        // Made with the content type `configure` sets later: a hosting content view traps when
        // handed a configuration of a different content type.
        content = UIHostingConfiguration { LinkGroupCardContent(state: .unavailable) }
            .margins(.all, 0)
            .makeContentView()
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .button

        content.translatesAutoresizingMaskIntoConstraints = false
        content.isUserInteractionEnabled = false
        addSubview(content)

        shimmer.translatesAutoresizingMaskIntoConstraints = false
        shimmer.layer.cornerRadius = GroupCardView.Layout.radius
        shimmer.layer.cornerCurve = .continuous
        addSubview(shimmer)

        for view in [content, shimmer] as [UIView] {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
    }

    func prepareForReuse() {
        shimmer.setShimmering(false)
    }

    /// Draws `state`; nil while the lookup has not answered.
    ///
    /// - Parameter loading: whether the lookup is still out. A card with nothing to say yet is the
    ///   shimmer on its own, at the card's minimum height.
    func configure(with state: LinkCard.Group.State?, loading: Bool) {
        let showsShimmer = loading && state == nil
        shimmer.isHidden = !showsShimmer
        shimmer.setShimmering(showsShimmer)
        content.isHidden = showsShimmer

        let display = state ?? .unavailable
        content.configuration = UIHostingConfiguration {
            LinkGroupCardContent(state: display)
        }
        .margins(.all, 0)

        accessibilityLabel = LinkGroupCardContent.accessibilityLabel(for: display)
        invalidateIntrinsicContentSize()
    }
}

/// The card's body, per the group head card (nodes 10125:19157, 10127:118280, 10127:116723): the
/// same radius, ring, avatar ring, title and requirement styling, with a tinted band across the top.
struct LinkGroupCardContent: View {

    let state: LinkCard.Group.State

    /// Values this card adds to the head card's ``GroupCardView/Layout``. Named so Android can copy
    /// them one for one.
    enum Layout {
        /// The tinted band across the top of the card.
        static let bandHeight: CGFloat = 46
        /// The band's opacity over the chat background. Pending design sign-off.
        static let bandOpacity: Double = 0.28
        static let avatar: CGFloat = 64
        /// Between the title and the member count under it.
        static let memberCountGap: CGFloat = 2
        /// The least room between the text column and the button, when the card is at its
        /// minimum height and the content is short.
        static let buttonGap: CGFloat = 16
    }

    /// Button labels, Title Case.
    enum Copy {
        /// Every resolved card, whatever the viewer's membership or holdings.
        static let start = "Start Chatting"
        static let unavailable = "Group Unavailable"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(tint.opacity(Layout.bandOpacity))
                    .frame(height: Layout.bandHeight)

                if case .resolved(let group) = state {
                    ContactAvatarView(
                        id: group.avatarID,
                        displayName: group.title,
                        imageData: group.imageData,
                        blurhash: group.blurHash,
                        size: Layout.avatar
                    )
                    .overlay { Circle().strokeBorder(Color.white.opacity(GroupCardView.Layout.borderOpacity)) }
                    // Centred on the band's bottom edge.
                    .padding(.top, Layout.bandHeight - Layout.avatar / 2)
                }
            }

            if case .resolved(let group) = state {
                text(for: group)
                    .padding(.horizontal, GroupCardView.Layout.horizontalPadding)
            }

            Spacer(minLength: Layout.buttonGap)

            button
                .padding(.horizontal, GroupCardView.Layout.horizontalPadding)
                .padding(.bottom, GroupCardView.Layout.horizontalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: GroupCardView.Layout.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GroupCardView.Layout.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(GroupCardView.Layout.borderOpacity))
        }
    }

    private func text(for group: LinkCard.Group.Resolved) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(group.title)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.top, GroupCardView.Layout.titleGap)

            Text(group.memberCount)
                .font(.default(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, Layout.memberCountGap)

            if let requirement = group.requirement {
                Text(requirement)
                    .font(.default(size: 15, weight: .medium))
                    .foregroundStyle(Color.textMain.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, GroupCardView.Layout.requirementGap)
            }
        }
    }

    @ViewBuilder private var button: some View {
        switch state {
        case .unavailable:
            Button(Copy.unavailable) {}
                .buttonStyle(.filled20Compact)
                .disabled(true)
        case .resolved:
            Button(Copy.start) {}.buttonStyle(.filledCompact)
        }
    }

    /// The picture's average colour, or the avatar placeholder's top colour when there is no
    /// picture — so the band always matches what the avatar under it shows.
    private var tint: Color {
        guard case .resolved(let group) = state,
              let average = BlurHash.averageColor(blurHash: group.blurHash) else {
            return .avatarPlaceholderTop
        }
        return average.color
    }

    static func accessibilityLabel(for state: LinkCard.Group.State) -> String {
        switch state {
        case .unavailable:
            return Copy.unavailable
        case .resolved(let group):
            return [group.title, group.memberCount, group.requirement?.replacingOccurrences(of: "\n", with: " ")]
                .compactMap { $0 }
                .joined(separator: ", ")
        }
    }
}
#endif
