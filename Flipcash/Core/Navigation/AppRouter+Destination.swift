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
        /// The "How Market Cap Works" explainer for one currency.
        case marketCapExplainer(PublicKey)
        /// The unified, cross-token activity history — the "dive in" from the
        /// Wallet's Recent section. `transactionHistory` is the per-token slice.
        case activity
        /// One activity entry, opened by tapping its row anywhere the row is
        /// drawn. Carries the whole ``Activity`` rather than an id: the row
        /// already holds it, and the feed's local store has no by-id lookup to
        /// re-read it from.
        case transactionDetails(Activity)
        case give(PublicKey)
        /// Pushes the buy flow (`BuyAmountScreen`) onto the current stack instead
        /// of presenting it as a sheet — the currency-info "Get" tile.
        case buyCurrency(PublicKey)
        /// Pushes the convert flow (`ConvertAmountScreen`) onto the current stack
        /// — the currency-info "Convert" tile. Sells this currency into a
        /// chosen destination (Dollars or another launchpad token).
        case convertCurrency(PublicKey)
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
        /// The Settings list, opened from the gear on the You tab.
        case settings
        /// The account's phone, email, user ID and public key, opened from Settings.
        case accountInfo
        /// The signed-in user's profile fields in one list, opened from the You tab's Edit Profile button.
        case editProfile
        /// The bio on its own, pushed from Edit Profile.
        case editBio
        /// The public groups shown on the signed-in user's profile, chosen from Edit Profile.
        case editFeaturedGroups
        /// The cover banner on its own, pushed from Edit Profile.
        case changeCoverPicture
        /// The display name on its own, edited from Settings. The full
        /// profile-setup flow starts on the same screen but carries on to the
        /// tip card; this one returns to the settings list.
        case changeDisplayName
        /// The profile picture on its own, changed from the You tab's checklist.
        /// The full profile-setup flow uses `.profilePhoto`, which carries on to
        /// the tip card; this one returns to the screen that opened it.
        case changeProfilePicture
        /// The public handle, claimed from the You page or changed from
        /// Settings. One destination for both: the screen seeds itself from the
        /// handle already on the profile, so there is nothing to distinguish.
        case username(Username?)
        /// The minimum a tipper must pay to open a DM. `isSetupStep` marks the
        /// You tab's checklist apart from a lone edit in Settings; it reaches
        /// the payload only, since the screen is the same from either.
        case setMinimumTip(isSetupStep: Bool)
        case settingsAdvancedBetaFeatures
        case settingsAppSettings
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
        /// Finding someone by their Flipcash handle, opened from the Chats tab.
        /// Distinct from `.username`, which claims the signed-in user's own.
        case usernameLookup
        /// The list of ways to start a chat, pushed from the Chats tab's `+`.
        case newChat
        /// The "New Public Group" form, opened from the New Chat screen.
        case newPublicGroup
        /// A tip DM conversation, pushed onto the `.tips` stack — from the
        /// Tips list or a tip-DM push notification.
        case tipConversation(ConversationID)
        /// Same screen as `tipConversation` but opens with the message field
        /// focused and the keyboard up. Modelled as a sibling case rather than
        /// an associated-value flag (matching `currencyInfoForDeposit`) so the
        /// trace shows "post-tip, keyboard up" distinctly, and so the ordinary
        /// tip-list / push-notification opens stay keyboard-closed untouched.
        case tipConversationWithKeyboard(ConversationID)
        /// A person's Flipcash profile, pushed from a tip DM's title/card or a group member's face;
        /// hosts the Block action. `origin` decides whether it offers a way into the DM.
        case userProfile(UserID, origin: UserProfileOrigin)
        /// A group chat's own profile, pushed from its navigation title or a favorite group. `origin`
        /// decides whether Open Chat returns to the chat underneath or opens it.
        case chatProfile(ConversationID, origin: ChatProfileOrigin)
        /// What an editor can change about a group, pushed from the chat profile's overflow menu.
        /// Only reachable while ``Conversation/canEdit`` holds.
        case editGroup(ConversationID)
        /// Renaming a group, pushed from the Group name card of `editGroup`.
        case editGroupName(ConversationID)
        /// Replacing a group's picture, pushed from the photo on `editGroup`.
        case editGroupPicture(ConversationID)
        /// Replacing a group's cover banner, pushed from the cover on `editGroup`.
        case editGroupCover(ConversationID)
        /// Setting or clearing a group's description, pushed from the Description card of `editGroup`.
        case editGroupDescription(ConversationID)
        /// Replacing a group's join or chat minimum balance, pushed from a Balance Requirements row
        /// of `editGroup`.
        case editGroupBalanceRequirement(ConversationID, role: GroupBalanceRole)
        /// The list of archived chats, pushed from the Archived row on the Chats tab.
        case archivedChats

        /// The stack this destination naturally belongs in. Cross-stack
        /// navigation uses this to know which sheet to present, or which tab
        /// to bring forward when the stack is tab-hosted.
        ///
        /// The settings destinations own `.you`: the You tab renders the
        /// settings list inline and pushes them onto its own stack — there is
        /// no Settings sheet to present them in.
        var owningStack: Stack {
            switch self {
            case .currencyInfo, .currencyInfoForDeposit, .discoverCurrencies,
                 .currencyCreationSummary, .currencyCreationWizard,
                 .transactionHistory, .marketCapExplainer, .activity, .transactionDetails, .give,
                 .buyCurrency, .convertCurrency,
                 .withdrawCurrency, .usdcDepositEducation, .usdcDepositAddress:
                return .balance
            case .settings, .accountInfo, .editProfile, .editBio, .editFeaturedGroups, .changeCoverPicture,
                 .changeDisplayName, .changeProfilePicture, .username,
                 .setMinimumTip,
                 .settingsAdvancedBetaFeatures, .settingsAppSettings, .settingsAccountSelection,
                 .settingsApplicationLogs, .blockedUsers, .accessKey, .withdraw:
                return .you
            case .profileName, .profilePhoto, .tipcard, .usernameLookup, .newChat, .newPublicGroup,
                 .tipConversation, .tipConversationWithKeyboard, .userProfile, .chatProfile,
                 .editGroup, .editGroupName, .editGroupPicture, .editGroupCover,
                 .editGroupDescription, .editGroupBalanceRequirement, .archivedChats:
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
            case .marketCapExplainer:           "marketCapExplainer"
            case .activity:                     "activity"
            case .transactionDetails:           "transactionDetails"
            case .give:                         "give"
            case .buyCurrency:                  "buyCurrency"
            case .convertCurrency:              "convertCurrency"
            case .withdrawCurrency:             "withdrawCurrency"
            case .usdcDepositEducation:         "usdcDepositEducation"
            case .usdcDepositAddress:           "usdcDepositAddress"
            case .settings:                     "settings"
            case .accountInfo:                  "accountInfo"
            case .editProfile:                  "editProfile"
            case .editBio:                      "editBio"
            case .editFeaturedGroups:           "editFeaturedGroups"
            case .changeCoverPicture:           "changeCoverPicture"
            case .changeDisplayName:            "changeDisplayName"
            case .changeProfilePicture:         "changeProfilePicture"
            case .username:                     "username"
            case .setMinimumTip:                "setMinimumTip"
            case .settingsAdvancedBetaFeatures: "settingsAdvancedBetaFeatures"
            case .settingsAppSettings:          "settingsAppSettings"
            case .settingsAccountSelection:     "settingsAccountSelection"
            case .settingsApplicationLogs:      "settingsApplicationLogs"
            case .blockedUsers:                 "blockedUsers"
            case .accessKey:                    "accessKey"
            case .withdraw:                     "withdraw"
            case .profileName:                  "profileName"
            case .profilePhoto:                 "profilePhoto"
            case .tipcard:                      "tipcard"
            case .usernameLookup:               "usernameLookup"
            case .newChat:                      "newChat"
            case .newPublicGroup:               "newPublicGroup"
            case .tipConversation:              "tipConversation"
            case .tipConversationWithKeyboard:  "tipConversationWithKeyboard"
            case .userProfile:                  "userProfile"
            case .chatProfile:                  "chatProfile"
            case .editGroup:                    "editGroup"
            case .editGroupName:                "editGroupName"
            case .editGroupPicture:             "editGroupPicture"
            case .editGroupCover:               "editGroupCover"
            case .editGroupDescription:         "editGroupDescription"
            case .editGroupBalanceRequirement:  "editGroupBalanceRequirement"
            case .archivedChats:                "archivedChats"
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
                 .marketCapExplainer(let mint),
                 .give(let mint),
                 .buyCurrency(let mint),
                 .convertCurrency(let mint):
                return mint.base58
            case .withdrawCurrency(let mint):
                return mint?.base58
            case .transactionDetails(let activity):
                return activity.id.base58
            case .tipConversation(let conversationID),
                 .tipConversationWithKeyboard(let conversationID),
                 .chatProfile(let conversationID, _),
                 .editGroup(let conversationID),
                 .editGroupName(let conversationID),
                 .editGroupPicture(let conversationID),
                 .editGroupCover(let conversationID),
                 .editGroupDescription(let conversationID):
                return conversationID.description
            case .editGroupBalanceRequirement(let conversationID, let role):
                return "\(conversationID.description) \(role)"
            case .userProfile(let userID, _):
                return userID.uuidString
            case .username(let username):
                return username?.value
            case .setMinimumTip(let isSetupStep):
                return isSetupStep ? "setup" : "settings"
            case .activity,
                 .discoverCurrencies, .currencyCreationSummary, .currencyCreationWizard,
                 .usdcDepositEducation, .usdcDepositAddress,
                 .settings, .accountInfo, .editProfile, .editBio, .editFeaturedGroups, .changeCoverPicture,
                 .changeDisplayName, .changeProfilePicture,
                 .settingsAdvancedBetaFeatures, .settingsAppSettings, .settingsAccountSelection,
                 .settingsApplicationLogs, .blockedUsers, .accessKey, .withdraw,
                 .profileName, .profilePhoto, .tipcard, .usernameLookup, .newChat, .newPublicGroup,
                 .archivedChats:
                return nil
            }
        }
    }
}
