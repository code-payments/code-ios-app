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

        case .give(let mint):
            // `.id(mint)` for the same reason as `.currencyInfo` above —
            // a deeplink replacing `.give(A)` with `.give(B)` must build a
            // fresh `GiveViewModel`, not reuse the one wired to `A`.
            GiveScreen(mint: mint)
                .id(mint)

        // MARK: - Settings flow

        case .settingsMyAccount:
            SettingsMyAccountScreen()

        case .settingsAdvancedFeatures:
            SettingsAdvancedFeaturesScreen()

        case .settingsAdvancedBetaFeatures:
            SettingsAdvancedBetaFeaturesScreen()

        case .settingsAppSettings:
            SettingsAppSettingsScreen()

        case .settingsBetaFlags:
            BetaFlagsScreen()

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

        case .accessKey:
            AccessKeyBackupScreen(mnemonic: sessionContainer.session.keyAccount.mnemonic)
                .navigationTitle("Access Key")
                .toolbarTitleDisplayMode(.inline)

        case .deposit:
            USDCDepositEducationScreen(
                onNext: { sessionContainer.appRouter.push(.usdcDepositAddress) },
                onDepositOtherCurrencies: {
                    sessionContainer.appRouter.push(.depositCurrencyList)
                }
            )

        case .depositCurrencyList:
            DepositCurrencyListScreen()

        case .depositAddress(let mint):
            // Resolves the cluster from the live `session.balance(for:)` lookup
            // — the destination only carries the mint so it stays Hashable +
            // Sendable. If the balance vanished between push and render
            // (shouldn't happen from the in-app picker, but possible from a
            // future deeplink), render an empty placeholder rather than crash.
            if let balance = sessionContainer.session.balance(for: mint),
               let vmAuthority = balance.vmAuthority {
                DepositScreen(
                    address: sessionContainer.session.owner.use(
                        mint: mint,
                        timeAuthority: vmAuthority
                    ).depositPublicKey.base58,
                    name: mint == .usdf ? balance.symbol : balance.name
                )
            }

        case .withdraw:
            PreselectedWithdrawRoot(
                mint: .usdf,
                onComplete: { sessionContainer.appRouter.popToRoot(on: .settings) },
                onWithdrawOtherCurrencies: {
                    sessionContainer.appRouter.pushAny(WithdrawNavigationPath.picker)
                }
            )

        case .withdrawCurrency(let mint):
            PreselectedWithdrawRoot(
                mint: mint,
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
            // Authority pubkey, NOT the derived USDC ATA. Showing the ATA
            // breaks first-time deposits: it doesn't exist on-chain yet, so
            // wallets fall back to "treat as owner, derive another ATA" and
            // funds land one level deeper than the server queries.
            DepositScreen(
                address: sessionContainer.session.owner.authorityPublicKey.base58,
                name: "USDC"
            )

        case .phantomFlow(let fundingOperation):
            PhantomFlowScreen(fundingOperation: fundingOperation)

        // MARK: - Conversation flow

        case .dmConversation(let context):
            // `.id(context)` forces fresh view identity per conversation.
            ConversationScreen(context: context)
                .id(context)
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
    }
}
