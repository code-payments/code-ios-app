# Architecture & Patterns

## Design Pattern: MVVM + Container DI

```
Container (DI)
├── Client (gRPC)
├── FlipClient (Flipcash APIs)
├── AccountManager (Keychain)
└── SessionContainer (when logged in)
    ├── Session (main state, @Observable)
    ├── RatesController
    │   ├── VerifiedProtoService (actor – caches verified exchange rate + reserve state proofs)
    │   └── LiveMintDataStreamer (actor – bidirectional streaming for rates/reserves)
    ├── HistoryController
    └── Database (SQLite)
```

- **ViewModels** provide over multi-screen flows or complex navigation patterns but not necessary for standalone, self-contained, isolated screens.
- **Session** is the main state object after authentication
- **Controllers** handle business logic and data persistence

**Injected via the environment, not init prop-drilling.** `Container` and `SessionContainer` are both `@Observable` (the latter is a class) and injected with `.environment(self)` inside their `injectingEnvironment(from:)` helpers — `Container` at the app root (app-wide), `SessionContainer` on `ScanScreen` in `ContainerScreen`'s `.loggedIn` case (logged-in subtree). Read them with type-based `@Environment(Container.self)` / `@Environment(SessionContainer.self)`; sheets and `navigationDestination`s inherit them. A screen that builds its view model or seeds `@State` in `init` can't read `@Environment` there — split it into a thin env-reading wrapper (`struct X`) over an unchanged content view (`struct XContent`) whose `init` takes the deps. Reach for a granular env value (`@Environment(SessionAuthenticator.self)`, etc.) when a screen needs only one member; read the whole container otherwise.

## gRPC Call Options (v2)

Per-RPC deadlines are passed via `GRPCCore.CallOptions` on each call — there is no shared `CodeService` preset anymore. The v1 rule still holds in the v2 shape:

| RPC kind | Deadline | How |
|----------|----------|-----|
| **Unary** (request → response) | 15 seconds | pass `options: .unaryDefault` (defined in `GRPCTransport.swift`) |
| **Server-streaming / bidirectional** | None | pass nothing (`.defaults`) — a stray deadline silently kills long-lived streams |

Streaming RPCs run through the `BidirectionalGRPCStream` / `ServerGRPCStream` adapters in `GRPCStream.swift`, which bridge v2's closure-scoped streaming (`requestProducer:` / `onResponse:`) to a retained, multi-sender handle (`sendMessage` / `cancel`). The transport and the shared `UserAgentClientInterceptor` are configured once on the `GRPCClient` in `Client.swift` / `FlipClient.swift`; the `runConnections()` task must stay retained for the client's lifetime.

## Transport Failure Classification

A gRPC transport failure (request timeout / unavailable channel) is a network condition, not a code defect — it must never reach Bugsnag. The `TransportClassifiableError` protocol carries this guarantee.

- **Typed error enums:** conform the enum to `TransportClassifiableError` — the compiler then requires all four transport cases (`.transportFailure` suppressed, `.cancelled` info, `.rejected` error, `.unknown` error) and the exhaustive `reportingLevel` forces you to classify them. In the call's `catch` map via `ErrorX.from(transportError: rpcError)`; the single shared default routes deterministic refusals (auth, precondition, bad argument) to `.rejected` and anomalies to `.unknown`. Retry loops gate on the shared `isRetryable` (`.unknown`/`.transportFailure` only) — never hand-roll the classification per call site, and never map a timeout to an `.error`-level `.unknown`.
- **Associated-value error enums** (cases like `.grpcStatus(RPCError)` / `.network(Error)`): return `.suppressed` from `reportingLevel` when the captured error is transient (`rpcError.code.isTransientNetworkError`), and forward `.grpcStatus(s)` / `.network(e)` to the inner value's `reportingLevel` (`(error as? ServerError)?.reportingLevel ?? .error`), mirroring `ErrorSubmitIntent` / `ErrorSwap` / `ErrorStatelessSwap` / `ErrorModeration`.
- **Unary RPCs whose failure type is the existential `Error`:** `RPCError` itself conforms to `ServerError`, mapping transient codes (`isTransientNetworkError`) to `.suppressed`, `.cancelled` to `.info` (app-initiated teardown, not a defect), and all other codes to `.error`, so shipping the raw error via `completion(.failure(error))` classifies transient transport failures automatically — no per-call-site mapping needed.
- `FlipcashCoreTests/TransportClassificationTests` asserts every conformer is wired — add ONE registry line when you add a classifiable error; it pins classification, severity parity, and retryability together.

## Navigation: AppRouter

All navigation flows through `AppRouter` — a single `@Observable @MainActor` class on `SessionContainer`, injected via `@Environment(AppRouter.self)`. **Don't add screen-level `@State` sheet flags or `selectedXxx` bindings for navigation** — mutate the router instead. Deeplinks and push notifications call `router.navigate(to:)`; in-screen pushes call `router.push(_:on:)`.

Top-level sheets (`Balance`, `Settings`, `Give`, `Discover`) each own a `NavigationStack(path: $router[.<stack>])` and register destinations via the `.appRouterDestinations(...)` modifier on their root content. Per-stack paths are `NavigationPath` (type-erased), so sub-flow destinations (e.g., `WithdrawNavigationPath`, `BuyFlowPath`) coexist with top-level `Destination` cases on the same stack — register `.navigationDestination(for: SubFlowPath.self)` on the sub-flow root view and push via `router.pushAny(_:on:)`. **Don't nest a `NavigationStack` inside another stack's destination** — push/pop/push corrupts SwiftUI's stack state with `comparisonTypeMismatch`.

**Nested sheets.** `presentedSheets` is an ordered stack: `.first` is the root sheet (mounted at app root) and any entries above visually stack on top. Use `router.presentNested(.x(...))` to stack a sheet on top of the current top — required for "sheet over sheet" UX like buy-from-currency-info. SwiftUI requires nested sheets to be mounted from **inside** the parent sheet's content tree (sibling `.sheet` modifiers at the root can't stack), so each top-level sheet's content applies the `.appRouterNestedSheet(...)` modifier — that's the convention. New top-level sheets must remember to apply it; the modifier handles all nested levels via env-injected `nestedSheetDepth`. The buy flow is the only nested sheet today (`.buy(mint)`); sell/give/etc. are migrating opt-in.

**Local interaction sheets stay local.** Transient pickers (currency selection, funding selection) belong on the screen that owns them as `.sheet(...)` / `.fullScreenCover(...)` modifiers — they're interactions, not navigation. Operation-bound modals (swap/launch processing covers) similarly belong locally, *unless* they're part of a router-managed sheet's flow — in that case prefer pushing onto the sheet's stack as a `BuyFlowPath.processing` (or similar) so the sheet's dismiss tears down the whole chain.

**The test:** if a deeplink could reasonably land the user here, it's a destination — route through `AppRouter`. If not, keep it local.

**Sheet path lifecycle.** `dismissSheet` pops the topmost sheet and leaves its `NavigationPath` populated so the closing animation runs with current contents. The path is cleared on the next `present(_:)` or `presentNested(_:)` of that same sheet value, so re-opens land at root. Sheet swaps at root (`present(.different)` without an intervening `dismissSheet`) preserve the swapped-out root's path for swap-back; nested sheets above a swapped root are always dismissed (and their paths cleared on re-open). `present(.sameRoot)` while a nested sheet is up pops the nested and keeps the root path. Don't add manual `popToRoot` calls around your own dismissal — let the router handle it.

Every router mutation logs one INFO entry under `flipcash.router` — filter by that label to trace any navigation interaction.

## Key Architectural Concepts

1. **Quarks** - Smallest unit of any currency (like cents for dollars)
2. **ExchangedFiat** - Wraps underlying currency + converted display value
3. **BondingCurve** - Pricing for custom currencies
4. **AccountCluster** - Manages keys per mint
5. **VerifiedState** - Bundles server-signed exchange rate proof (`rateProto`) and optional reserve state proof (`reserveProto`). Required when submitting any payment intent. For **launchpad currencies**, `reserveProto` is mandatory — the server rejects intents without it. **Pin-at-compute invariant**: amount-entry flows (`CurrencySellViewModel`, `WithdrawViewModel`, `GiveViewModel`) fetch the pin at the commit moment via `prepareSubmission()` and compute `ExchangedFiat.quarks` against that same pin. The buy flow pins the **payment mint's** verified state when a payment currency is selected (`BuyPaymentCurrencyViewModel.select`) and carries it through `BuyConfirmationViewModel` to submission — for launchpad-paid buys the swap amount is denominated in the payment token, so the payment mint's rate + reserve proof are the ones that must match the quarks. The pin is then carried through `Session.showCashBill` → `BillDescription.verifiedState` → `SendCashOperation` / `createCashLink` so face-to-face transfer and cash-link submission both use the proof the quarks were derived from. Fetching twice or pinning at flow-open reintroduces the "native amount and quark value mismatch" reject.
6. **SendCashOperation** - Orchestrates peer-to-peer transfers via a rendezvous handshake. Has two concurrent paths: Path 1 (advertise bill with verified state) and Path 2 (listen for grab, then transfer). Both paths share a resolved `VerifiedState`.
