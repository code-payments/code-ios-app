//
//  AppRouter+Destination.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import Foundation
import FlipcashCore

extension AppRouter {

    /// A type-erased push target. Every screen reachable via a NavigationStack
    /// push (anywhere in the app) is a case here.
    enum Destination: Hashable, Sendable, CustomStringConvertible {

        // Wallet flow
        case currencyInfo(PublicKey)
        case discoverCurrencies
        case currencyCreationSummary
        case currencyCreationWizard
        case transactionHistory(PublicKey)

        // Settings flow
        case settingsMyAccount
        case settingsAdvancedFeatures
        case settingsAppSettings
        case settingsBetaFlags
        case settingsAccountSelection
        case settingsApplicationLogs
        case accessKey
        case depositCurrencyList
        case withdraw

        /// The stack this destination naturally belongs in. Cross-stack
        /// navigation uses this to know which sheet to present.
        var owningStack: Stack {
            switch self {
            case .currencyInfo, .discoverCurrencies, .currencyCreationSummary,
                 .currencyCreationWizard, .transactionHistory:
                return .balance
            case .settingsMyAccount, .settingsAdvancedFeatures, .settingsAppSettings,
                 .settingsBetaFlags, .settingsAccountSelection, .settingsApplicationLogs,
                 .accessKey, .depositCurrencyList, .withdraw:
                return .settings
            }
        }

        /// Stable string for log filtering. Deliberately omits associated values
        /// so PublicKey base58 strings never end up in interpolated log messages.
        var description: String {
            switch self {
            case .currencyInfo:                 "currencyInfo"
            case .discoverCurrencies:           "discoverCurrencies"
            case .currencyCreationSummary:      "currencyCreationSummary"
            case .currencyCreationWizard:       "currencyCreationWizard"
            case .transactionHistory:           "transactionHistory"
            case .settingsMyAccount:            "settingsMyAccount"
            case .settingsAdvancedFeatures:     "settingsAdvancedFeatures"
            case .settingsAppSettings:          "settingsAppSettings"
            case .settingsBetaFlags:            "settingsBetaFlags"
            case .settingsAccountSelection:     "settingsAccountSelection"
            case .settingsApplicationLogs:      "settingsApplicationLogs"
            case .accessKey:                    "accessKey"
            case .depositCurrencyList:          "depositCurrencyList"
            case .withdraw:                     "withdraw"
            }
        }
    }
}
