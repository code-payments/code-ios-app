//
//  AppRouterAutoReturnIntegrationTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-05-08.
//
//  Integration coverage for `AppRouter.dismissAll()` followed by a
//  cross-stack `navigate(to:)` — the auto-return-on-background flow's
//  most interesting interaction. Predicate-level coverage lives in
//  `AppDelegateAutoReturnTriggerTests`; the dismissAll contract itself
//  lives in `AppRouterDismissAllTests`.
//

import Foundation
import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("AppRouter Auto-Return Integration")
struct AppRouterAutoReturnIntegrationTests {

    // MARK: - Helpers

    /// A second, distinct `PublicKey` for the "deep link arrives after
    /// reset" assertions. Different from `.usdc` so the leaf swap is
    /// observable.
    private static let otherMint = PublicKey.usdf

    // MARK: - 1. Deep link after dismissAll lands on a clean state

    /// Legacy bug: the interface-reset rebuilt the view hierarchy. A deep
    /// link arriving in the same scene-active cycle could double-present —
    /// the reset's rebuilt nav stack plus the deep link's `present(_:)`
    /// both wrote into the live tree.
    ///
    /// v3 contract: `dismissAll()` clears `presentedSheet` and every
    /// stack's path. A subsequent `navigate(to:)` from a deep link
    /// presents fresh on a clean slate — the navigated leaf is the
    /// only entry on the target stack regardless of prior depth.
    @Test("dismissAll clears all stacks so a deep link lands on a clean state")
    func dismissAll_clearsAllStacks_soDeeplinkLandsOnCleanState() {
        let router = AppRouter()

        // Build up real depth: present a sheet and push two destinations.
        router.present(.balance)
        router.push(.transactionHistory(.usdc))
        router.push(.currencyInfo(.usdc))

        // Auto-return fires on foreground.
        router.dismissAll()

        // Deep link arrives immediately after — like a push notification
        // routed through `AppRouter.navigate(to:)`.
        router.navigate(to: .currencyInfo(Self.otherMint))

        // The balance sheet is the destination's owning stack.
        #expect(router.presentedSheet == .balance)
        // Single entry: only the deep-link's leaf, no stale push history
        // from the pre-reset depth.
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(Self.otherMint)))
        #expect(router[.balance].count == 1)
    }

    // MARK: - 2. dismissAll then navigate does not double-present

    /// Legacy bug: the reset rebuilt the view hierarchy, which could
    /// collide with a concurrent `present()` call. The classic crash mode
    /// was a sheet from one flow being present alongside the new sheet
    /// from a deep link, with `presentedSheet` pointing at one but the
    /// other's path still populated underneath.
    ///
    /// v3 contract: `dismissAll()` clears the active sheet and every
    /// stack path. `navigate(to:)` then presents the destination's owning
    /// sheet cleanly — no orphaned reference to the previously-presented
    /// sheet, no stale path on the previous sheet's stack.
    @Test("dismissAll followed by navigate does not double-present any sheet")
    func dismissAll_thenNavigate_doesNotDoublePresent() {
        let router = AppRouter()

        // User was deep in Settings when they backgrounded.
        router.present(.settings)
        router.push(.settingsMyAccount)
        router.push(.settingsAdvancedFeatures)

        // Auto-return fires.
        router.dismissAll()

        // Deep link to a balance-stack destination arrives — analogous
        // to a push notification opening a currency.
        router.navigate(to: .currencyInfo(.usdc))

        // The presented sheet is the deep link's target only. No
        // overlapping settings sheet, no orphaned path.
        #expect(router.presentedSheet == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
        #expect(router[.balance].count == 1)
        // The dismissing stack's path is preserved through the slide-off
        // animation — exactly as covered in `AppRouterDismissAllTests`.
        // This confirms the live-tree invariant explicitly: only
        // `presentedSheet` determines what the user sees, and the deep
        // link's target is unambiguous.
        #expect(router[.settings] == AppRouter.navigationPath(.settingsMyAccount, .settingsAdvancedFeatures))
    }

    // MARK: - 3. Ordering symmetry: gate is one-shot

    /// The atomic gate (`AppDelegate.consumeAutoReturn`) is unit-tested in
    /// `AppDelegateAutoReturnTriggerTests`. This test asserts the visible
    /// AppRouter state matches a single dismissAll → navigate sequence:
    /// deep link wins the race, scenePhase's later attempt is gated false.
    @Test("Deep-link-first ordering: single dismissAll, navigate target persists")
    func deepLinkFirstOrdering_singleDismissAll_navigateTargetPersists() throws {
        let router = AppRouter()
        var lastBackgroundedAt: Date? = Date(timeInterval: -360, since: Date())

        router.present(.settings)
        router.push(.settingsMyAccount)
        router.push(.settingsAdvancedFeatures)

        // Deep link wins the race: handleOpenURL consumes the gate first.
        try #require(AppDelegate.consumeAutoReturn(
            now: Date(),
            lastBackgroundedAt: &lastBackgroundedAt
        ))
        router.dismissAll()
        router.navigate(to: .currencyInfo(.usdc))

        // .active fires second; gate is already consumed, so its dismissAll
        // never runs.
        #expect(AppDelegate.consumeAutoReturn(
            now: Date(),
            lastBackgroundedAt: &lastBackgroundedAt
        ) == false)

        #expect(lastBackgroundedAt == nil)
        #expect(router.presentedSheet == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
        #expect(router[.balance].count == 1)
    }

    /// Sibling: the `.active` scene-phase handler fires first. Same final
    /// state, different traversal order.
    @Test("Scene-phase-first ordering: single dismissAll, navigate target persists")
    func scenePhaseFirstOrdering_singleDismissAll_navigateTargetPersists() throws {
        let router = AppRouter()
        var lastBackgroundedAt: Date? = Date(timeInterval: -360, since: Date())

        router.present(.settings)
        router.push(.settingsMyAccount)
        router.push(.settingsAdvancedFeatures)

        // .active wins the race.
        try #require(AppDelegate.consumeAutoReturn(
            now: Date(),
            lastBackgroundedAt: &lastBackgroundedAt
        ))
        router.dismissAll()

        // handleOpenURL fires second; gate already consumed.
        #expect(AppDelegate.consumeAutoReturn(
            now: Date(),
            lastBackgroundedAt: &lastBackgroundedAt
        ) == false)
        router.navigate(to: .currencyInfo(.usdc))

        #expect(lastBackgroundedAt == nil)
        #expect(router.presentedSheet == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
        #expect(router[.balance].count == 1)
    }

    // MARK: - 4. Under-threshold path is unaffected

    /// Under the 5-minute threshold, neither path consumes the gate; the
    /// deep link just replaces the target stack's path. The existing
    /// "swap-and-return" behaviour is preserved.
    @Test("Under-threshold deep link does not dismiss other stacks")
    func underThreshold_deepLink_doesNotDismissOtherStacks() {
        let router = AppRouter()
        let original = Date(timeInterval: -120, since: Date()) // 2m
        var lastBackgroundedAt: Date? = original

        router.present(.settings)
        router.push(.settingsMyAccount)

        let consumed = AppDelegate.consumeAutoReturn(
            now: Date(),
            lastBackgroundedAt: &lastBackgroundedAt
        )

        #expect(consumed == false)
        #expect(lastBackgroundedAt == original) // preserved — under threshold

        router.navigate(to: .currencyInfo(.usdc))

        #expect(router.presentedSheet == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
        // Settings's path is preserved underneath — the existing
        // swap-and-return contract.
        #expect(router[.settings] == AppRouter.navigationPath(.settingsMyAccount))
    }

}
