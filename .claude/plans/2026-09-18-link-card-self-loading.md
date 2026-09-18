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

Shimmer only what is genuinely absent until the lookup lands. Both cards already say true things
while unresolved, and a shimmer over a correct value tells the reader it is a guess.

On the cash card that means the amount and the stub slots, and *not* the type row: unresolved it
reads "Cash Link", a brand constant that refines to the token's name on resolve. Android reached the
same conclusion independently about its own equivalent label.

The token card carries the mint's abbreviated address, which is correct-then-refined in the same
way, so its text does not shimmer either. What shimmers is the bill surface: unresolved, the
gradient is the neutral row colour standing in for branding nobody has fetched, which makes it the
one part of that card that really is a placeholder. Sweeping the surface says the look is still
coming without implying the address is a guess.

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

Deleted outright: `holdFirstPaintForCards`, `firstPaintDeadline`, `awaitsFirstCards`,
`firstPaintWait`, `releaseFirstPaint`, `resolveCards`, `unansweredCards`, `ask`, `land`,
`landCardState`, `cardStates`.

Moved into the source rather than deleted: `startClaimableRefresh`, `refreshClaimableCards`,
`reresolveCash`, `cashCards`, `observeSettledClaims`, and `cardMemo`.

`cardsInFlight` needs care. It looks like a deletion but its job — deduplicating concurrent asks for
one link — is load-bearing, and the source picks it up by memoizing a `Task` per key. See
[Cancellation](#cancellation-and-what-android-already-settled).

## Tests

`LinkCardLandingTests` covers `land`, which goes away; its cases move onto the source's stream.
`LinkCardResolverTests` and `LinkCardClassifierTests` are unaffected apart from the `state` argument
leaving the initialisers.

Worth adding:

- Recycling. Configure card A, reuse the cell, configure card B, then let A's answer arrive. B must
  be untouched.
- A `known` hit paints resolved with no shimmer and no subscription.
- A failed lookup stops the shimmer, leaves the card unresolved, and is not remembered — the next
  appearance asks again.
- A claimable card's refresh reaches an on-screen card through the stream.
- Two rows quoting one link make one query. This is the `cardsInFlight` guarantee moving house, and
  the current actor cannot make it on its own.

## Cancellation, and what Android already settled

A lookup is not cancelled when its last subscriber goes away. It is bounded by the chat screen
instead.

Android answered this first and the reasoning transfers. Its `LinkCardResolver` memoizes **the
query, not the answer** — a `Deferred` per key, launched in a scope the resolver owns — so a
consumer that dies mid-await cancels only its own await. The query finishes and the next reader
takes the answer. The scope is `@ViewModelScoped` and ended by `ChatViewModel.onCleared`, so the
cache dies with the screen and re-entering a chat asks again.

iOS should adopt the same shape, because it also fixes a hole here. `LinkCardResolver.cashState`
checks its cache, then awaits the lookup, then writes. On an actor that `await` is a suspension
point, so two concurrent `resolve` calls for one key both miss the cache and both query. Today
`ConversationLoadCoordinator.cardsInFlight` hides it by deduplicating at the call site on the main
actor — which means the deduplication disappears along with the coordinator's card code unless it
moves.

So the source holds a `Task` per key rather than a `LinkCard.State` per key. Every subscriber awaits
the same task, cancelling a subscriber cancels nothing, and the source is torn down with the
conversation. One change closes the re-entrancy gap, replaces `cardsInFlight`, and settles
cancellation.

## Failures are forgotten, not recorded

The two platforms currently cache failures in opposite directions, each correctly for its own
architecture.

Android forgets a failure, so the next pass asks again: holding one "means one bad moment decides
the card until the reader leaves the chat and comes back". iOS records it, because `landCardState`
is reached from a re-map that runs on every observation tick, and a remembered failure is what stops
a scrolling transcript retrying continuously.

This refactor removes iOS's reason. Once the card drives its own ask, there is no per-tick re-map —
the ask happens once per appearance, which is far rarer. Converging on Android's behaviour then
looks better: a card that failed while offline resolves when the reader scrolls back to it after
reconnecting, instead of staying dead for the visit.

So: forget. The accepted cost is that a failing card re-shimmers each time it appears. If that reads
badly in practice, the fallback is to keep forgetting but hold a short cooldown per key.
