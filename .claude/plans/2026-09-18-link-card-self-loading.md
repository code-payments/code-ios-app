# Link cards load themselves

Moving link-card resolution out of the transcript's load pass and into the card view, with a
loading state. Shipped behaviour today is in [#795](https://github.com/code-payments/code-ios-app/pull/795).

**Status:** design approved, implementation not started.

---

## What happens today

Opening a chat with an unresolved link card blanks the transcript for up to two seconds.
[`ConversationLoadCoordinator`](../../Flipcash/Core/Screens/Conversation/ConversationLoadCoordinator.swift)
paints synchronously, then `holdFirstPaintForCards()` throws the rows away, sets `awaitsFirstCards`,
and waits on the lookups behind a `firstPaintWait` deadline of 2s. Every answer lands in a
`cardStates` dictionary and calls `refresh`, which re-maps the whole window.

The hold exists for a good reason: without it a cash card paints as a blank white ticket and turns
claimed under the reader a hop later. It buys that by making the transcript wait on a network call
that has nothing to do with the messages in it.

The card views are passive. `LinkCashCardView.configure(with:)` and `LinkTokenCardView.configure(with:)`
switch on a two-case state — `.unresolved` or `.resolved` — where `.unresolved` also stands for
"the lookup failed, timed out, or never ran".

## The change

The card owns its own lookup and shows that it is working. The transcript paints immediately and
never waits.

Three properties of the existing code make this cheaper than it sounds:

- **The card's height does not depend on its contents.** `LinkCardView` pins height to width by a
  fixed aspect ratio, so loading to resolved cannot change a row's height. No re-measure, no scroll
  jump. This is the constraint that usually kills self-loading rows, and it is already satisfied.
- **A synchronous read of prior answers already exists.**
  [`LinkCardMemo`](../../Flipcash/Core/Screens/Conversation/LinkCardMemo.swift) holds what the
  resolver has answered, on the main actor, readable without awaiting.
- **`LinkCardResolver` is an actor that memoizes per key**, so several rows quoting one link still
  make one query.

## The seam

`FlipcashUI` is a package and cannot reach `Client` or `LinkCardResolver`. So the card asks for its
contents through a protocol the UI package owns, and the app target conforms:

```swift
public protocol LinkCardSource: Sendable {
    /// What is already known about this card, without suspending — nil if nothing is.
    @MainActor func known(_ card: LinkCard) -> LinkCard.State?

    /// Every state this card takes, first answer onward. Ends when the caller stops iterating.
    func states(for card: LinkCard) -> AsyncStream<LinkCard.State>
}
```

The two methods answer different questions. `known` is what stops a scroll-in from shimmering over a
link already resolved this session — the job `LinkCardMemo` was added for. `states` is the
suspension, and everything that happens to the card after it.

The app-target conformance wraps today's `LinkCardResolver` and `LinkCardMemo` in one object. It is
injected down the route `onLinkCardTap` already takes: `ChatScreenRepresentable` →
`ChatScreenViewController` → `ChatViewController` → cell → `LinkableBubbleView` → `LinkCardView`.

## State leaves the transcript

`LinkCard.Cash` and `LinkCard.Token` lose their `state` field. The transcript carries identity —
url, entropy or mint, range — and the card view owns state. That removes `applying(_:)`,
`isUnresolved`, the `state` computed var, and `Inputs.cardStates`. `resolutionKey` stays; it is what
the source keys on.

The consequence worth the churn: `ChatItem` equality no longer changes when a lookup lands, so
resolving a card cannot touch the collection view's diff.

Blast radius is contained. `state` appears only in the coordinator, the `LinkCard` extension in
[`LinkCardResolver.swift`](../../Flipcash/Core/Screens/Conversation/LinkCardResolver.swift),
`LinkCardClassifier`, the two card views, and tests.

## The card view

`configure(with:source:)` branches once:

- `source.known(card)` returns a state — paint it. No shimmer, no task.
- It returns nil — paint the existing unresolved rendering, start the shimmer, and start a task
  iterating `states(for:)`. The first element stops the shimmer.

The task is held on the view and cancelled in `prepareForReuse`, and on reconfigure when the
incoming card's `resolutionKey` differs. Cells recycle, so a task outliving its card would paint one
link's answer onto another link's row. This is the one new failure mode the change introduces and
the main thing tests need to pin down.

## The shimmer

There is nothing to reuse. The only skeleton in the codebase is `CurrencyDiscoverySkeletonRow`, a
SwiftUI view using `.redacted(reason: .placeholder)`, which is no help to these `CALayer`-drawn
cards. So: a small shimmer layer, a `CAGradientLayer` highlight band swept across the card.

One sweep across the whole card, not one per label. The unresolved token card names the mint's
abbreviated address, which is real content — it is what the raw link text showed — and shimmering
that label alone would tell the reader it is a placeholder.

Two lifecycle rules. Stop on `didMoveToWindow`, so rows scrolled offscreen are not animating. Honour
Reduce Motion with a static dim rather than a sweep.

Failure changes nothing visible except that the shimmer stops. The card stays as it is, because the
link underneath still works — the rule the current design states explicitly, and the reason neither
card kind has an error state.

## Refreshes move to the source

Two things currently live in the coordinator and outlast first paint: the 15s re-ask for cards still
showing as claimable (`claimableRefresh`), and the invalidation that fires when a claim settles on
this device (`observeSettledClaims`, reading `session.cashLinkClaims`).

Both move into the source, which yields the new state into the stream the card is already iterating.
The coordinator is then left with no card code at all.

This also makes the cadence match its stated intent. The comment on `claimableRefresh` says a card
re-asks "while they are looking at it", but the current implementation refreshes every claimable card
in the window whether or not it is on screen. Driven by a subscription that exists only while a card
is configured, it refreshes what is actually being looked at.

## What the coordinator loses

`holdFirstPaintForCards`, `firstPaintDeadline`, `awaitsFirstCards`, `firstPaintWait`,
`releaseFirstPaint`, `resolveCards`, `unansweredCards`, `ask`, `land`, `landCardState`,
`startClaimableRefresh`, `refreshClaimableCards`, `reresolveCash`, `cashCards`,
`observeSettledClaims`, `cardStates`, `cardsInFlight`, and `cardMemo`.

## Tests

`LinkCardLandingTests` covers `land`, which goes away; its cases move onto the source's stream.
`LinkCardResolverTests` and `LinkCardClassifierTests` are unaffected apart from the `state` argument
leaving the initialisers.

Worth adding:

- Recycling. Configure card A, reuse the cell, configure card B, then let A's answer arrive. B must
  be untouched.
- A `known` hit paints resolved with no shimmer and no subscription.
- A failed lookup stops the shimmer and leaves the card unresolved.
- A claimable card's refresh reaches an on-screen card through the stream.

## Open question

Whether the source should cancel an in-flight lookup when its last subscriber goes away. Cancelling
frees a request for a card scrolled past quickly; not cancelling means the answer is memoized and
ready if the reader scrolls back. Leaning toward not cancelling, on the grounds that the resolver
already memoizes failures to stop retry storms, but this is not settled.
