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
        /// The unified, cross-token activity history — the "dive in" from the
        /// Wallet's Recent section. `transactionHistory` is the per-token slice.
        case activity
        case give(PublicKey)
        /// Pushes the buy flow (`BuyAmountScreen`) onto the current stack instead
        /// of presenting it as a sheet — the new-UI currency-info "Convert"/"Get".
        case buyCurrency(PublicKey)
        /// Withdraw flow on the Wallet's stack (pops back to the wallet on
        /// finish). `nil` starts on the currency picker; a mint skips the picker
        /// pre-selected — Dollars (USDF) lands on the "Withdraw as USDC" intro,
        /// any other currency on the amount screen. Pushed from the Wallet
        /// "Withdraw Money" tile (`nil`) and Currency Info (a mint).
        case withdrawCurrency(PublicKey?)
        /// USDC → USDF deposit education screen.
        case usdcDepositEducation
        /// USDC → USDF deposit address screen. Shows the user's authority
        /// pubkey — wallets derive the USDC ATA from it on send.
        case usdcDepositAddress

        // Settings flow
        case settingsMyAccount
        case settingsAdvancedFeatures
        case settingsAdvancedBetaFeatures
        case settingsAppSettings
        case settingsBetaFlags
        case settingsAccountSelection
        case settingsApplicationLogs
        case blockedUsers
        case accessKey
        case withdraw

        // Tips flow
        case profileName
        case profilePhoto
        /// The signed-in user's own tipcard, pushed from the Tips list.
        case tipcard
        /// A tip DM conversation, pushed onto the `.tips` stack — from the
        /// Tips list or a tip-DM push notification.
        case tipConversation(ConversationID)
        /// Same screen as `tipConversation` but opens with the message field
        /// focused and the keyboard up. Modelled as a sibling case rather than
        /// an associated-value flag (matching `currencyInfoForDeposit`) so the
        /// trace shows "post-tip, keyboard up" distinctly, and so the ordinary
        /// tip-list / push-notification opens stay keyboard-closed untouched.
        case tipConversationWithKeyboard(ConversationID)
        /// The counterpart's Flipcash profile, pushed from a tip DM's title/card; hosts the Block action.
        case userProfile(UserID)

        /// The stack this destination naturally belongs in. Cross-stack
        /// navigation uses this to know which sheet to present.
        var owningStack: Stack {
            switch self {
            case .currencyInfo, .currencyInfoForDeposit, .discoverCurrencies,
                 .currencyCreationSummary, .currencyCreationWizard,
                 .transactionHistory, .activity, .give, .buyCurrency, .withdrawCurrency,
                 .usdcDepositEducation, .usdcDepositAddress:
                return .balance
            case .settingsMyAccount, .settingsAdvancedFeatures, .settingsAdvancedBetaFeatures,
                 .settingsAppSettings, .settingsBetaFlags, .settingsAccountSelection,
                 .settingsApplicationLogs, .blockedUsers, .accessKey, .withdraw:
                return .settings
            case .profileName, .profilePhoto, .tipcard,
                 .tipConversation, .tipConversationWithKeyboard, .userProfile:
                return .tips
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
            case .activity:                     "activity"
            case .give:                         "give"
            case .buyCurrency:                  "buyCurrency"
            case .withdrawCurrency:             "withdrawCurrency"
            case .usdcDepositEducation:         "usdcDepositEducation"
            case .usdcDepositAddress:           "usdcDepositAddress"
            case .settingsMyAccount:            "settingsMyAccount"
            case .settingsAdvancedFeatures:     "settingsAdvancedFeatures"
            case .settingsAdvancedBetaFeatures: "settingsAdvancedBetaFeatures"
            case .settingsAppSettings:          "settingsAppSettings"
            case .settingsBetaFlags:            "settingsBetaFlags"
            case .settingsAccountSelection:     "settingsAccountSelection"
            case .settingsApplicationLogs:      "settingsApplicationLogs"
            case .blockedUsers:                 "blockedUsers"
            case .accessKey:                    "accessKey"
            case .withdraw:                     "withdraw"
            case .profileName:                  "profileName"
            case .profilePhoto:                 "profilePhoto"
            case .tipcard:                      "tipcard"
            case .tipConversation:              "tipConversation"
            case .tipConversationWithKeyboard:  "tipConversationWithKeyboard"
            case .userProfile:                  "userProfile"
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
                 .buyCurrency(let mint):
                return mint.base58
            case .withdrawCurrency(let mint):
                return mint?.base58
            case .tipConversation(let conversationID),
                 .tipConversationWithKeyboard(let conversationID):
                return conversationID.description
            case .userProfile(let userID):
                return userID.uuidString
            case .activity,
                 .discoverCurrencies, .currencyCreationSummary, .currencyCreationWizard,
                 .usdcDepositEducation, .usdcDepositAddress,
                 .settingsMyAccount, .settingsAdvancedFeatures, .settingsAdvancedBetaFeatures,
                 .settingsAppSettings, .settingsBetaFlags, .settingsAccountSelection,
                 .settingsApplicationLogs, .blockedUsers, .accessKey, .withdraw,
                 .profileName, .profilePhoto, .tipcard:
                return nil
            }
        }
    }
}
