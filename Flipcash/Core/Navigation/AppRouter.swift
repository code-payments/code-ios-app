//
//  AppRouter.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import Foundation
import SwiftUI
import FlipcashCore

private let logger = Logger(label: "flipcash.router")

/// Centralised navigation state for the app. Each top-level modal sheet
/// (`SheetPresentation`) owns a NavigationStack whose path is stored here
/// per `Stack`. Sheet swaps preserve other stacks' paths so reopening a
/// previously-visible sheet restores its state.
///
/// Paths are stored as `NavigationPath` (type-erased) so a single stack
/// can carry destinations of more than one Hashable type — for example,
/// the Settings stack carries `Destination` cases at the top level and
/// `WithdrawNavigationPath` cases for the multi-step withdraw flow.
/// This avoids nested `NavigationStack`s, which crash with
/// `comparisonTypeMismatch` on push/pop/push cycles.
///
/// The router supports nested sheets: `presentedSheets` is an ordered stack
/// where the bottom entry is the root sheet (mounted at app root) and any
/// entries above visually stack on top via `.appRouterNestedSheet` modifiers
/// applied inside each parent sheet's content tree. SwiftUI requires nested
/// sheets to be presented from within the parent's view tree — they cannot
/// be siblings at the root.
///
/// All mutators log at INFO via `flipcash.router`. The bindable subscript
/// funnels SwiftUI's automatic writes (e.g., swipe-back) through `setPath`,
/// so every observable state change produces exactly one log line.
@Observable
@MainActor
final class AppRouter {

    /// Approximate duration of a SwiftUI `.sheet` / `.fullScreenCover` dismiss
    /// animation. Used to sequence state mutations that must land *after* a
    /// dismiss has fully cleared the view tree — e.g. nilling a cover's
    /// `item` binding without staging a separate cover-dismiss animation, or
    /// mutating bill state so it enters fresh on the revealed ScanScreen.
    static let dismissAnimationDuration: Duration = .milliseconds(400)

    /// Stack of presented sheets, bottom-first. `.first` is the root sheet
    /// (mounted at app root); `.last` is topmost (visible). Empty when no
    /// sheet is presented.
    private(set) var presentedSheets: [SheetPresentation] = []

    /// Topmost (currently visible) sheet, or nil if no sheet is presented.
    var presentedSheet: SheetPresentation? { presentedSheets.last }

    /// Root sheet — the one mounted at the app root. Distinct from
    /// `presentedSheet` when nested sheets are present.
    var rootSheet: SheetPresentation? { presentedSheets.first }

    private var paths: [Stack: NavigationPath] = [:]

    /// Stacks whose owning sheet was explicitly dismissed (close button,
    /// swipe-down, or programmatic `dismissSheet`) since the last presentation
    /// of that stack. The next `present(_:)` or `presentNested(_:)` on a sheet
    /// whose stack is in this set clears the stack's `NavigationPath` so
    /// re-opening starts at root. Sheet swaps at the root level don't add to
    /// the set, so swap-back preserves the prior path. Keyed by `Stack` (not
    /// `SheetPresentation`) because the path is per-stack and payload-equality
    /// would miss "different `.buy(mint)`" re-opens that share the same stack.
    private var dismissedStacks: Set<Stack> = []

    init() {}

    /// Bindable per-stack `NavigationPath`. Drives `NavigationStack(path: $router[.balance])`.
    /// Writes funnel through the binding-setter `setPath` so SwiftUI's automatic
    /// mutations (e.g., swipe-back) also log.
    subscript(stack: Stack) -> NavigationPath {
        get { paths[stack, default: NavigationPath()] }
        set { setPath(newValue, on: stack) }
    }

    // MARK: - Stack mutators

    /// Pushes onto whatever stack is topmost (`presentedSheet?.stack`). With
    /// nested sheets, that's the nested sheet's stack — pushes always land on
    /// the visible NavigationStack, never on a stack hidden underneath.
    ///
    /// No-op with a warning if no sheet is presented — pushes onto a hidden
    /// stack would silently corrupt that stack's path until the user later
    /// presents that sheet.
    ///
    /// Cross-stack navigation is `navigate(to:)`'s job, not `push`'s.
    func push(_ destination: Destination) {
        guard let stack = presentedSheet?.stack else {
            logger.warning("Push attempted with no sheet presented", metadata: [
                "destination": "\(destination)",
            ])
            return
        }
        paths[stack, default: NavigationPath()].append(destination)
        logger.info("Push", metadata: navigationMetadata(stack: stack, destination: destination))
    }

    /// Pushes any Hashable value onto the topmost stack. Used by sub-flows
    /// whose destination types live outside `AppRouter.Destination` (e.g.,
    /// `WithdrawNavigationPath`, `BuyFlowPath`), so a single stack can carry
    /// mixed types without nesting `NavigationStack`s. No-op with a warning
    /// if no sheet is presented.
    func pushAny<H: Hashable>(_ value: H) {
        guard let stack = presentedSheet?.stack else {
            logger.warning("Push (sub-flow) attempted with no sheet presented", metadata: [
                "type": "\(type(of: value))",
            ])
            return
        }
        paths[stack, default: NavigationPath()].append(value)
        logger.info("Push (sub-flow)", metadata: [
            "stack": "\(stack)",
            "type": "\(type(of: value))",
        ])
    }

    func pop(on stack: Stack) {
        guard !(paths[stack]?.isEmpty ?? true) else { return }
        paths[stack]?.removeLast()
        logger.info("Pop", metadata: ["stack": "\(stack)"])
    }

    func popToRoot(on stack: Stack) {
        guard !(paths[stack]?.isEmpty ?? true) else { return }
        paths[stack] = NavigationPath()
        logger.info("Reset stack", metadata: ["stack": "\(stack)"])
    }

    /// Pops up to `count` items from the top of `stack`. Used by sub-flows
    /// (e.g., `WithdrawViewModel.popToEnterAmount`) that need to unwind a
    /// known number of substeps.
    func popLast(_ count: Int, on stack: Stack) {
        let available = paths[stack, default: NavigationPath()].count
        let actual = min(count, available)
        guard actual > 0 else { return }
        for _ in 0..<actual {
            paths[stack]?.removeLast()
        }
        logger.info("Pop multiple", metadata: [
            "stack": "\(stack)",
            "count": "\(actual)",
        ])
    }

    /// Replaces the entire path on `stack` with the given typed destinations.
    /// Used for cross-stack jumps like `navigate(to:)` where the leaf is set
    /// fresh.
    func setPath(_ destinations: [Destination], on stack: Stack) {
        var newPath = NavigationPath()
        for destination in destinations { newPath.append(destination) }
        let oldPath = paths[stack, default: NavigationPath()]
        guard oldPath != newPath else { return }
        paths[stack] = newPath
        logger.info("Set path", metadata: navigationMetadata(stack: stack, destination: destinations.last))
    }

    /// SwiftUI binding setter — fires when the NavigationStack writes a new
    /// path back through the binding (system swipe-back, NavigationLink
    /// activation, programmatic `dismiss()`). Distinguished from explicit
    /// `setPath(_:on:)` so a trail differentiates "user gesture" from
    /// "intent-driven jump".
    private func setPath(_ newPath: NavigationPath, on stack: Stack) {
        let oldPath = paths[stack, default: NavigationPath()]
        guard oldPath != newPath else { return }
        paths[stack] = newPath
        logger.info("Path changed externally", metadata: ["stack": "\(stack)"])
    }

    // MARK: - Sheet mutators

    /// Presents `sheet` as the root sheet.
    ///
    /// Semantics:
    /// - Already at this exact state (`presentedSheets == [sheet]`) → idempotent.
    /// - Same root with nested sheets above → pop the nested(s), keep root.
    ///   `present(.balance)` while `[.balance, .buy(mint)]` is up → `[.balance]`.
    /// - Different root (with or without nested above) → dismiss everything,
    ///   present new root.
    ///
    /// If the new root's stack was previously dismissed (sits in
    /// `dismissedStacks`), its path is cleared synchronously *before* the
    /// sheet mounts — so a re-open lands at root. A sheet swap (presenting a
    /// different sheet without going through `dismissSheet` first) leaves
    /// both paths intact, preserving the original "swap-and-return" behaviour.
    func present(_ sheet: SheetPresentation) {
        if presentedSheets == [sheet] { return }

        let previousTop = presentedSheet

        if presentedSheets.first == sheet {
            // Same root, nested above → pop nested(s), keep root path intact.
            for nested in presentedSheets.dropFirst() {
                dismissedStacks.insert(nested.stack)
            }
            presentedSheets = [sheet]
            logger.info("Presented sheet (popped nested above same root)", metadata: [
                "sheet": "\(sheet)",
                "previousSheet": "\(previousTop.map(String.init(describing:)) ?? "<none>")",
            ])
            return
        }

        // Different root: nested sheets above (if any) are dismissed — their
        // paths clear on next re-open. The replaced root is left out of
        // `dismissedStacks` so a future `present(_:)` of the old root restores
        // its path (swap-back semantics).
        for nested in presentedSheets.dropFirst() {
            dismissedStacks.insert(nested.stack)
        }

        if dismissedStacks.remove(sheet.stack) != nil {
            paths[sheet.stack] = NavigationPath()
        }

        presentedSheets = [sheet]
        logger.info("Presented sheet", metadata: [
            "sheet": "\(sheet)",
            "previousSheet": "\(previousTop.map(String.init(describing:)) ?? "<none>")",
        ])
    }

    /// Appends `sheet` on top of the current top, stacking visually. Requires
    /// at least one sheet already presented (no-op + warning otherwise — the
    /// caller should `present(_:)` a root first, not promote-implicitly).
    ///
    /// Semantics:
    /// - Stack empty → no-op + warning.
    /// - Same sheet already on top → idempotent.
    /// - Same case different payload on top (e.g., `.buy(A)` → `.buy(B)`) →
    ///   swap the top entry and clear the shared stack's path so the new
    ///   payload mounts at root.
    /// - Otherwise → append.
    ///
    /// Path-clear-on-reopen applies identically to nested sheets: if the
    /// presented sheet's stack sits in `dismissedStacks`, its path is cleared
    /// synchronously before mount.
    func presentNested(_ sheet: SheetPresentation) {
        guard !presentedSheets.isEmpty else {
            logger.warning("presentNested attempted with no sheet presented; call present(_:) first", metadata: [
                "sheet": "\(sheet)",
            ])
            return
        }

        if presentedSheets.last == sheet { return }

        if let top = presentedSheets.last,
           top != sheet,
           top.caseKind == sheet.caseKind {
            // Same case kind on top with a different payload — swap. The
            // displaced and new values share a stack, so its path belonged to
            // the old payload and must clear before the new payload mounts.
            paths[sheet.stack] = NavigationPath()
            presentedSheets[presentedSheets.count - 1] = sheet
            logger.info("Presented nested sheet (swapped same-case top)", metadata: [
                "sheet": "\(sheet)",
                "displaced": "\(top)",
            ])
            return
        }

        if dismissedStacks.remove(sheet.stack) != nil {
            paths[sheet.stack] = NavigationPath()
        }

        presentedSheets.append(sheet)
        logger.info("Presented nested sheet", metadata: [
            "sheet": "\(sheet)",
            "depth": "\(presentedSheets.count)",
        ])
    }

    /// Dismisses the topmost sheet. If only the root remains, this dismisses
    /// the root (same as the pre-nested behaviour). With nested sheets, only
    /// the topmost is popped — the root stays presented.
    ///
    /// The dismissed sheet is marked "explicitly closed" so the next
    /// presentation of the same value clears its stack path. The path itself
    /// is left untouched here — the dismissing sheet keeps its current
    /// contents through the slide-down animation, and the clear happens on
    /// re-open instead.
    func dismissSheet() {
        guard let dismissing = presentedSheets.popLast() else { return }
        dismissedStacks.insert(dismissing.stack)
        logger.info("Dismissed sheet", metadata: [
            "sheet": "\(dismissing)",
            "remainingDepth": "\(presentedSheets.count)",
        ])
    }

    /// Global navigation reset: dismisses every presented sheet and clears
    /// every stack's `NavigationPath`. The user lands on the Scanner — the
    /// unconditional root rendered behind all sheets.
    ///
    /// Distinct from ``popToRoot(on:)``, which is a per-stack pop. This
    /// method is the all-sheets + all-stacks variant, used by the
    /// auto-return-on-background trigger when the user has been away long
    /// enough that any in-flight navigation should be discarded.
    ///
    /// The dismissing root sheet's slide-down animation runs with its current
    /// contents — the same behaviour as ``dismissSheet()``. Inactive stacks
    /// have no on-screen UI so their paths are cleared synchronously.
    func dismissAll() {
        let dismissing = presentedSheets
        let dismissingRoot = presentedSheets.first
        presentedSheets = []
        for sheet in dismissing {
            dismissedStacks.insert(sheet.stack)
        }
        // Clear every stack's path except the dismissing root's — that stack
        // keeps its path through the slide-off animation, cleared on next
        // present of that root via the dismissedStacks mechanism.
        for stack in Stack.allCases where stack != dismissingRoot?.stack {
            paths[stack] = NavigationPath()
        }
        logger.info("Dismiss all", metadata: [
            "dismissedSheets": "\(dismissing.map(String.init(describing:)))",
        ])
    }

    // MARK: - Logging helpers

    /// Builds the standard navigation log metadata: `stack`, `destination`,
    /// and (when the destination carries a `PublicKey` or similar) `payload`.
    /// Shared by `push` and `setPath` so the trail format stays consistent and
    /// the conditional payload-add lives in one place.
    private func navigationMetadata(stack: Stack, destination: Destination?) -> Logger.Metadata {
        var metadata: Logger.Metadata = [
            "stack": "\(stack)",
            "destination": "\(destination.map(String.init(describing:)) ?? "<empty>")",
        ]
        if let payload = destination?.payload {
            metadata["payload"] = "\(payload)"
        }
        return metadata
    }

    // MARK: - Cross-stack navigation

    /// Cross-stack navigation. Presents the destination's `owningStack` as the
    /// root sheet (dismissing any nested sheets above) and sets `[destination]`
    /// as the only path entry on that stack. Other stacks' paths are preserved
    /// underneath.
    ///
    /// Call this from deeplinks, push notifications, and any programmatic
    /// redirect that should land the user *on* the destination regardless of
    /// where they currently are.
    ///
    /// > Note: `DestinationView` applies `.id(mint)` to `CurrencyInfoScreen`
    /// > so leaf swaps from `[currencyInfo(A)]` to `[currencyInfo(B)]` rebuild
    /// > the destination with fresh `@State` rather than reusing the previous
    /// > view's view model.
    func navigate(to destination: Destination) {
        let targetStack = destination.owningStack
        // `Destination.owningStack` only ever names a root stack
        // (balance/settings/give/discover) — `.buy` is nested-only and never
        // an owning stack — so the optional `Stack.sheet` is never nil here.
        guard let targetSheet = targetStack.sheet else {
            logger.warning("navigate(to:) hit a nested-only stack — destination is misrouted", metadata: [
                "stack": "\(targetStack)",
                "destination": "\(destination)",
            ])
            return
        }

        var expected = NavigationPath()
        expected.append(destination)
        let alreadyThere = presentedSheets == [targetSheet]
                        && paths[targetStack, default: NavigationPath()] == expected
        guard !alreadyThere else { return }

        // present(_:) handles dismiss-nested-then-swap-root semantics.
        present(targetSheet)
        setPath([destination], on: targetStack)
    }
}
