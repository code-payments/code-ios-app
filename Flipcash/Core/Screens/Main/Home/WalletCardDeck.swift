//
//  WalletCardDeck.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// Opening and closing a token card from a ``TokenCardStack``: the deck clears
/// around the tapped card as it lifts to the top, the currency page comes in
/// behind it, and closing puts the card back into its slot. Held by each screen
/// that shows the stack — today's wallet, and the currencies screen Money pushes
/// — and read by the stack and by ``View/walletCardPage(_:close:)``.
///
/// `@State` fields in a `DynamicProperty`, not an `@Observable` class as the
/// named-unit rule would usually have it. ``open(_:currentTop:safeAreaTop:alongside:)``
/// sets `heroOffset` to the tapped card's slot without animation and then
/// animates it to zero, in the same turn that builds the page. `@State` keeps
/// each write with its own transaction, so the page starts from the slot. An
/// observable class hands the new page only the final zero, and the card
/// appears at the top of the page instead of travelling up to it.
///
/// Read it only from the body of the screen that holds it.
@MainActor
struct WalletCardDeck: DynamicProperty {

    /// The card being opened. The deck reorganises around it and the detail
    /// panel rises beneath it.
    @State private(set) var expandingMint: PublicKey?
    /// How far the page's hero card is displaced from its resting slot. Seeded
    /// with the tapped card's position in the deck and animated to zero, so the
    /// card the page shows *is* the card that travels — there is no copy laid
    /// over the top, and it belongs to the page's scroll view the whole time.
    @State private(set) var heroOffset: CGFloat = 0
    /// The slot the deck leaves empty while that card is drawn elsewhere.
    @State private(set) var hiddenMint: PublicKey?
    /// Released once the transition has settled, letting the page build its
    /// chart and read its activity without stuttering the animation.
    @State private(set) var heavyContentReady = false
    /// Brings the page in behind the travelling card: everything except the
    /// card itself, which is continuous.
    @State private(set) var pageContentOpacity: Double = 0
    /// Whether the page exists yet. Split from its fade so the cost of
    /// building it is paid on its own runloop turn, while the card is already
    /// in flight, rather than on the frame it becomes visible.
    @State private(set) var pageIsBuilt = false
    /// Fades what the deck sits on — balance header included — out behind the
    /// opening card.
    @State private(set) var deckOpacity: Double = 1
    /// Where a pull-to-close let go of the card, so the deck picks it up there
    /// rather than snapping it back to its open slot first. Animated to zero as
    /// the close carries it home.
    @State private(set) var releasedPullOffset: CGFloat = 0
    /// Drives the deck's reorganisation, 0 (resting) to 1 (cleared), animated in
    /// lockstep with the card's flight so the two read as one gesture.
    @State private(set) var expansionProgress: CGFloat = 0
    /// Identifies the transition currently in flight. Opening and closing both
    /// finish their work in callbacks — an animation completion, and a delayed
    /// page fade — which keep running even once the transition that scheduled
    /// them has been replaced. Each captures the token it started with and does
    /// nothing if it no longer matches, so a close settling in the background
    /// cannot tear down the open that interrupted it.
    @State private var transitionToken = 0

    static let liftDuration: TimeInterval = 0.32
    /// What the deck sits on is gone before the page starts arriving, so the
    /// two never cross-fade over each other.
    static let walletFadeDuration: TimeInterval = 0.16
    /// How far behind the card the page follows.
    static let pageFollowDelay: TimeInterval = 0.20

    /// Opens a token: the deck reorganises around the tapped card, which stays
    /// on screen while the detail panel rises beneath it.
    ///
    /// - Parameters:
    ///   - currentTop: The tapped card's top edge in global space, as the stack
    ///     reports it.
    ///   - safeAreaTop: The host's top safe-area inset, which the page's own
    ///     layout starts below.
    ///   - alongside: Work the host does in the same un-animated step, ahead of
    ///     the motion.
    func open(_ mint: PublicKey, currentTop: CGFloat, safeAreaTop: CGFloat, alongside: () -> Void = {}) {
        transitionToken &+= 1
        let token = transitionToken

        // Everything that costs a frame happens in this one un-animated step, so
        // the animation that follows is pure interpolation.
        var seed = Transaction()
        seed.disablesAnimations = true
        withTransaction(seed) {
            // The page's own hero card starts over the deck slot the tapped
            // card occupies, so the two coincide exactly on the first frame.
            heroOffset = (currentTop - safeAreaTop) - WalletCardGeometry.openCardTopInset
            pageContentOpacity = 0
            pageIsBuilt = false
            expansionProgress = 0
            expandingMint = mint
            hiddenMint = mint
            // Both of these can block the main thread for a few frames — hiding
            // the tab bar (the wallet's `alongside`) relayouts the whole
            // `TabView`, and building the page runs its view model's synchronous
            // metadata read and decode. They are done here, before the animation
            // below is committed, so the cost lands as a short pause on the tap
            // rather than as a stall part-way through the flight. SwiftUI's
            // spring animations are driven on the main thread, so work deferred
            // until *after* the commit does not run alongside the motion — it
            // interrupts it.
            alongside()
            pageIsBuilt = true
        }

        // The card's flight and the deck's reorganisation are one animation: the
        // cards above collapse into the opened card's slot and the ones below run
        // off the bottom exactly as it lifts away.
        //
        // The hand-off is driven by the animation finishing rather than by a
        // matching sleep: a spring is still settling when its nominal duration
        // is up, so on a timer the flying card is still short of its mark when
        // the page's hero card appears at the final position. The two are then
        // drawn a few points apart, which reads as the card juddering into
        // place. `.removed` fires once it has actually stopped.
        withAnimation(.smooth(duration: Self.liftDuration), completionCriteria: .removed) {
            heroOffset = 0
            expansionProgress = 1
        } completion: { [self] in
            guard token == self.transitionToken else { return }
            // Everything has come to rest, so the chart can fetch its points and
            // draw for real inside the space it has been holding all along.
            self.heavyContentReady = true
        }

        // What the deck sits on clears ahead of the deck, so the screen is
        // already dark by the time the page starts coming up. Fading the two
        // across each other instead shows the balance and the cards straight
        // through the tiles for the length of the overlap.
        withAnimation(.easeOut(duration: Self.walletFadeDuration)) { deckOpacity = 0 }

        // The card leads and the page follows it in, sharing its curve so the
        // two read as one movement. Delayed rather than dispatched later, so
        // both are committed in the same frame and cannot drift apart, and run
        // long enough that the page is not sitting complete while the card is
        // still travelling.
        withAnimation(.smooth(duration: Self.liftDuration).delay(Self.pageFollowDelay)) {
            pageContentOpacity = 1
        }
    }

    /// Arrives in the opened state without the travel — for a deep link, where
    /// there is no tap to have come from and the card may not even be on screen
    /// to start from. Everything lands where the opening animation would have
    /// left it, so closing still puts the card back into the deck normally.
    func openImmediately(_ mint: PublicKey, alongside: () -> Void = {}) {
        transitionToken &+= 1

        var immediate = Transaction()
        immediate.disablesAnimations = true
        withTransaction(immediate) {
            heroOffset = 0
            releasedPullOffset = 0
            expansionProgress = 1
            deckOpacity = 0
            pageContentOpacity = 1
            expandingMint = mint
            hiddenMint = mint
            alongside()
            pageIsBuilt = true
            heavyContentReady = true
        }
    }

    /// Closes a token: the reverse of opening. The page drops away and the deck
    /// takes its card back, sliding it down into its own slot and under the
    /// cards stacked on top of it — put back, rather than simply vanishing.
    ///
    /// - Parameters:
    ///   - pullOffset: Where a pull-to-close let go of the card.
    ///   - restoresContentAtOnce: Brings back what the page was covering in the
    ///     close's first frame instead of fading it in with the deck — for a
    ///     screen with no deck to fade back.
    ///   - alongside: Work the host does in the same un-animated step, ahead of
    ///     the motion. Not run when no card is open.
    func close(resumingFrom pullOffset: CGFloat = 0, restoresContentAtOnce: Bool = false, alongside: () -> Void = {}) {
        guard expandingMint != nil else { return }
        transitionToken &+= 1
        let token = transitionToken

        // Hand the card to the deck before anything moves. It is already sitting
        // at the open position (the stack holds it there while `progress` is 1),
        // so this swap is invisible — and from here the deck owns the return,
        // which is what lets the card go *under* its neighbours on the way home.
        var handback = Transaction()
        handback.disablesAnimations = true
        withTransaction(handback) {
            hiddenMint = nil
            // Hand the card over at the height the finger left it at, so the
            // close picks up from there instead of jumping back to the open slot
            // and replaying from the top.
            releasedPullOffset = pullOffset
            pageContentOpacity = 0
            pageIsBuilt = false
            heavyContentReady = false
            // Money is what the page was covering, and it was faded out when the
            // card opened. Fading it back in after the page has gone leaves a
            // frame with neither drawn, so it returns in this same step.
            if restoresContentAtOnce { deckOpacity = 1 }
            // The wallet brings its tab bar back here, before the motion, for the
            // same reason it is hidden before the opening one: restoring it
            // relayouts the whole `TabView`. Left until the animation finishes,
            // that cost lands *after* the deck has settled and the bar visibly
            // arrives late.
            alongside()
        }

        // `expandingMint` has to stay put for the duration: it is the anchor the
        // reorganisation is measured against, and clearing it here would swap the
        // deck back to its resting formula in one frame instead of unwinding it.
        withAnimation(.smooth(duration: Self.liftDuration), completionCriteria: .removed) {
            expansionProgress = 0
            deckOpacity = 1
            releasedPullOffset = 0
        } completion: { [self] in
            // Only if this close is still the current transition: tapping a card
            // again while it settles starts an open, and clearing the anchor then
            // would strand the wallet with its header faded out and no page.
            guard token == self.transitionToken else { return }
            // The deck is back in its resting fan, so the anchor can go. Waiting
            // for the animation rather than a matching sleep matters here too:
            // clearing it while the spring is still settling drops the cards the
            // last few points in one frame.
            withTransaction(handback) {
                self.expandingMint = nil
            }
        }
    }

    /// Recedes the screen under a pull-to-close: the info content and chrome
    /// fade out. The deck is deliberately left as it is — reassembling it under
    /// the finger leaves the card nothing to hand over to when the drag ends,
    /// and the stack reading through a half-faded page is not what the gesture
    /// should look like anyway. It comes back on release, carrying the card home
    /// with it.
    ///
    /// The card's *position* is left alone too: the scroll view's overscroll
    /// already carries it down a point per point, and driving its journey back
    /// to the deck on top of that sends it several times faster than the drag.
    ///
    /// Un-animated on purpose. This tracks a finger, so each update is the
    /// current position rather than something to interpolate towards.
    func scrubDismiss(_ progress: CGFloat) {
        guard expandingMint != nil else { return }
        var tracking = Transaction()
        tracking.disablesAnimations = true
        withTransaction(tracking) { pageContentOpacity = 1 - progress }
    }

    /// A pull-to-close let go short of the threshold: put the page back.
    func cancelPull() {
        guard expandingMint != nil else { return }
        withAnimation(.smooth(duration: 0.25)) { pageContentOpacity = 1 }
    }
}

extension View {

    /// The currency page for the card `deck` has open, laid over this screen.
    /// Once the deck has finished reorganising, the page takes over the whole
    /// screen with its hero card on the same spot the deck parked the opened
    /// card — so the swap is invisible and the page scrolls as one, card
    /// included.
    ///
    /// `close` closes the card, resuming from where a pull let go of it.
    func walletCardPage(_ deck: WalletCardDeck, close: @escaping (_ resumingFrom: CGFloat) -> Void) -> some View {
        overlay {
            // Built once the card is already in flight, but held invisible
            // until it is most of the way there.
            if deck.pageIsBuilt, let mint = deck.expandingMint {
                CurrencyInfoScreen(
                    mint: mint,
                    presentation: .overlay(
                        onClose: { close(0) },
                        heroOffset: deck.heroOffset,
                        contentOpacity: deck.pageContentOpacity,
                        onPull: deck.scrubDismiss,
                        onPullEnded: { passedThreshold, releasedAt in
                            if passedThreshold {
                                close(releasedAt)
                            } else {
                                deck.cancelPull()
                            }
                        }
                    ),
                    defersHeavyContent: !deck.heavyContentReady
                )
                .id(mint)
                // Fades in behind the card rather than sliding, which would
                // drag the chrome and tiles in from the bottom. The deck is
                // clearing underneath, so nothing shows through.
                .background(Color.backgroundMain.opacity(deck.pageContentOpacity))
                // Deliberately no edge-swipe back. The screen is lifted over
                // the screen with the deck rather than pushed onto it, and its
                // chrome says so with a close box instead of a back chevron.
            }
        }
    }
}

extension TokenCardData {

    /// One card per balance, in the order given. Resolves each token's bill
    /// colors once (a DB read per token), so a screen keeps the result rather
    /// than building it per body evaluation.
    static func walletCards(for balances: [ExchangedBalance], session: Session, rate: Rate) -> [TokenCardData] {
        balances.map { balance in
            let (value, isPositive) = balance.stored.computeAppreciation(with: rate)
            // The pill always shows (per Figma). A sub-cent value rounds to
            // "$0.00" and reads as positive, so a tiny negative never renders "-$0.00".
            let roundsToZero = value.nativeAmount.value < 0.005
            let appreciationText = (isPositive || roundsToZero ? "+" : "-") + value.nativeAmount.formatted()
            return TokenCardData(
                mint: balance.stored.mint,
                name: balance.stored.name,
                imageURL: balance.stored.imageURL,
                balanceText: balance.exchangedFiat.nativeAmount.formatted(),
                appreciationText: appreciationText,
                colors: session.billColors(for: balance.stored.mint),
                isUSDF: balance.stored.mint == .usdf
            )
        }
    }
}
