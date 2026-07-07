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
        case settings
        case give
        case discover
        case buy
        case addMoney
        case downloadApp
        case send
        case sendAmount

        /// The sheet a stack is presented in. Cross-stack navigation uses
        /// this to know which top-level modal to surface.
        ///
        /// `.buy`, `.addMoney`, and `.sendAmount` return `nil` — their sheets
        /// carry a payload (mint / context / contact) that can't be synthesized
        /// from the stack alone, so they're entered via `presentNested`/`present`
        /// directly, never via `navigate(to:)`.
        var sheet: SheetPresentation? {
            switch self {
            case .balance:      .balance
            case .settings:     .settings
            case .give:         .give
            case .discover:     .discover
            case .buy:          nil
            case .addMoney:     nil
            case .downloadApp:  .downloadApp
            case .send:         .send
            case .sendAmount:   nil
            }
        }

        var description: String {
            switch self {
            case .balance:      "balance"
            case .settings:     "settings"
            case .give:         "give"
            case .discover:     "discover"
            case .buy:          "buy"
            case .addMoney:     "addMoney"
            case .downloadApp:  "downloadApp"
            case .send:         "send"
            case .sendAmount:   "sendAmount"
            }
        }
    }
}
