# 2026-11-02 - Task-group fan-out over an AnyObject protocol failed region checks (e3c405108)

## What happened
To resolve group-send recipients four at a time, a protocol extension on
`RecipientResolving: AnyObject` added `resolveUserIDs(_:)`, whose task-group children
called `self.resolveUserID`. The build failed with "sending 'self' risks causing data
races". Marking the extension `@MainActor` and the children `{ @MainActor in ... }`
failed with the same two errors.

## The misstep
The app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` suggested the protocol's
`self` was main-isolated, and so Sendable. It isn't: inside the extension `self` is a
generic conformer of a non-Sendable `AnyObject` protocol, and the region checker won't
let a child task capture it, even a `@MainActor` child.

## Resolution
`RecipientBatch.resolveOwners(_:concurrency:resolve:)` takes an `@escaping @Sendable`
lookup closure, the `BlocklistController.resolve` shape. Callers pass
`{ @MainActor [self] in try await self.resolver.resolveUserID($0) }`. The view model is
a main-actor class, so it is Sendable to capture. `Collection.concurrentForEach` uses the
same shape.

## Lesson
For a concurrent fan-out in the app target, take a `@Sendable` closure and capture the
main-actor owner. Don't capture an `any Protocol` (or a protocol extension's `self`) in
child tasks.

## Landed on
Instruction. `.claude/docs/architecture.md#concurrent-fan-out`.
