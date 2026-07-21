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
        /// Skips the picker step in the withdraw flow and lands the user on
        /// `WithdrawIntroScreen` with the currency pre-selected. Pushed from
        /// USDF Currency Info on the Wallet sheet.
        case withdrawCurrency(PublicKey)
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
        case accessKey
        case withdraw

        // Tips flow
        case profileName
        case profilePhoto

        // Conversation flow
        /// A DM conversation, pushed onto the `.send` stack — from the Chats
        /// section of the recipient picker (`.existing`) or by tapping a synced
        /// contact (`.contact`, in which case the chat may not exist yet; the
        /// first payment creates it). Deeplinks and push notifications land here
        /// via `navigate(to: .dmConversation)`. Send Cash presents the amount
        /// entry as `SheetPresentation.sendAmount` over this.
        case dmConversation(ConversationContext)

        /// The stack this destination naturally belongs in. Cross-stack
        /// navigation uses this to know which sheet to present.
        var owningStack: Stack {
            switch self {
            case .currencyInfo, .currencyInfoForDeposit, .discoverCurrencies,
                 .currencyCreationSummary, .currencyCreationWizard,
                 .transactionHistory, .give, .withdrawCurrency,
                 .usdcDepositEducation, .usdcDepositAddress:
                return .balance
            case .settingsMyAccount, .settingsAdvancedFeatures, .settingsAdvancedBetaFeatures,
                 .settingsAppSettings, .settingsBetaFlags, .settingsAccountSelection,
                 .settingsApplicationLogs, .accessKey, .withdraw:
                return .settings
            case .profileName, .profilePhoto:
                return .tips
            case .dmConversation:
                return .send
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
            case .accessKey:                    "accessKey"
            case .withdraw:                     "withdraw"
            case .profileName:                  "profileName"
            case .profilePhoto:                 "profilePhoto"
            case .dmConversation:               "dmConversation"
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
                 .withdrawCurrency(let mint):
                return mint.base58
            case .dmConversation(.existing(let conversationID)):
                return conversationID.description
            case .dmConversation(.contact(let contact)):
                return contact.contactId
            case .discoverCurrencies, .currencyCreationSummary, .currencyCreationWizard,
                 .usdcDepositEducation, .usdcDepositAddress,
                 .settingsMyAccount, .settingsAdvancedFeatures, .settingsAdvancedBetaFeatures,
                 .settingsAppSettings, .settingsBetaFlags, .settingsAccountSelection,
                 .settingsApplicationLogs, .accessKey, .withdraw,
                 .profileName, .profilePhoto:
                return nil
            }
        }
    }
}
