# Re-resolve gRPC addresses when the network path changes

**Status (2026-10-06):** implemented, uncommitted. Unit tests pass
(`NetworkChangeDNSResolverTests`, `NetworkPathStateTests`, `GRPCTransportTests`); the simulator
connects through the new resolver. The Wi-Fi to cellular path is not yet checked on a device.

Changes from the plan below, after review:
- Push mode turns off the library's re-resolve after GOAWAY or a dropped connection
  (`GRPCChannel.swift:147-148` leaves `resolverWithBackoff` nil, so `:655` is a no-op). To cover
  server address rotation, the resolver also refreshes every 5 minutes and `AppDelegate` posts a
  trigger on every foreground.
- A failed triggered lookup walks the retry delays once instead of giving up.
- Logs carry the resolved addresses, not just counts.

## Problem

A user on 5G saw every request fail with `POSIXErrorCode(rawValue: 50): Network is down` until
they force-quit the app. Cellular Data was on and no VPN was active.

- The log names one address for a week: `[ipv4]3.221.240.75:443`, from 2026-09-30 12:33 to
  2026-10-06 17:35 (~56 lines). The process was suspended and resumed, never killed.
- grpc-swift-nio-transport 2.4.4 resolves `.dns(host:port:)` once with `getaddrinfo` and hands IP
  literals to Network.framework. It re-resolves only when an *established* connection gets GOAWAY
  or closes uncleanly (`Subchannel.swift:340`, `:357`). A failed connect backs off and redials
  the same addresses forever (`Subchannel.swift:295`).
- Backgrounding does not help: `FlipClient` and `Client` are process-lifetime `let`s on
  `Container` (`Container.swift:38-39`). Force-quit is the only thing that forces a fresh lookup.

Unproven: why that address returns ENETDOWN on cellular. Leading guess: it was resolved on Wi-Fi
and the carrier's 5G is IPv6-only. The `ipv4`/`ipv6`/`dns` fields now logged by
`NetworkPathMonitor` will confirm or rule this out on the next export.

## Approach: a push-mode DNS resolver

`HTTP2ClientTransport.TransportServices.init` takes a `resolverRegistry`
(`HTTP2ClientTransport+TransportServices.swift:83-91`). `NameResolver` supports `.push` update
mode: the channel consumes an async sequence of `NameResolutionResult`s for as long as it lives and
hands each one to the load balancer (`GRPCChannel.swift:452-464`).

Register a resolver for the DNS target that:

1. Resolves with `getaddrinfo` on start and yields the result (same as today).
2. Re-resolves and yields again whenever it receives a "path changed" signal.
3. Also re-resolves when the channel reports a connect failure? Not possible from outside: push
   resolvers get no `requiresNameResolution` callback. Path changes are the trigger.

The default load balancer is pick-first (`GRPCChannel.swift:518`). On a new endpoint it replaces
the subchannel; on an identical endpoint it does nothing (`PickFirstLoadBalancer.swift:324`). So a
new address set reconnects, and an unchanged one costs nothing.

Why this over rebuilding the clients: every service wrapper captures `GRPCClient` by value in a
`let` (e.g. `EventStreamingService.swift:17-20`), and `EventStreamer` / `LiveMintDataStreamer`
hold their service in a `let`. Swapping clients means making ~23 services, both streamers, and
their owners swappable. The resolver keeps all of that untouched.

## Changes

1. **FlipcashCore `PathAwareDNSResolver`** (new, next to `GRPCTransport.swift`): a
   `NameResolverFactory` for `ResolvableTargets.DNS` returning `updateMode: .push`. It owns an
   `AsyncStream` of re-resolve triggers. On each trigger it calls `getaddrinfo` off the
   cooperative pool (the library's `DNSResolver` is `package`, so we need our own small wrapper)
   and yields the endpoints. A failed lookup is logged and skipped, not thrown, so the channel
   keeps its last good addresses. Throwing would end the sequence.
2. **A process-wide trigger** that `NetworkPathMonitor` fires on a change of `status` or
   `interfaces`, not on every field (expensive/constrained flips shouldn't reconnect). FlipcashCore
   can't see the app target, so the trigger lives in FlipcashCore (e.g. a
   `NetworkPathChanges` broadcaster) and the app's monitor posts into it.
3. **`GRPCTransport.makeTransportServices`** passes a registry containing the new factory.
   All four call sites pick it up with no change. The notification extensions'
   `ChatNotificationClient` instances are short-lived and also unaffected in practice.
4. **Logging:** log each re-resolve with host, address count and families (not the IPs as message
   text; addresses go in metadata), so the next export shows the address swap.

## Tests

- Resolver unit test with an injected lookup function: initial yield, a trigger yields new
  endpoints, a failed lookup yields nothing and the sequence stays open, cancellation ends it.
- Monitor test: interface change posts a trigger; an expensive-only change does not.
- Device check: connect on Wi-Fi, background, switch to cellular, foreground. The log should show
  a path change, a re-resolve, then `Event stream went live`.

## Risks

- Re-resolving on every Wi-Fi/cellular flip reconnects even when the old address would have
  worked. Pick-first ignores identical results, so the cost is one lookup per change.
- If the next log shows the *same* addresses failing after a fresh lookup, this theory is wrong and
  the fix is the bigger one: rebuild `FlipClient`/`Client` internals on path change.
- Upstream may fix this (re-resolve on connect failure). Worth filing an issue on
  grpc/grpc-swift-nio-transport; this resolver can be deleted if they do.

## Status: reverted (2026-10-06)

Implemented, device-tested, then reverted. On bmc-iphone the Wi-Fi to cellular switch re-resolved and
reconnected within a second, but every lookup on both networks returned the same three `fc-v2`
addresses, including `3.221.240.75`, which worked over cellular. The address the user was stuck on
was not stale, so this fix does not address their bug. Side effect seen: DNS reorders the list,
pick-first treats a reordered list as new, so every lookup reconnected.

Kept: `NetworkPathMonitor` logging (status, reason, interfaces, IPv4/IPv6/DNS) and the
cellular-denied dialog. Next step: wait for a report with that logging. Fallback if it recurs with a
satisfied path: rebuild the gRPC clients after repeated ENETDOWN (the force-quit equivalent).
