//
//  AppRouter+DestinationView.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import FlipcashCore

/// Renders an `AppRouter.Destination` as the corresponding screen. Single
/// destination → view map for the whole app. Adding a new destination case
/// requires a new arm here; the exhaustive switch enforces this at compile time.
struct DestinationView: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    let destination: AppRouter.Destination

    var body: some View {
        switch destination {

        // MARK: - Wallet flow

        case .currencyInfo(let mint):
            // `.id(mint)` forces a fresh view identity (and thus fresh `@State`,
            // including a fresh `CurrencyInfoViewModel`) whenever the mint
            // changes. Without it, SwiftUI reuses the existing view at the same
            // navigation depth — same struct type, same position — and the
            // viewModel keeps the old token's data, so deeplinks that replace
            // `[.currencyInfo(A)]` with `[.currencyInfo(B)]` show stale UI.
            CurrencyInfoScreen(mint: mint)
                .id(mint)

        case .currencyInfoForDeposit(let mint):
            CurrencyInfoScreen(mint: mint, showBuyOnAppear: true)
                .id(mint)

        case .discoverCurrencies:
            CurrencyDiscoveryScreen()

        case .currencyCreationSummary:
            CurrencyCreationSummaryScreen()

        case .currencyCreationWizard:
            CurrencyCreationWizardScreen(state: CurrencyCreationState())

        case .transactionHistory(let mint):
            TransactionHistoryScreen(mint: mint)

        case .activity:
            ActivityHistoryScreen()

        case .give(let mint):
            // `.id(mint)` for the same reason as `.currencyInfo` above —
            // a deeplink replacing `.give(A)` with `.give(B)` must build a
            // fresh `GiveViewModel`, not reuse the one wired to `A`.
            GiveScreen(mint: mint)
                .id(mint)

        case .buyCurrency(let mint):
            BuyAmountScreen(mint: mint)

        case .convertCurrency(let mint):
            ConvertAmountScreen(mint: mint)

        // MARK: - Settings flow

        case .settingsMyAccount:
            SettingsMyAccountScreen()

        case .changeDisplayName:
            ChangeDisplayNameScreen(currentName: sessionContainer.session.profile?.displayName ?? "")

        case .changeProfilePicture:
            ChangeProfilePictureScreen(currentName: sessionContainer.session.profile?.displayName ?? "")

        case .username(let username):
            UsernameEntryScreen(currentUsername: username)

        case .settingsAdvancedFeatures:
            SettingsAdvancedFeaturesScreen()

        case .settingsAdvancedBetaFeatures:
            SettingsAdvancedBetaFeaturesScreen()

        case .settingsAppSettings:
            SettingsAppSettingsScreen()

        case .settingsAccountSelection:
            // The action closure dismisses the settings sheet and switches accounts.
            // Captured at the modifier site so the AppRouter stays pure-navigation.
            AccountSelectionScreen(
                sessionAuthenticator: container.sessionAuthenticator,
                action: { [appRouter = sessionContainer.appRouter, sessionAuthenticator = container.sessionAuthenticator] account in
                    Task { @MainActor in
                        appRouter.dismissSheet()
                        try? await Task.delay(milliseconds: 250)
                        sessionAuthenticator.switchAccount(to: account.account.mnemonic)
                    }
                }
            )

        case .settingsApplicationLogs:
            ApplicationLogsScreen()

        case .blockedUsers:
            BlockedUsersScreen()

        case .accessKey:
            AccessKeyBackupScreen(mnemonic: sessionContainer.session.keyAccount.mnemonic)
                .navigationTitle("Access Key")
                .toolbarTitleDisplayMode(.inline)

        case .withdraw:
            // No preselected mint — the flow starts on the currency picker.
            WithdrawFlowRoot(
                onComplete: { sessionContainer.appRouter.popToRoot() }
            )

        case .withdrawCurrency(let mint):
            WithdrawFlowRoot(
                preselectedMint: mint,
                // Reachable from the Wallet (.balance) and — since cash cards open currency info — from
                // a chat (.send). Reset the host stack, not a hardcoded one, so the
                // user isn't stranded on the finished withdraw screen when it ran over a chat.
                onComplete: { sessionContainer.appRouter.popToRoot() }
            )

        case .usdcDepositEducation:
            USDCDepositEducationScreen(
                onNext: { sessionContainer.appRouter.push(.usdcDepositAddress) }
            )

        case .usdcDepositAddress:
            DepositScreen.usdcDeposit(session: sessionContainer.session)

        // MARK: - Tips flow

        case .profileName:
            ProfileNameScreen()

        case .profilePhoto:
            ProfilePhotoScreen()

        case .tipcard:
            TipcardScreen()

        case .usernameLookup:
            UsernameLookupScreen()

        case .tipConversation(let conversationID):
            // `.id` forces fresh view identity per conversation.
            ConversationScreen(context: .existing(conversationID))
                .id(conversationID)

        case .tipConversationWithKeyboard(let conversationID):
            // Post-tip open: same screen, but focus the field so the keyboard
            // comes up. `.id` forces fresh view identity per conversation.
            ConversationScreen(context: .existing(conversationID), openKeyboard: true)
                .id(conversationID)

        case .tipConversationForUser(let userID):
            // Opened before the chat exists, so the screen is given the person
            // and derives the chat id itself. `.id` forces fresh view identity.
            ConversationScreen(context: .tipDM(counterpart: userID))
                .id(userID)

        case .userProfile(let userID):
            UserProfileScreen(userID: userID)
                .id(userID)
        }
    }
}

extension View {

    /// Attaches the app-wide destination → view map to a NavigationStack.
    /// Apply on the root content view of every NavigationStack(path:) bound to
    /// `$router[.<stack>]`.
    func appRouterDestinations() -> some View {
        navigationDestination(for: AppRouter.Destination.self) { destination in
            DestinationView(destination: destination)
        }
        // The Add Money deposit flow pushes onto whichever stack launched it
        // (wallet, settings, buy, chat, …) rather than opening its own sheet,
        // so every app stack registers its steps here.
        .navigationDestination(for: AddMoneyFlowStep.self) { step in
            AddMoneyFlowStepDestination(step: step)
        }
        // The up-front debit-card verification (intro → phone → email) pushes
        // onto the same stack ahead of the deposit flow.
        .navigationDestination(for: OnrampVerificationPath.self) { path in
            OnrampVerificationPushedStep(path: path)
        }
        // Sheet-hosted stacks otherwise recognize swipe-back from anywhere; keep
        // it to the leading edge, matching the root stack and system behavior.
        .edgeOnlySwipeBack()
    }
}

/// Renders a pushed Add Money deposit step on the app's shared stacks.
/// Advancing pushes the next step onto the same stack.
private struct AddMoneyFlowStepDestination: View {

    let step: AddMoneyFlowStep

    @Environment(AppRouter.self) private var router

    var body: some View {
        AddMoneyFlowDestination(step: step, onStep: { router.pushAny($0) })
            .environment(\.dismissParentContainer, {
                // The flow is pushed onto the host stack, so finishing pops back
                // to that stack's root, returning to where it was launched.
                router.popToRoot()
            })
    }
}
