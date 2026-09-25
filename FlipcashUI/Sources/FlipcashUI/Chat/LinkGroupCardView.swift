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
/// is the same `ContactAvatarView` the chat's own head card draws. Only the button takes a tap; it
/// routes through the chat link, whose screen offers the join or the buy itself.
final class LinkGroupCardView: UIView {

    /// Called when the "View" button is tapped.
    var onStart: (() -> Void)?

    /// Called when the content's height at the card's width changes, so the row can be measured
    /// again.
    var onHeightChange: (() -> Void)?

    /// What the card last drew, so a repeat of it is not reported as a change.
    private var shown: (state: LinkCard.Group.State?, loading: Bool)?

    private let content: any UIView & UIContentView
    /// The content's height at the card's actual width. The hosting view's own intrinsic height is
    /// worked out at its ideal width, where a wrapped requirement line fits on one line, so the row
    /// came up a line short and the card spilled over its neighbours.
    private var fittedHeight: NSLayoutConstraint!
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

        content.translatesAutoresizingMaskIntoConstraints = false
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
        fittedHeight = content.heightAnchor.constraint(equalToConstant: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if fit() { onHeightChange?() }
    }

    /// Pins the content to its height at the current width. Off while the shimmer stands alone,
    /// which takes the card's minimum height instead.
    /// - Returns: whether the pinned height changed.
    @discardableResult
    private func fit() -> Bool {
        guard !content.isHidden, bounds.width > 0 else {
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
        shimmer.setShimmering(false)
        shown = nil
    }

    /// Draws `state`; nil while the lookup has not answered.
    ///
    /// - Parameter loading: whether the lookup is still out. A card with nothing to say yet is the
    ///   shimmer on its own, at the card's minimum height.
    /// - Returns: whether this changed what the card draws, and with it the card's height.
    @discardableResult
    func configure(with state: LinkCard.Group.State?, loading: Bool) -> Bool {
        if let shown, shown.state == state, shown.loading == loading { return false }
        shown = (state, loading)

        let showsShimmer = loading && state == nil
        shimmer.isHidden = !showsShimmer
        shimmer.setShimmering(showsShimmer)
        content.isHidden = showsShimmer

        let display = state ?? .unavailable
        content.configuration = UIHostingConfiguration {
            LinkGroupCardContent(state: display, onAction: { [weak self] in self?.onStart?() })
        }
        .margins(.all, 0)

        fit()
        return true
    }
}

/// The card's body, per the group head card (nodes 10125:19157, 10127:118280, 10127:116723): the
/// same radius, ring, avatar ring, title and requirement styling, with a tinted band across the top.
///
/// Shared by two hosts rather than forked between them: ``LinkGroupCardView`` draws it wherever a
/// group's invite link appears in a transcript (CTA "View", into the group), and
/// ``ChatGroupCardCell``'s ``GroupCardView`` draws it at the head of a group's own transcript while
/// it is still empty (CTA "Invite People", into the invite sheet). The CTA's label and action are
/// the only things that differ between the two, so they are the only things passed in.
struct LinkGroupCardContent: View {

    let state: LinkCard.Group.State
    /// The button's label — "View" from a transcript link, "Invite People" from a group's own
    /// empty-state head card.
    var ctaTitle: String = Copy.view
    /// Called when the button is tapped.
    var onAction: () -> Void = {}
    /// The button's UI-test handle, which differs by host.
    var ctaAccessibilityIdentifier: String = "group-card-cta"
    /// Taps the picture/title band open, same as the head card's own chevron used to. Nil leaves
    /// the band inert, as it is inline in a transcript, where only the button leads anywhere.
    var onTapCard: (() -> Void)? = nil

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
        /// A group's invite link, met in a transcript.
        static let view = "View"
        /// A group's own empty-state head card.
        static let invite = "Invite People"
        static let unavailable = "Group Unavailable"
    }

    var body: some View {
        VStack(spacing: 0) {
            band

            if case .resolved(let group) = state {
                text(for: group)
                    .padding(.horizontal, GroupCardView.Layout.horizontalPadding)
                    // Measured at its ideal height whatever the row proposes: under a short
                    // proposal `Text` drops the requirement's second line for an ellipsis.
                    .fixedSize(horizontal: false, vertical: true)
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
            Text(group.title)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
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

    /// The tinted band and the picture centred on its bottom edge, tappable as one unit when
    /// ``onTapCard`` is set.
    @ViewBuilder private var band: some View {
        let content = ZStack(alignment: .top) {
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
        if let onTapCard, case .resolved = state {
            Button(action: onTapCard) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder private var button: some View {
        switch state {
        case .unavailable:
            Button(Copy.unavailable) {}
                .buttonStyle(.filled20Compact)
                .disabled(true)
        case .resolved:
            Button(ctaTitle, action: onAction)
                .buttonStyle(.filledCompact)
                .accessibilityIdentifier(ctaAccessibilityIdentifier)
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
}
#endif
