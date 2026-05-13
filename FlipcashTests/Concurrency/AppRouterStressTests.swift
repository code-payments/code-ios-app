//
//  AppRouterStressTests.swift
//  FlipcashTests
//
//  Observable-state sentinel for `AppRouter`. `AppRouter` is
//  `@MainActor @Observable` — its mutators are serialized by main-actor
//  isolation, so this suite cannot manufacture cross-actor pressure. Its
//  purpose is to lock in observable-state correctness across the
//  present/dismiss cycle so that the present/dismiss bookkeeping
//  (`presentedSheet`, `dismissedSheets`, per-stack `paths`) converges on
//  a consistent state after repeated user-flow shapes regardless of
//  whether `AppRouter` is explicitly or implicitly main-actor isolated.
//
//  Scope: state-consistency only. The router emits one INFO log per
//  mutation under `flipcash.router`, but there's no in-suite log handler
//  exposed to count them — log-count assertion would require additional
//  production seams.
//

import Foundation
import Testing
@testable import Flipcash

@Suite(
    "AppRouter present/dismiss cycle",
    .timeLimit(.minutes(1)),
    .tags(.concurrency, .stress)
)
@MainActor
struct AppRouterStressTests {

    @Test("100 alternating present/dismiss leave router in consistent state")
    func alternatingPresentDismiss_isConsistent() {
        let router = AppRouter()

        for _ in 0..<100 {
            router.present(.balance)
            router.dismissSheet()
        }

        #expect(router.presentedSheet == nil)
        #expect(router[.balance].isEmpty)
    }

    /// Cycling through every `SheetPresentation` case mirrors the real
    /// "swap between top-level sheets" flow — the user opens Balance,
    /// then Settings, then Give, etc., dismissing each in turn. After 100
    /// rounds the router must be back at no presented sheet with every
    /// per-stack path empty.
    @Test("100 rounds across all sheet cases converge on empty state")
    func cyclingAllSheets_convergesOnEmptyState() {
        let router = AppRouter()
        // `compactMap` skips nested-only stacks (`.buy`) — they can't be
        // a root sheet, so they're outside this stress test's scope.
        let sheets = AppRouter.Stack.allCases.compactMap(\.sheet)

        for i in 0..<100 {
            let sheet = sheets[i % sheets.count]
            router.present(sheet)
            router.dismissSheet()
        }

        #expect(router.presentedSheet == nil)
        for stack in AppRouter.Stack.allCases {
            #expect(router[stack].isEmpty)
        }
    }
}
