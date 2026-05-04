//
//  AppRouter+SheetPresentation.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import Foundation

extension AppRouter {

    /// Identifies the top-level modal sheet currently overlaying `ScanScreen`.
    /// One sheet at a time; switching sheets dismisses the previous.
    enum SheetPresentation: Identifiable, Hashable, Sendable, CustomStringConvertible {
        case balance
        case settings
        case give
        case discover

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
            }
        }

        var description: String {
            switch self {
            case .balance:  "balance"
            case .settings: "settings"
            case .give:     "give"
            case .discover: "discover"
            }
        }
    }
}
