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
    nonisolated enum Destination: Hashable, Sendable, CustomStringConvertible {

        // Wallet flow
        case currencyInfo(PublicKey)
        /// Same screen as `currencyInfo` but auto-presents the buy nested
        /// sheet on appear. Modelled as a sibling case rather than an
        /// associated-value flag so the trace shows "user wanted to deposit"
        /// distinctly from "user opened currency info".
        case currencyInfoForDeposit(PublicKey)
        case discoverCurrencies
        case currencyCreationSummary
        case currencyCreationWizard
        case transactionHistory(PublicKey)
        case give(PublicKey)

        // Settings flow
        case settingsMyAccount
        case settingsAdvancedFeatures
        case settingsAppSettings
        case settingsBetaFlags
        case settingsAccountSelection
        case settingsApplicationLogs
        case accessKey
        case depositCurrencyList
        case deposit(PublicKey)
        case withdraw

        /// The stack this destination naturally belongs in. Cross-stack
        /// navigation uses this to know which sheet to present.
        var owningStack: Stack {
            switch self {
            case .currencyInfo, .currencyInfoForDeposit, .discoverCurrencies,
                 .currencyCreationSummary, .currencyCreationWizard,
                 .transactionHistory, .give:
                return .balance
            case .settingsMyAccount, .settingsAdvancedFeatures, .settingsAppSettings,
                 .settingsBetaFlags, .settingsAccountSelection,
                 .settingsApplicationLogs, .accessKey, .depositCurrencyList, .deposit, .withdraw:
                return .settings
            }
        }

        /// Stable, payload-free name. Used as the `destination` log key so a
        /// trail can be filtered with `grep destination=currencyInfo` regardless
        /// of which mint was opened. The mint itself is surfaced separately via
        /// the `payload` metadata so it remains queryable but doesn't fragment
        /// the destination buckets.
        var description: String {
            switch self {
            case .currencyInfo:                 "currencyInfo"
            case .currencyInfoForDeposit:       "currencyInfoForDeposit"
            case .discoverCurrencies:           "discoverCurrencies"
            case .currencyCreationSummary:      "currencyCreationSummary"
            case .currencyCreationWizard:       "currencyCreationWizard"
            case .transactionHistory:           "transactionHistory"
            case .give:                         "give"
            case .settingsMyAccount:            "settingsMyAccount"
            case .settingsAdvancedFeatures:     "settingsAdvancedFeatures"
            case .settingsAppSettings:          "settingsAppSettings"
            case .settingsBetaFlags:            "settingsBetaFlags"
            case .settingsAccountSelection:     "settingsAccountSelection"
            case .settingsApplicationLogs:      "settingsApplicationLogs"
            case .accessKey:                    "accessKey"
            case .depositCurrencyList:          "depositCurrencyList"
            case .deposit:                      "deposit"
            case .withdraw:                     "withdraw"
            }
        }

        /// Identifying associated value, if any, suitable for log metadata.
        /// Returns `nil` for payload-free destinations so the log key is
        /// omitted rather than serialised as an empty string.
        var payload: String? {
            switch self {
            case .currencyInfo(let mint),
                 .currencyInfoForDeposit(let mint),
                 .transactionHistory(let mint),
                 .give(let mint),
                 .deposit(let mint):
                return mint.base58
            case .discoverCurrencies, .currencyCreationSummary, .currencyCreationWizard,
                 .settingsMyAccount, .settingsAdvancedFeatures, .settingsAppSettings,
                 .settingsBetaFlags, .settingsAccountSelection,
                 .settingsApplicationLogs, .accessKey, .depositCurrencyList, .withdraw:
                return nil
            }
        }
    }
}
