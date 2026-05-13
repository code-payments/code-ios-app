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
    /// once — the bottom of the stack is the root sheet (overlays `ScanScreen`)
    /// and any subsequent entries are nested sheets that visually stack on top.
    nonisolated enum SheetPresentation: Identifiable, Hashable, Sendable, CustomStringConvertible {
        case balance
        case settings
        case give
        case discover
        case buy(PublicKey)

        var id: Self { self }

        /// The stack hosted inside this sheet. Inverse of `Stack.sheet`.
        /// Used by `dismissSheet` to clear the dismissed stack's path so a
        /// re-presentation starts at root rather than restoring the stale leaf.
        var stack: Stack {
            switch self {
            case .balance:  .balance
            case .settings: .settings
            case .give:     .give
            case .discover: .discover
            case .buy:      .buy
            }
        }

        /// Payload-free case discriminator. Used by `presentNested` to detect
        /// "same case, different payload" (e.g. `.buy(A)` → `.buy(B)`) without
        /// comparing the stringly-typed `description`.
        var caseKind: CaseKind {
            switch self {
            case .balance:  .balance
            case .settings: .settings
            case .give:     .give
            case .discover: .discover
            case .buy:      .buy
            }
        }

        enum CaseKind: Hashable, Sendable {
            case balance
            case settings
            case give
            case discover
            case buy
        }

        var description: String {
            switch self {
            case .balance:  "balance"
            case .settings: "settings"
            case .give:     "give"
            case .discover: "discover"
            case .buy:      "buy"
            }
        }
    }
}
