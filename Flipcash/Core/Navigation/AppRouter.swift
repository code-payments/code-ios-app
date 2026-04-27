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

    init() {}

    /// Bindable per-stack `NavigationPath`. Drives `NavigationStack(path: $router[.balance])`.
    /// Writes funnel through the binding-setter `setPath` so SwiftUI's automatic
    /// mutations (e.g., swipe-back) also log.
    subscript(stack: Stack) -> NavigationPath {
        get { paths[stack, default: NavigationPath()] }
        set { setPath(newValue, on: stack) }
    }

    // MARK: - Stack mutators

    func push(_ destination: Destination, on stack: Stack) {
        paths[stack, default: NavigationPath()].append(destination)
        logger.info("Pushed destination", metadata: [
            "stack": "\(stack)",
            "destination": "\(destination)",
            "depth": "\(paths[stack, default: NavigationPath()].count)",
        ])
    }

    /// Pushes any Hashable value onto the stack. Used by sub-flows whose
    /// destination types live outside `AppRouter.Destination` (e.g.,
    /// `WithdrawNavigationPath`), so a single stack can carry mixed types
    /// without nesting `NavigationStack`s.
    func pushAny<H: Hashable>(_ value: H, on stack: Stack) {
        paths[stack, default: NavigationPath()].append(value)
        logger.info("Pushed sub-flow destination", metadata: [
            "stack": "\(stack)",
            "type": "\(type(of: value))",
            "depth": "\(paths[stack, default: NavigationPath()].count)",
        ])
    }

    func pop(on stack: Stack) {
        guard !(paths[stack]?.isEmpty ?? true) else { return }
        paths[stack]?.removeLast()
        logger.info("Popped destination", metadata: [
            "stack": "\(stack)",
            "newDepth": "\(paths[stack, default: NavigationPath()].count)",
        ])
    }

    func popToRoot(on stack: Stack) {
        guard !(paths[stack]?.isEmpty ?? true) else { return }
        paths[stack] = NavigationPath()
        logger.info("Popped to root", metadata: ["stack": "\(stack)"])
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
        logger.info("Popped count items", metadata: [
            "stack": "\(stack)",
            "count": "\(actual)",
            "newDepth": "\(paths[stack, default: NavigationPath()].count)",
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
        logger.info("Replaced path", metadata: [
            "stack": "\(stack)",
            "previousDepth": "\(oldPath.count)",
            "newDepth": "\(destinations.count)",
            "newTop": "\(destinations.last.map(String.init(describing:)) ?? "<empty>")",
        ])
    }

    /// SwiftUI binding setter — receives an updated `NavigationPath` whose
    /// length may differ from our last known state (e.g., the user popped
    /// via swipe-back).
    private func setPath(_ newPath: NavigationPath, on stack: Stack) {
        let oldPath = paths[stack, default: NavigationPath()]
        guard oldPath != newPath else { return }
        paths[stack] = newPath
        logger.info("Replaced path", metadata: [
            "stack": "\(stack)",
            "previousDepth": "\(oldPath.count)",
            "newDepth": "\(newPath.count)",
        ])
    }

    // MARK: - Sheet mutators

    /// Presents `sheet`. Idempotent: no-op if already presenting `sheet`.
    func present(_ sheet: SheetPresentation) {
        guard sheet != presentedSheet else { return }
        let previous = presentedSheet
        presentedSheet = sheet
        logger.info("Presented sheet", metadata: [
            "sheet": "\(sheet)",
            "previousSheet": "\(previous.map(String.init(describing:)) ?? "<none>")",
        ])
    }

    func dismissSheet() {
        guard let dismissing = presentedSheet else { return }
        presentedSheet = nil
        logger.info("Dismissed sheet", metadata: ["sheet": "\(dismissing)"])
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
