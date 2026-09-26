//
//  LinkUserCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The person card: a frosted ID card for a `flipcash.com/<handle>` or `flipcash.com/<uuid>` link,
/// tapped as a whole.
///
/// Built from the person's public profile only. Hosted the same way as ``LinkGroupCardView``: SwiftUI
/// content in a UIKit view, pinned to its fitted height at the card's width, a shimmer while the
/// lookup is out.
final class LinkUserCardView: UIView {

    /// Called when the card is tapped. Never for a card with no account behind it.
    var onTap: (() -> Void)?

    /// Called when the content's height at the card's width changes, so the row can be measured
    /// again.
    var onHeightChange: (() -> Void)?

    /// What the card last drew, so a repeat of it is not reported as a change.
    private var shown: (state: LinkCard.User.State?, handle: String?, loading: Bool)?
    /// The width the content was last drawn at, which sets the card's minimum height.
    private var drawnWidth: CGFloat = 0

    private let content: any UIView & UIContentView
    /// The content's height at the card's actual width, as for ``LinkGroupCardView``.
    private var fittedHeight: NSLayoutConstraint!
    /// The card's minimum proportion, held while the shimmer stands alone.
    private var shimmerHeight: NSLayoutConstraint!
    private let shimmer = LinkCardShimmerView(
        ground: UIColor(Color.backgroundRow),
        highlight: UIColor.white.withAlphaComponent(0.06)
    )

    override init(frame: CGRect) {
        // Made with the content type `configure` sets later: a hosting content view traps when
        // handed a configuration of a different content type.
        content = UIHostingConfiguration { LinkUserCardContent(state: .notFound, linkedHandle: nil, width: 0) }
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
        shimmerHeight = heightAnchor.constraint(equalTo: widthAnchor, multiplier: LinkCardView.aspectRatio)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shimmer.layer.cornerRadius = GroupCardView.Layout.radius
        if bounds.width != drawnWidth, let shown {
            draw(shown.state, handle: shown.handle)
        }
        if fit() { onHeightChange?() }
    }

    /// Pins the content to its height at the current width. Off while the shimmer stands alone,
    /// which takes the card's minimum proportion instead.
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
    /// - Parameters:
    ///   - linkedHandle: the `@handle` the link itself names, the name a not-found card shows.
    ///   - loading: whether the lookup is still out. A card with nothing to say yet is the shimmer
    ///     on its own, at the card's minimum proportion.
    /// - Returns: whether this changed what the card draws, and with it the card's height.
    @discardableResult
    func configure(with state: LinkCard.User.State?, linkedHandle: String?, loading: Bool) -> Bool {
        if let shown, shown.state == state, shown.handle == linkedHandle, shown.loading == loading { return false }
        shown = (state, linkedHandle, loading)

        let showsShimmer = loading && state == nil
        shimmer.isHidden = !showsShimmer
        shimmer.setShimmering(showsShimmer)
        content.isHidden = showsShimmer
        shimmerHeight.isActive = showsShimmer

        draw(state, handle: linkedHandle)
        fit()
        return true
    }

    private func draw(_ state: LinkCard.User.State?, handle: String?) {
        drawnWidth = bounds.width
        let display = state ?? .notFound
        let width = bounds.width
        content.configuration = UIHostingConfiguration {
            LinkUserCardContent(state: display, linkedHandle: handle, width: width) { [weak self] in
                self?.onTap?()
            }
        }
        .margins(.all, 0)
    }
}

/// The person card's body: an ID card over the person's blurred picture, sized and cornered like
/// the other link cards, and itself the tap target.
///
/// The minimum height comes from ``LinkCardView/aspectRatio`` and the corner and border from the
/// group card, so it lines up with a cash or group card; the rest is in ``Layout``.
struct LinkUserCardContent: View {

    let state: LinkCard.User.State
    /// The `@handle` the link names, shown as the name when there is no account behind it.
    let linkedHandle: String?
    /// The card's width, which sets its minimum height.
    let width: CGFloat
    var onTap: () -> Void = {}

    /// This card's own values. Named so Android can copy them one for one.
    enum Layout {
        /// The black over the decoded BlurHash backdrop. Pending design sign-off.
        static let tintOpacity: Double = 0.6
        /// Inset from every edge of the card to its content.
        static let padding: CGFloat = 14
        static let avatar: CGFloat = 40
        /// The least room between the avatar and the name, when the card is at its minimum height.
        static let avatarGap: CGFloat = 16
        /// Between every line of the name column, so the column spaces evenly.
        static let lineGap: CGFloat = 6
        /// The handle, set in `appTextMessage` under the `appTextLarge` name.
        static let handleOpacity: Double = 0.5
        /// The joined line or the not-found line, set in `appTextCaption`.
        static let detailOpacity: Double = 0.45
    }

    /// Detail-line copy, Title Case.
    enum Copy {
        static let notFound = "No Such Account"
    }

    var body: some View {
        Button(action: onTap) { card }
            .buttonStyle(.plain)
            // Nothing to open with no account behind the link.
            .disabled(!isTappable)
            .accessibilityElement(children: .combine)
    }

    private var isTappable: Bool {
        switch state {
        case .resolved: true
        case .notFound: false
        }
    }

    // MARK: - Card -

    private var cornerRadius: CGFloat { GroupCardView.Layout.radius }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if case .resolved(let user) = state {
                ContactAvatarView(
                    id: user.avatarID,
                    displayName: user.displayName,
                    imageData: user.imageData,
                    blurhash: user.blurHash,
                    size: Layout.avatar
                )
                .overlay { Circle().strokeBorder(Color.white.opacity(GroupCardView.Layout.borderOpacity)) }
            }

            Spacer(minLength: Layout.avatarGap)

            identity
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, minHeight: width * LinkCardView.aspectRatio, alignment: .leading)
        .background { backdrop }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(GroupCardView.Layout.borderOpacity))
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let name {
                Text(name)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
            }

            if case .resolved(let user) = state, let handle = user.handle {
                Text(handle)
                    .font(.appTextMessage)
                    .foregroundStyle(Color.textMain)
                    .opacity(Layout.handleOpacity)
                    .padding(.top, Layout.lineGap)
            }

            if let detail {
                Text(detail)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                    .opacity(Layout.detailOpacity)
                    .padding(.top, Layout.lineGap)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The account's name, or for a card with no account the handle the link names; nothing for an
    /// id link with nobody behind it.
    private var name: String? {
        switch state {
        case .resolved(let user): user.displayName
        case .notFound:           linkedHandle
        }
    }

    /// The small line under the handle: when the account joined, or that there is no account.
    private var detail: String? {
        switch state {
        case .resolved(let user): user.joined
        case .notFound:           Copy.notFound
        }
    }

    /// The picture's BlurHash filling the card under a black tint, or the tint over the
    /// chat's own ground when there is no picture. The photo itself is never the backdrop.
    private var backdrop: some View {
        ZStack {
            Color.backgroundMain
            if case .resolved(let user) = state, let preview = BlurHashCache.shared.image(for: user.blurHash) {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
            }
            Color.black.opacity(Layout.tintOpacity)
        }
    }
}
#endif
