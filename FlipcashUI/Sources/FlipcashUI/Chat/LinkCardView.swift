//
//  LinkCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import FlipcashCore

/// The card slot in a link bubble: one frame, one set of proportions, whichever kind of card the
/// message carries.
///
/// The kinds are laid out by the same rectangle on purpose. A transcript mixing a cash link and
/// a token link should read as one column of cards rather than two card sizes, and the bubble above
/// it switches on whether there is a card at all — not on which one. A group card has the same width
/// and takes its height from its content instead: it carries a button and text that grow with
/// Dynamic Type, and holds these proportions as its minimum. A person card is the exception: a
/// compact row that sets its own width and height, like a text bubble.
///
/// Every kind is built once and kept, hidden, rather than swapped in per dequeue: this sits in a
/// recycled row, and a transcript that alternates kinds would otherwise allocate a card per scroll.
///
/// This is also where a card's lookup lives. It paints whatever the source already knows, shimmers
/// if that is nothing, and then follows the source's stream for as long as the row holds this card.
@MainActor
final class LinkCardView: UIView {

    /// The proportions of the wallet's bill: 224pt of card across 328pt of usable width — its own
    /// height at full width less two screen insets on a 375pt phone. A chat bubble is a good deal
    /// narrower than that, and scaling the height with the width is what keeps a card a card there
    /// rather than a tall panel. Every kind's height, or for a group card its minimum. Not the person
    /// card's, which is as tall as its content.
    static let aspectRatio: CGFloat = 224.0 / 328.0

    private let cashView = LinkCashCardView()
    private let tokenView = LinkTokenCardView()
    private let groupView = LinkGroupCardView()
    private let userView = LinkUserCardView()
    let webView = LinkWebCardView()

    /// A card whose content sets the slot's height.
    private enum Sized { case group, user, web }

    /// Height at exactly the proportions, for a cash or token card.
    private var fixedHeight: NSLayoutConstraint!
    /// Height at least the proportions, for a group card, whose content may need more.
    private var minimumHeight: NSLayoutConstraint!
    /// Lets the group card's content set the slot's height. Only while a group card is showing: a
    /// hidden view still takes part in layout, and the group content's own height would otherwise
    /// hold every other kind of card open past its proportions.
    private var groupBottom: NSLayoutConstraint!
    /// The same, for the person card.
    private var userBottom: NSLayoutConstraint!
    /// The same, for the web card, which takes no height while it draws nothing.
    private var webBottom: NSLayoutConstraint!

    /// Whether a web card asks for its page as it draws or waits for its chip. Set before
    /// ``configure(with:source:)``.
    var webPreviewMode: WebLinkPreviewMode = .tapToLoad
    /// The web links this transcript's viewer has already asked to preview, so a recycled row does
    /// not put the chip back up in front of an answer they asked for.
    var webPreviewRequests = WebPreviewRequests()
    /// Where the web card's image comes from: the source the card was last configured with.
    private weak var imageSource: (any LinkCardSource)?

    /// Whether a web card that is still waiting on its page draws the placeholder: set for a message
    /// that is only its link, before ``configure(with:source:)``.
    var webShowsPlaceholder = false

    /// Whether a web card's page preview, or its placeholder, is drawn: what widens the bubble around
    /// it, and what a link-only message is drawn bare for.
    var drawsWebPreview: Bool {
        switch webView.content {
        case .preview, .placeholder: true
        case .nothing, .chip: false
        }
    }

    /// The subscription to the card currently shown. Cancelled before every reconfigure and on
    /// reuse: cells recycle, and a task outliving its card would paint one link's answer onto
    /// another link's row.
    private var subscription: Task<Void, Never>?

    /// Called when a group card's button, or a person card, is tapped.
    var onCardButton: (() -> Void)?

    /// Whether `point`, in this view's coordinates, is on one of the card's own buttons: the cash
    /// card's "Claim" pill, the group card's "View" or the web card's "Show preview" chip. These
    /// act on the first tap; the rest of a card takes the transcript's double tap.
    func hasButton(at point: CGPoint) -> Bool {
        if !cashView.isHidden, cashView.hasButton(at: convert(point, to: cashView)) { return true }
        if !groupView.isHidden, groupView.hasButton(at: convert(point, to: groupView)) { return true }
        if !webView.isHidden, webView.hasButton(at: convert(point, to: webView)) { return true }
        return false
    }

    /// The card's outline: `BubbleBackgroundView`'s radii for the card's place in its bubble run, so
    /// it groups with the bubbles around it exactly as a text bubble would. Every kind takes it,
    /// placeholder included.
    var cornerRadii = BubbleBackgroundView.standaloneRadii {
        didSet {
            cashView.cornerRadii = cornerRadii
            tokenView.cornerRadii = cornerRadii
            groupView.cornerRadii = cornerRadii
            userView.cornerRadii = cornerRadii
            webView.cornerRadii = cornerRadii
        }
    }

    /// Whether a web card stands on its own in place of its bubble.
    var webIsBare: Bool {
        get { webView.isBare }
        set { webView.isBare = newValue }
    }

    /// Called when an answer arriving after ``configure(with:source:)`` changes the card's height,
    /// so the row holding it can be measured again. Only a group or person card's height follows
    /// its content.
    var onHeightChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        for card in [cashView, tokenView] as [UIView] {
            card.translatesAutoresizingMaskIntoConstraints = false
            card.isHidden = true
            addSubview(card)
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: topAnchor),
                card.bottomAnchor.constraint(equalTo: bottomAnchor),
                card.leadingAnchor.constraint(equalTo: leadingAnchor),
                card.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        groupView.onStart = { [weak self] in self?.onCardButton?() }
        groupView.onHeightChange = { [weak self] in self?.onHeightChange?() }
        userView.onTap = { [weak self] in self?.onCardButton?() }
        userView.onHeightChange = { [weak self] in self?.onHeightChange?() }
        webView.onTap = { [weak self] in self?.onCardButton?() }
        webView.onImageChange = { [weak self] in self?.onHeightChange?() }
        for card in [groupView, userView, webView] as [UIView] {
            card.translatesAutoresizingMaskIntoConstraints = false
            card.isHidden = true
            addSubview(card)
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: topAnchor),
                card.leadingAnchor.constraint(equalTo: leadingAnchor),
                card.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        groupBottom = groupView.bottomAnchor.constraint(equalTo: bottomAnchor)
        userBottom = userView.bottomAnchor.constraint(equalTo: bottomAnchor)
        webBottom = webView.bottomAnchor.constraint(equalTo: bottomAnchor)

        // The card's proportions, not its size. One of the two is always live, including while
        // collapsed: a card with no width has no height either, so this stays consistent with the
        // bubble's zero-size constraints rather than fighting them.
        fixedHeight = heightAnchor.constraint(equalTo: widthAnchor, multiplier: Self.aspectRatio)
        minimumHeight = heightAnchor.constraint(greaterThanOrEqualTo: widthAnchor, multiplier: Self.aspectRatio)
        fixedHeight.isActive = true
    }

    /// Switches the slot between the fixed proportions of a cash or token card (nil), the content-set
    /// height over a minimum of a group card, and the content-set height of a person card.
    private func setSized(_ sized: Sized?) {
        groupView.isHidden = sized != .group
        userView.isHidden = sized != .user
        webView.isHidden = sized != .web
        // Deactivated before activated, so the slot never holds two heights at once.
        if sized != .group { groupBottom.isActive = false }
        if sized != .user { userBottom.isActive = false }
        if sized != .web { webBottom.isActive = false }
        switch sized {
        case nil:
            minimumHeight.isActive = false
            fixedHeight.isActive = true
        case .group:
            fixedHeight.isActive = false
            minimumHeight.isActive = true
        case .user, .web:
            fixedHeight.isActive = false
            minimumHeight.isActive = false
        }
        if sized == .group { groupBottom.isActive = true }
        if sized == .user { userBottom.isActive = true }
        if sized == .web { webBottom.isActive = true }
    }

    func prepareForReuse() {
        subscription?.cancel()
        subscription = nil
        cashView.prepareForReuse()
        tokenView.prepareForReuse()
        groupView.prepareForReuse()
        userView.prepareForReuse()
        webView.prepareForReuse()
        setSized(nil)
    }

    /// Shows `card` and keeps it up to date from `source`.
    ///
    /// Paints once from ``LinkCardSource/known(_:)`` — the answer if the link has been looked at
    /// this session, the unresolved card under a shimmer if it has not — and then subscribes either
    /// way. A known card subscribes too, because what arrives later is not only the first answer: a
    /// claim settling on this device, or the re-ask of a link still showing as claimable, reaches
    /// the row through the same stream. Its first element repeats what is already painted, which
    /// costs a redraw of values that have not changed.
    ///
    /// With no source the card paints unresolved and asks nothing, which is what a preview or a
    /// test that does not care about resolution gets.
    func configure(with card: LinkCard, source: (any LinkCardSource)?) {
        subscription?.cancel()
        subscription = nil

        imageSource = source
        webView.onShowPreview = nil
        let known = source?.known(card)
        show(card, state: known, loading: known == nil && source != nil)

        guard let source else { return }
        // A held answer costs no request, so it paints in either mode; the chip stands in for
        // the lookup until the viewer asks.
        if case .web(let web) = card, known == nil, awaitsChip(web) {
            webView.onShowPreview = { [weak self, weak source] in
                guard let self, let source else { return }
                webPreviewRequests.insert(web.url)
                configure(with: card, source: source)
                onHeightChange?()
            }
            return
        }
        subscribe(to: card, source: source)
    }

    /// Whether `web` waits behind the chip: a viewer outside the group who has not asked for it.
    private func awaitsChip(_ web: LinkCard.Web) -> Bool {
        switch webPreviewMode {
        case .automatic: false
        case .tapToLoad: !webPreviewRequests.contains(web.url)
        }
    }

    private func subscribe(to card: LinkCard, source: any LinkCardSource) {
        // Subscribed here rather than inside the task: a task body does not run until the caller
        // suspends, and an answer that lands in that gap would be yielded to nobody.
        let states = source.states(for: card)
        subscription = Task { [weak self] in
            for await state in states {
                guard let self, !Task.isCancelled else { return }
                if show(card, state: state, loading: false) { onHeightChange?() }
            }
        }
    }

    /// Hands `state` to the view for `card`'s kind. A state of another kind, or none at all, is
    /// the unresolved card: the source keys each kind separately, so this is unreachable, and
    /// drawing the link's own identity is the right answer if it ever is reached.
    /// - Returns: whether the card's height may have changed.
    @discardableResult
    private func show(_ card: LinkCard, state: LinkCard.State?, loading: Bool) -> Bool {
        switch card {
        case .cash:
            cashView.isHidden = false
            tokenView.isHidden = true
            setSized(nil)
            cashView.configure(with: Self.cashState(state), loading: loading)
            return false

        case .token(let token):
            cashView.isHidden = true
            tokenView.isHidden = false
            setSized(nil)
            tokenView.configure(with: token, state: Self.tokenState(state), loading: loading)
            return false

        case .group:
            cashView.isHidden = true
            tokenView.isHidden = true
            setSized(.group)
            return groupView.configure(with: Self.groupState(state), loading: loading)

        case .user(let user):
            cashView.isHidden = true
            tokenView.isHidden = true
            setSized(.user)
            return userView.configure(with: Self.userState(state), linkedHandle: user.linkedHandle, loading: loading)

        case .web(let web):
            cashView.isHidden = true
            tokenView.isHidden = true
            setSized(.web)
            webView.loadImage = { [weak self] url in await self?.imageSource?.webImage(for: url) }
            webView.cachedImage = { [weak self] url in self?.imageSource?.cachedWebImage(for: url) }
            let placeholder = webShowsPlaceholder && loading ? Self.displayHost(of: web) : nil
            return webView.configure(with: Self.webContent(
                state, chip: chipHost(web), placeholder: placeholder.map { ($0, web.url) }
            ))
        }
    }

    /// The chip's host when `web` waits behind the chip, else nil.
    private func chipHost(_ web: LinkCard.Web) -> String? {
        guard awaitsChip(web) else { return nil }
        return Self.displayHost(of: web)
    }

    /// The link's own host as the chip and placeholder show it, without its "www.".
    private static func displayHost(of web: LinkCard.Web) -> String {
        let host = WebLinks.host(of: web.url) ?? web.url.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// `.none` draws nothing. Loading draws the chip while it waits to be tapped, the placeholder for
    /// a link-only message, and otherwise nothing.
    private static func webContent(
        _ state: LinkCard.State?,
        chip host: String?,
        placeholder: (host: String, url: URL)?
    ) -> LinkWebCardView.Content {
        switch state {
        case .web(.resolved(let page)):
            return .preview(page)
        case .web(.none):
            return .nothing
        case .cash, .token, .group, .user, nil:
            if let host { return .chip(host: host) }
            if let placeholder { return .placeholder(host: placeholder.host, url: placeholder.url) }
            return .nothing
        }
    }

    private static func cashState(_ state: LinkCard.State?) -> LinkCard.Cash.State {
        switch state {
        case .cash(let cash):       cash
        case .token, .group, .user, .web, nil: .unresolved
        }
    }

    private static func tokenState(_ state: LinkCard.State?) -> LinkCard.Token.State {
        switch state {
        case .token(let token):     token
        case .cash, .group, .user, .web, nil: .unresolved
        }
    }

    /// Nil while nothing is known, which the group card draws as its shimmer when a lookup is out.
    private static func groupState(_ state: LinkCard.State?) -> LinkCard.Group.State? {
        switch state {
        case .group(let group):     group
        case .cash, .token, .user, .web, nil: nil
        }
    }

    /// Nil while nothing is known, which the person card draws as its shimmer when a lookup is out.
    private static func userState(_ state: LinkCard.State?) -> LinkCard.User.State? {
        switch state {
        case .user(let user):               user
        case .cash, .token, .group, .web, nil: nil
        }
    }
}
#endif
