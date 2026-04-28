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

    let destination: AppRouter.Destination
    let container: Container
    let sessionContainer: SessionContainer

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
            CurrencyInfoScreen(
                mint: mint,
                container: container,
                sessionContainer: sessionContainer
            )
            .id(mint)

        case .currencyInfoForDeposit(let mint):
            CurrencyInfoScreen(
                mint: mint,
                container: container,
                sessionContainer: sessionContainer,
                showFundingOnAppear: true
            )
            .id(mint)

        case .discoverCurrencies:
            CurrencyDiscoveryScreen(
                container: container,
                sessionContainer: sessionContainer
            )

        case .currencyCreationSummary:
            CurrencyCreationSummaryScreen()

        case .currencyCreationWizard:
            CurrencyCreationWizardScreen(
                state: CurrencyCreationState(),
                sessionContainer: sessionContainer
            )

        case .transactionHistory(let mint):
            TransactionHistoryScreen(mint: mint)

        case .give(let mint):
            // Builds a fresh `GiveViewModel` and primes its presentation
            // lifecycle (`isPresented = true`) so `refreshSelectedBalance`
            // and the entered-amount reset run before first render. The
            // wrapper survives recomposition via `@State`, so the viewModel
            // lasts the destination's lifetime.
            GiveDestinationView(
                mint: mint,
                container: container,
                sessionContainer: sessionContainer
            )
            .id(mint)

        // MARK: - Settings flow

        case .settingsMyAccount:
            SettingsMyAccountScreen(
                container: container,
                sessionContainer: sessionContainer
            )

        case .settingsAdvancedFeatures:
            SettingsAdvancedFeaturesScreen()

        case .settingsAppSettings:
            SettingsAppSettingsScreen()

        case .settingsBetaFlags:
            BetaFlagsScreen(container: container)

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
                .navigationBarTitleDisplayMode(.inline)

        case .depositCurrencyList:
            DepositCurrencyListScreen()

        case .deposit(let mint):
            // Resolves the cluster from the live `session.balance(for:)` lookup
            // — the destination only carries the mint so it stays Hashable +
            // Sendable. If the balance vanished between push and render
            // (shouldn't happen from the in-app picker, but possible from a
            // future deeplink), render an empty placeholder rather than crash.
            if let balance = sessionContainer.session.balance(for: mint),
               let vmAuthority = balance.vmAuthority {
                DepositScreen(
                    cluster: sessionContainer.session.owner.use(
                        mint: mint,
                        timeAuthority: vmAuthority
                    ),
                    name: balance.name
                )
            }

        case .withdraw:
            WithdrawScreen(
                container: container,
                sessionContainer: sessionContainer
            )
        }
    }
}

extension View {

    /// Attaches the app-wide destination → view map to a NavigationStack.
    /// Apply on the root content view of every NavigationStack(path:) bound to
    /// `$router[.<stack>]`.
    func appRouterDestinations(container: Container, sessionContainer: SessionContainer) -> some View {
        navigationDestination(for: AppRouter.Destination.self) { destination in
            DestinationView(
                destination: destination,
                container: container,
                sessionContainer: sessionContainer
            )
        }
    }
}

/// Owns the `GiveViewModel` for the `.give(mint)` destination. Constructing
/// the viewModel inline in `DestinationView`'s switch would lose `@State`
/// semantics — every body evaluation would create a fresh instance — so the
/// dedicated wrapper preserves the same instance across recomposition.
///
/// On creation, the viewModel's `isPresented = true` setter fires its didSet
/// (which calls `refreshSelectedBalance` and resets the entered amount). That
/// matches the previous behaviour where `CurrencyInfoScreen.onGive` set
/// `giveViewModel.isPresented = true` immediately before the navigation push.
private struct GiveDestinationView: View {
    @State private var viewModel: GiveViewModel

    init(mint: PublicKey, container: Container, sessionContainer: SessionContainer) {
        sessionContainer.ratesController.selectToken(mint)
        let viewModel = GiveViewModel(container: container, sessionContainer: sessionContainer)
        viewModel.isPresented = true
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        GiveScreen(viewModel: viewModel)
    }
}
