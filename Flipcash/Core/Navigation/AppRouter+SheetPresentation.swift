//
//  AppRouter+SheetPresentation.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import Foundation
import FlipcashCore

extension AppRouter {

    /// Identifies a top-level modal sheet. The router can present multiple at
    /// once — the bottom of the stack is the root sheet (overlays the tab bar)
    /// and any subsequent entries are nested sheets that visually stack on top.
    nonisolated enum SheetPresentation: Identifiable, Hashable, Sendable, CustomStringConvertible {
        case settings
        case give
        case buy(PublicKey)
        /// Standalone Add Money flow (deposit USDF). Payload selects the
        /// "No Balance Yet" subtitle; the flow itself is currency-agnostic.
        case addMoney(AddMoneyContext)
        case downloadApp
        /// Send Cash amount entry, stacked on top of the chat via
        /// `presentNested(.sendAmount)`. Dismissing it reveals the chat.
        case sendAmount(SendTarget)
        /// My Tipcard, or the invitation to create a profile when there isn't one.
        case tips

        var id: Self { self }

        /// The stack hosted inside this sheet. Inverse of `Stack.sheet`.
        /// Used by `dismissSheet` to clear the dismissed stack's path so a
        /// re-presentation starts at root rather than restoring the stale leaf.
        var stack: Stack {
            switch self {
            case .settings:     .settings
            case .give:         .give
            case .buy:          .buy
            case .addMoney:     .addMoney
            case .downloadApp:  .downloadApp
            case .sendAmount:   .sendAmount
            case .tips:         .tips
            }
        }

        /// Payload-free case discriminator. Used by `presentNested` to detect
        /// "same case, different payload" (e.g. `.buy(A)` → `.buy(B)`) without
        /// comparing the stringly-typed `description`.
        var caseKind: CaseKind {
            switch self {
            case .settings:     .settings
            case .give:         .give
            case .buy:          .buy
            case .addMoney:     .addMoney
            case .downloadApp:  .downloadApp
            case .sendAmount:   .sendAmount
            case .tips:         .tips
            }
        }

        enum CaseKind: Hashable, Sendable {
            case settings
            case give
            case buy
            case addMoney
            case downloadApp
            case sendAmount
            case tips
        }

        var description: String {
            switch self {
            case .settings:     "settings"
            case .give:         "give"
            case .buy:          "buy"
            case .addMoney:     "addMoney"
            case .downloadApp:  "downloadApp"
            case .sendAmount:   "sendAmount"
            case .tips:         "tips"
            }
        }
    }
}
