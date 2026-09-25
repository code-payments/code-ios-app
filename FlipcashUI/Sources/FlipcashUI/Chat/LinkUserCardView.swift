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
/// with the person's minimum to chat and a button under it.
///
/// Built from the person's public profile only. Hosted the same way as ``LinkGroupCardView``: SwiftUI
/// content in a UIKit view, pinned to its fitted height at the card's width, a shimmer while the
/// lookup is out, and taps only on the button.
final class LinkUserCardView: UIView {

    /// Called when the button is tapped.
    var onButton: (() -> Void)?

    /// Called when the content's height at the card's width changes, so the row can be measured
    /// again.
    var onHeightChange: (() -> Void)?

    /// What the card last drew, so a repeat of it is not reported as a change.
    private var shown: (state: LinkCard.User.State?, handle: String?, loading: Bool)?
    /// The width the content was last drawn at. The card's type and corner are fractions of it.
    private var drawnWidth: CGFloat = 0

    private let content: any UIView & UIContentView
    /// The content's height at the card's actual width, as for ``LinkGroupCardView``.
    private var fittedHeight: NSLayoutConstraint!
    /// The card's own proportion, held while the shimmer stands alone.
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
        shimmerHeight = heightAnchor.constraint(equalTo: widthAnchor, multiplier: TipcardProportions.aspectRatio)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shimmer.layer.cornerRadius = bounds.width * TipcardProportions.cornerRadiusFraction
        if bounds.width != drawnWidth, let shown {
            draw(shown.state, handle: shown.handle)
        }
        if fit() { onHeightChange?() }
    }

    /// Pins the content to its height at the current width. Off while the shimmer stands alone,
    /// which takes the card's own proportion instead.
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
    ///     on its own, at the card's own proportion.
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
                self?.onButton?()
            }
        }
        .margins(.all, 0)
    }
}

/// The person card's body: the ID card in the tip card's proportions and material, then the fee
/// line and the button under it.
///
/// Proportions, corner and type scale come from ``TipcardProportions`` (nodes 9276:4641,
/// 9277:121417, 9277:121421, 9443:7991); the rest is below, in ``Layout``.
struct LinkUserCardContent: View {

    let state: LinkCard.User.State
    /// The `@handle` the link names, shown as the name when there is no account behind it.
    let linkedHandle: String?
    /// The card's width. Its type and corner are fractions of it, as on the tip card.
    let width: CGFloat
    var onButton: () -> Void = {}

    /// Values this card adds to ``TipcardProportions``. Named so Android can copy them one for one.
    enum Layout {
        /// The black over the frosted backdrop. The tip card draws 0.72 over a live blur; this card
        /// draws over a decoded BlurHash instead. Pending design sign-off.
        static let tintOpacity: Double = 0.6
        /// Inset from every edge of the card to its content.
        static let padding: CGFloat = 14
        static let avatar: CGFloat = 40
        /// The least room between the avatar and the name, when the card is at its minimum height.
        static let avatarGap: CGFloat = 16
        /// Between the handle and the joined line.
        static let joinedGap: CGFloat = 10
        static let joinedSize: CGFloat = 13
        static let joinedOpacity: Double = 0.45
        /// Between the card and the fee line, or the button when there is no fee.
        static let belowCardGap: CGFloat = 12
        static let feeSize: CGFloat = 15
        static let feeOpacity: Double = 0.5
        /// Between the fee line and the button.
        static let feeGap: CGFloat = 12
    }

    /// Button labels, Title Case.
    enum Copy {
        static let start = "Start Chatting"
        /// Provisional, pending design: what the viewer's own link offers in place of a chat.
        static let own = "View Your Card"
        static let notFound = "No Such Account"
    }

    var body: some View {
        VStack(spacing: 0) {
            card

            if case .resolved(let user) = state, let fee = user.fee {
                Text(fee)
                    .font(.default(size: Layout.feeSize, weight: .medium))
                    .foregroundStyle(Color.textMain.opacity(Layout.feeOpacity))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Layout.belowCardGap)
                    .padding(.bottom, Layout.feeGap)
            } else {
                Spacer().frame(height: Layout.belowCardGap)
            }

            button
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Card -

    private var cornerRadius: CGFloat { width * TipcardProportions.cornerRadiusFraction }
    private var nameSize: CGFloat { width * TipcardProportions.nameFraction }

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
        .frame(maxWidth: .infinity, minHeight: width * TipcardProportions.aspectRatio, alignment: .leading)
        .background { backdrop }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(GroupCardView.Layout.borderOpacity))
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let name {
                Text(name)
                    .font(.default(size: nameSize, weight: .bold))
                    .foregroundStyle(Color.textMain)
            }

            if case .resolved(let user) = state, let handle = user.handle {
                Text(handle)
                    .font(.default(size: nameSize, weight: .medium))
                    .foregroundStyle(Color.textMain)
                    .opacity(TipcardProportions.subtitleOpacity)
                    .padding(.top, width * TipcardProportions.subtitleGapFraction)
            }

            if case .resolved(let user) = state, let joined = user.joined {
                Text(joined)
                    .font(.default(size: Layout.joinedSize, weight: .medium))
                    .foregroundStyle(Color.textMain)
                    .opacity(Layout.joinedOpacity)
                    .padding(.top, Layout.joinedGap)
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

    /// The picture's BlurHash filling the card under the tip card's black, or the black over the
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

    // MARK: - Button -

    @ViewBuilder private var button: some View {
        switch state {
        case .notFound:
            Button(Copy.notFound) {}
                .buttonStyle(.filled20Compact)
                .disabled(true)
        case .resolved(let user) where user.isOwn:
            Button(Copy.own, action: onButton).buttonStyle(.filled20Compact)
        case .resolved:
            Button(Copy.start, action: onButton).buttonStyle(.filledCompact)
        }
    }
}
#endif
