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

        var id: Self { self }

        var description: String {
            switch self {
            case .balance:  "balance"
            case .settings: "settings"
            case .give:     "give"
            }
        }
    }
}
