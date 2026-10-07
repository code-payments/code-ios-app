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

/// The person card: a compact frosted row for a `flipcash.com/<handle>` or `flipcash.com/<uuid>`
/// link, tapped as a whole.
///
/// Built from the person's public profile only. Hosted the same way as ``LinkGroupCardView``: SwiftUI
/// content in a UIKit view, pinned to its fitted height at the card's width, a shimmer while the
/// lookup is out. Unlike the other link cards it hugs its content like a text bubble, so it reports
/// its content's width as its own and the row gives it no more than it asks for.
final class LinkUserCardView: UIView {

    /// Called when the card is tapped. Never for a card with no account behind it.
    var onTap: (() -> Void)?

    /// Called when the content's height at the card's width changes, so the row can be measured
    /// again.
    var onHeightChange: (() -> Void)?

    /// The card's outline, set by the row from the card's place in its bubble run.
    var cornerRadii = BubbleBackgroundView.standaloneRadii {
        didSet {
            guard cornerRadii != oldValue else { return }
            shimmer.roundCorners(to: cornerRadii)
            if let shown { draw(shown.state, handle: shown.handle) }
        }
    }

    /// What the card last drew, so a repeat of it is not reported as a change.
    private var shown: (state: LinkCard.User.State?, handle: String?, loading: Bool)?
    /// The width the content was last drawn at.
    private var drawnWidth: CGFloat = 0
    /// The content's width with room to spare: one line per text, before the row caps it.
    private var idealWidth: CGFloat = LinkUserCardContent.Layout.shimmerWidth

    private let content: any UIView & UIContentView
    /// Measures the card's ideal width; never on screen.
    private lazy var measurer = UIHostingController(rootView: AnyView(EmptyView()))
    /// The content's height at the card's actual width, as for ``LinkGroupCardView``.
    private var fittedHeight: NSLayoutConstraint!
    /// The shimmer's own height, held while it stands alone.
    private var shimmerHeight: NSLayoutConstraint!
    private let shimmer = LinkCardShimmerView(
        ground: UIColor(Color.backgroundRow),
        highlight: UIColor.white.withAlphaComponent(0.06)
    )

    override init(frame: CGRect) {
        // Made with the content type `configure` sets later: a hosting content view traps when
        // handed a configuration of a different content type.
        content = UIHostingConfiguration { LinkUserCardContent(state: .notFound, linkedHandle: nil) }
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
        shimmer.roundCorners(to: cornerRadii)
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
        shimmerHeight = heightAnchor.constraint(equalToConstant: LinkUserCardContent.Layout.shimmerHeight)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.textSizeChanged()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: idealWidth, height: UIView.noIntrinsicMetric)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != drawnWidth, let shown {
            draw(shown.state, handle: shown.handle)
        }
        if fit() { onHeightChange?() }
    }

    /// Pins the content to its height at the current width. Off while the shimmer stands alone,
    /// which takes its own fixed size instead.
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
    ///     on its own, at its own fixed size.
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
        idealWidth = showsShimmer ? LinkUserCardContent.Layout.shimmerWidth : measuredIdealWidth()
        invalidateIntrinsicContentSize()
        fit()
        return true
    }

    /// The content's width when nothing constrains it: each text on one line.
    ///
    /// Measured off to the side, on the card alone at its ideal size: the hosted content fills the
    /// row's width, which would report back whatever width it was offered.
    private func measuredIdealWidth() -> CGFloat {
        guard let shown else { return LinkUserCardContent.Layout.shimmerWidth }
        let typeSize = DynamicTypeSize(traitCollection.preferredContentSizeCategory) ?? .large
        measurer.rootView = AnyView(
            LinkUserCardContent(state: shown.state ?? .notFound, linkedHandle: shown.handle, fillsWidth: false)
                .fixedSize()
                .environment(\.dynamicTypeSize, typeSize)
        )
        return measurer.sizeThatFits(in: UIView.layoutFittingExpandedSize).width.rounded(.up)
    }

    /// Measures again at a new text size, which changes the card's width.
    private func textSizeChanged() {
        guard let shown, !(shown.loading && shown.state == nil) else { return }
        idealWidth = measuredIdealWidth()
        invalidateIntrinsicContentSize()
    }

    private func draw(_ state: LinkCard.User.State?, handle: String?) {
        drawnWidth = bounds.width
        let display = state ?? .notFound
        let radii = cornerRadii
        content.configuration = UIHostingConfiguration {
            LinkUserCardContent(state: display, linkedHandle: handle, cornerRadii: radii) { [weak self] in
                self?.onTap?()
            }
        }
        .margins(.all, 0)
    }
}

/// The person card's body: the person's avatar beside their name, handle and join date, on a
/// rounded frosted ground as wide as the text needs, and itself the tap target.
///
/// At accessibility text sizes the avatar moves above the text and every line wraps, where a row
/// would cut each one short. The border comes from the group card and the corners from the bubble run; the rest is in
/// ``Layout``.
struct LinkUserCardContent: View {

    let state: LinkCard.User.State
    /// The `@handle` the link names, shown as the name when there is no account behind it.
    let linkedHandle: String?
    /// Whether the card fills all the width it is given, as in the row, or reports only its own
    /// width, as when measured.
    var fillsWidth = true
    /// The card's outline: its place in the bubble run, or standalone when measured.
    var cornerRadii = BubbleBackgroundView.standaloneRadii
    var onTap: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize

    /// This card's own values. Named so Android can copy them one for one.
    enum Layout {
        /// The black over the decoded BlurHash backdrop. Pending design sign-off.
        static let tintOpacity: Double = 0.6
        static let avatar: CGFloat = 44
        /// Between the avatar and the text beside it, or above it at accessibility sizes.
        static let avatarGap: CGFloat = 12
        /// Above and below the content.
        static let verticalPadding: CGFloat = 10
        /// Before the avatar. Less than ``trailingPadding`` because the avatar's circle already
        /// leaves room at its edge.
        static let leadingPadding: CGFloat = 10
        /// After the text.
        static let trailingPadding: CGFloat = 16
        /// Between the lines of text.
        static let lineGap: CGFloat = 2
        /// The name wraps to this many lines before it ends in an ellipsis. Display names run to
        /// 64 Unicode scalars (`DisplayNameValidator.maxScalars`); the handle (15 characters at
        /// most) and the joined line always fit on one.
        static let nameLines = 2
        /// The handle, set in `appTextCaption` under the `appTextMedium` name.
        static let handleOpacity: Double = 0.5
        /// The joined line or the not-found line, set in `appTextCaption`.
        static let detailOpacity: Double = 0.45
        /// The shimmer's size while the lookup is out, near a typical resolved card's.
        static let shimmerWidth: CGFloat = 200
        static let shimmerHeight: CGFloat = 64
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

    private var outline: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
    }

    private var card: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Layout.avatarGap) { avatar; identity }
            } else {
                HStack(spacing: Layout.avatarGap) { avatar; identity }
            }
        }
        .padding(.vertical, Layout.verticalPadding)
        .padding(.leading, Layout.leadingPadding)
        .padding(.trailing, Layout.trailingPadding)
        // Fills the row, which is the card's own width unless a reply's quote widens it or the
        // column caps it at a large text size, so it always reaches the column's edge.
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .background { backdrop }
        .clipShape(outline)
        .overlay { outline.strokeBorder(Color.white.opacity(LinkCardMetrics.borderOpacity)) }
        .contentShape(outline)
    }

    /// The person's picture, or with no account the generic person glyph: an empty name gives the
    /// avatar no initials to draw.
    private var avatar: some View {
        Group {
            switch state {
            case .resolved(let user):
                ContactAvatarView(
                    id: user.avatarID,
                    displayName: user.displayName,
                    imageData: user.imageData,
                    blurhash: user.blurHash,
                    size: Layout.avatar
                )
            case .notFound:
                ContactAvatarView(id: "", displayName: "", size: Layout.avatar)
            }
        }
        .overlay { Circle().strokeBorder(Color.white.opacity(LinkCardMetrics.borderOpacity)) }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: Layout.lineGap) {
            if let name {
                Text(name)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(lineLimit(Layout.nameLines))
            }

            if case .resolved(let user) = state, let handle = user.handle {
                Text(handle)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                    .opacity(Layout.handleOpacity)
                    .lineLimit(lineLimit(1))
            }

            if let detail {
                Text(detail)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                    .opacity(Layout.detailOpacity)
                    .lineLimit(lineLimit(1))
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `lines` in the row; unlimited at accessibility sizes, where the stacked layout wraps rather
    /// than cutting a line short.
    private func lineLimit(_ lines: Int) -> Int? {
        typeSize.isAccessibilitySize ? nil : lines
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
