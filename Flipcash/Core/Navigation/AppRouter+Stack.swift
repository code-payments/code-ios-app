//
//  AppRouter+Stack.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import Foundation

extension AppRouter {

    /// Identifies one of the app's top-level NavigationStacks. Used as the
    /// per-stack key for path storage and to look up which sheet a destination
    /// surfaces in.
    enum Stack: Hashable, CaseIterable, Sendable, CustomStringConvertible {
        case balance
        case give
        case buy
        case addMoney
        case downloadApp
        case sendAmount
        case tips
        case you

        /// The sheet a stack is presented in. Cross-stack navigation uses
        /// this to know which top-level modal to surface.
        ///
        /// `.buy`, `.addMoney`, and `.sendAmount` return `nil` — their sheets
        /// carry a payload (mint / context / contact) that can't be synthesized
        /// from the stack alone, so they're entered via `presentNested`/`present`
        /// directly, never via `navigate(to:)`. `.balance` and `.you` are tab
        /// stacks, reached by bringing their tab forward.
        var sheet: SheetPresentation? {
            switch self {
            case .balance:      nil
            case .give:         .give
            case .buy:          nil
            case .addMoney:     nil
            case .downloadApp:  .downloadApp
            case .sendAmount:   nil
            case .tips:         .tips
            case .you:          nil
            }
        }

        /// Whether a tab hosts this stack rather than a sheet. `navigate(to:)`
        /// reaches these by bringing the tab forward — presenting a sheet
        /// instead would lay a second copy of the surface over the tab that
        /// already holds it. Mirrored by `HomeTab.pushStack`.
        ///
        /// `.tips` is both: the Chat tab hosts it, and `present(.tips)` still
        /// puts the same stack in a sheet from surfaces that have no tab bar.
        /// The tab wins for `navigate(to:)`.
        var isTabHosted: Bool {
            switch self {
            case .balance:      true
            case .give:         false
            case .buy:          false
            case .addMoney:     false
            case .downloadApp:  false
            case .sendAmount:   false
            case .tips:         true
            case .you:          true
            }
        }

        var description: String {
            switch self {
            case .balance:      "balance"
            case .give:         "give"
            case .buy:          "buy"
            case .addMoney:     "addMoney"
            case .downloadApp:  "downloadApp"
            case .sendAmount:   "sendAmount"
            case .tips:         "tips"
            case .you:          "you"
            }
        }
    }
}
