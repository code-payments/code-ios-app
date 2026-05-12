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

        /// The sheet a stack is presented in. Cross-stack navigation uses
        /// this to know which top-level modal to surface.
        var sheet: SheetPresentation {
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
