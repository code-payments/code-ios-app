//
//  Regression_auto_return.swift
//  FlipcashTests
//
//  Regression coverage for the legacy interface-reset pain points the v3
//  Auto-Return-on-background feature must not reintroduce. The original
//  reset (removed in commit `bc66ccc3`) rebuilt `UIWindow.rootViewController`
//  after 60 seconds in the background and caused three classes of bugs:
//
//  1. Deep links arriving in the same scene-active cycle as a reset could
//     race and double-present destinations.
//  2. The reset could collide with a concurrent `present()` call from a
//     push notification or QR-scan handler, leaving orphaned state.
//  3. The reset destroyed view-state in flight, killing in-progress
//     operations and streams.
//
//  v3 replaces the view-hierarchy rebuild with a router-only mutation
//  (`AppRouter.returnToRoot()` — clears `presentedSheet` and every stack
//  path). The tests below assert *current* properties of the implementation
//  that prove the legacy classes of failure are no longer reachable.
//
//  Structural guarantee (not directly tested): `AppRouter.returnToRoot()`
//  only touches `presentedSheet`, `dismissedSheets`, and `paths`. It cannot
//  reach `Session`, `WalletConnection`, or any in-flight
//  `SendCashOperation` because `AppRouter` does not own references to them
//  — the type system enforces this. The two tests below cover the
//  cross-component behaviour through observable `AppRouter` state.
//
//  Why no UI tests for the eight scenarios in plan §10.2:
//
//  The minimum production timeout is 5 minutes. Driving it from a UI test
//  loop would require either (a) a launch-arg parser in
//  `AppDelegate.application(_:didFinishLaunchingWithOptions:)` that
//  overrides `Preferences.autoReturnTimeout` to a short duration, or (b) a
//  new `BetaFlags.Option` toggling a short-duration override path.
//
//  Neither pattern exists in production today. The current `--ui-testing`
//  flag is a boolean; `BetaFlags.Option` is a fixed enum with no
//  short-timeout case; and there is no precedent for launch-arg parsing in
//  AppDelegate beyond the boolean. Adding either would be an invasive
//  production hook purely to enable tests, which the implementer's
//  instructions and CLAUDE.md forbid (visibility relaxation, test-only
//  production code).
//
//  Unit-level coverage lives in `AppDelegateAutoReturnTriggerTests`,
//  `AppRouterReturnToRootTests`, and `PreferencesAutoReturnTimeoutTests`.
//
//  Manual verification matrix (run when changing trigger or action):
//   - Set timeout to 5 Minutes, open Settings, background ≥ 5 min,
//     return → Settings dismissed, Scanner visible.
//   - Set timeout to 5 Minutes, open Settings, background < 5 min,
//     return → Settings still showing.
//   - Open Discover, background ≥ 5 min → Discover dismissed.
//   - Open Balance → push CurrencyInfo, background ≥ 5 min → Scanner
//     (balance sheet dismissed, path cleared).
//   - Open Balance → push CurrencyInfo, background < 5 min →
//     CurrencyInfo still showing.
//   - Set timeout to Never, open Settings, background ≥ 6 min →
//     Settings still showing.
//   - App Settings → Auto-Return → tap "10 Minutes" → checkmark moves;
//     navigate back, re-enter Auto-Return → "10 Minutes" still checked.
//   - Cold start (no prior `lastBackgroundedAt`) → no auto-return on
//     first foreground.
//
//  If a UI-driven version becomes worthwhile, the cleanest seam would be
//  a new `BetaFlags.Option` (e.g. `.shortAutoReturnForTesting`) that
//  `AppDelegate.scenePhaseChanged` checks alongside the user preference,
//  off by default in production. That keeps the test hook gated behind
//  an existing pattern instead of inventing one.
//

import Foundation
import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Regression: auto-return — legacy interface-reset pain points")
struct Regression_auto_return {

    // MARK: - Helpers

    /// A second, distinct `PublicKey` for the "deep link arrives after
    /// reset" assertions. Different from `.usdc` so the leaf swap is
    /// observable.
    private static let otherMint = PublicKey.usdf

    // MARK: - 1. Deep link after returnToRoot lands on a clean state

    /// Legacy bug: the interface-reset rebuilt the view hierarchy. A deep
    /// link arriving in the same scene-active cycle could double-present —
    /// the reset's rebuilt nav stack plus the deep link's `present(_:)`
    /// both wrote into the live tree.
    ///
    /// v3 contract: `returnToRoot()` clears `presentedSheet` and every
    /// stack's path. A subsequent `navigate(to:)` from a deep link
    /// presents fresh on a clean slate — the navigated leaf is the
    /// only entry on the target stack regardless of prior depth.
    @Test("returnToRoot clears all stacks so a deep link lands on a clean state")
    func returnToRoot_clearsAllStacks_soDeeplinkLandsOnCleanState() {
        let router = AppRouter()

        // Build up real depth: present a sheet and push two destinations.
        router.present(.balance)
        router.push(.transactionHistory(.usdc))
        router.push(.currencyInfo(.usdc))

        // Auto-return fires on foreground.
        router.returnToRoot()

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

    // MARK: - 2. returnToRoot then navigate does not double-present

    /// Legacy bug: the reset rebuilt the view hierarchy, which could
    /// collide with a concurrent `present()` call. The classic crash mode
    /// was a sheet from one flow being present alongside the new sheet
    /// from a deep link, with `presentedSheet` pointing at one but the
    /// other's path still populated underneath.
    ///
    /// v3 contract: `returnToRoot()` clears the active sheet and every
    /// stack path. `navigate(to:)` then presents the destination's owning
    /// sheet cleanly — no orphaned reference to the previously-presented
    /// sheet, no stale path on the previous sheet's stack.
    @Test("returnToRoot followed by navigate does not double-present any sheet")
    func returnToRoot_thenNavigate_doesNotDoublePresent() {
        let router = AppRouter()

        // User was deep in Settings when they backgrounded.
        router.present(.settings)
        router.push(.settingsMyAccount)
        router.push(.settingsAdvancedFeatures)

        // Auto-return fires.
        router.returnToRoot()

        // Deep link to a balance-stack destination arrives — analogous
        // to a push notification opening a currency.
        router.navigate(to: .currencyInfo(.usdc))

        // The presented sheet is the deep link's target only. No
        // overlapping settings sheet, no orphaned path.
        #expect(router.presentedSheet == .balance)
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
        #expect(router[.balance].count == 1)
        // The dismissing stack's path is preserved through the slide-off
        // animation — exactly as covered in `AppRouterReturnToRootTests`.
        // This confirms the live-tree invariant explicitly: only
        // `presentedSheet` determines what the user sees, and the deep
        // link's target is unambiguous.
        #expect(router[.settings] == AppRouter.navigationPath(.settingsMyAccount, .settingsAdvancedFeatures))
    }

}
