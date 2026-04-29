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
/// All mutators log at INFO via `flipcash.router`. The bindable subscript
/// funnels SwiftUI's automatic writes (e.g., swipe-back) through `setPath`,
/// so every observable state change produces exactly one log line.
@MainActor
@Observable
final class AppRouter {

    private(set) var presentedSheet: SheetPresentation?

    private var paths: [Stack: NavigationPath] = [:]

    /// Sheets the user has explicitly dismissed (close button, swipe-down, or
    /// programmatic `dismissSheet`) since their last presentation. The next
    /// `present(_:)` of an entry in this set clears the sheet's stack path so
    /// re-opening starts at root. Sheet swaps don't add to the set, so swap-back
    /// preserves the prior path. Bounded by the number of `SheetPresentation`
    /// cases.
    private var dismissedSheets: Set<SheetPresentation> = []

    init() {}

    /// Bindable per-stack `NavigationPath`. Drives `NavigationStack(path: $router[.balance])`.
    /// Writes funnel through the binding-setter `setPath` so SwiftUI's automatic
    /// mutations (e.g., swipe-back) also log.
    subscript(stack: Stack) -> NavigationPath {
        get { paths[stack, default: NavigationPath()] }
        set { setPath(newValue, on: stack) }
    }

    // MARK: - Stack mutators

    /// Pushes onto whatever stack is currently presented (`presentedSheet?.stack`).
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

    /// Pushes any Hashable value onto the currently-presented stack. Used by
    /// sub-flows whose destination types live outside `AppRouter.Destination`
    /// (e.g., `WithdrawNavigationPath`), so a single stack can carry mixed
    /// types without nesting `NavigationStack`s. No-op with a warning if no
    /// sheet is presented.
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

    /// Presents `sheet`. Idempotent: no-op if already presenting `sheet`.
    ///
    /// If `sheet` was previously dismissed (sits in `dismissedSheets`), its
    /// stack path is cleared synchronously *before* the sheet mounts — so a
    /// re-open lands at root. A sheet swap (presenting a different sheet
    /// without going through `dismissSheet` first) leaves both paths intact,
    /// preserving the original "swap-and-return" behaviour.
    ///
    /// Doing the clear here instead of inside `dismissSheet` avoids the
    /// "push back, then dismiss" animation: dismissal lets the sheet's
    /// snapshot slide off-screen with its current contents intact, and the
    /// clear runs only when the user actively chooses to re-open.
    func present(_ sheet: SheetPresentation) {
        guard sheet != presentedSheet else { return }
        let previous = presentedSheet
        if dismissedSheets.remove(sheet) != nil {
            paths[sheet.stack] = NavigationPath()
        }
        presentedSheet = sheet
        logger.info("Presented sheet", metadata: [
            "sheet": "\(sheet)",
            "previousSheet": "\(previous.map(String.init(describing:)) ?? "<none>")",
        ])
    }

    /// Dismisses the active sheet and marks it as "explicitly closed" so the
    /// next `present(_:)` of the same sheet clears its stack path. The path
    /// itself is left untouched here — the dismissing sheet keeps its current
    /// contents through the slide-down animation, and the clear happens on
    /// re-open instead.
    func dismissSheet() {
        guard let dismissing = presentedSheet else { return }
        presentedSheet = nil
        dismissedSheets.insert(dismissing)
        logger.info("Dismissed sheet", metadata: ["sheet": "\(dismissing)"])
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

    /// Cross-stack navigation. Presents the destination's `owningStack` (swapping
    /// the current sheet if different) and sets `[destination]` as the only
    /// path entry on that stack. Other stacks' paths are preserved underneath.
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
        let targetSheet = targetStack.sheet

        var expected = NavigationPath()
        expected.append(destination)
        let alreadyThere = presentedSheet == targetSheet
                        && paths[targetStack, default: NavigationPath()] == expected
        guard !alreadyThere else { return }

        present(targetSheet)
        setPath([destination], on: targetStack)
    }
}
