//
//  AccountSelectionScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-03-04.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct AccountSelectionScreen: View {

    @EnvironmentObject private var client: Client
    @EnvironmentObject private var ratesController: RatesController

    @Binding public var isPresented: Bool

    private let sessionAuthenticator: SessionAuthenticator
    private let accountManager: AccountManager

    @State private var accounts: [HistoricalAccount] = []

    private let action: (AccountDescription) -> Void

    private var balanceRate: Rate {
        ratesController.rateForBalanceCurrency()
    }

    // MARK: - Init -

    public init(isPresented: Binding<Bool>, sessionAuthenticator: SessionAuthenticator, action: @escaping (AccountDescription) -> Void) {
        self._isPresented = isPresented
        self.sessionAuthenticator = sessionAuthenticator
        self.accountManager = sessionAuthenticator.accountManager
        self.action = action
    }

    // MARK: - Body -

    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                List {
                    ForEach(accounts) { account in
                        row(for: account)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparatorTint(Color.rowSeparator)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
        }
        .onAppear {
            fetchAccounts()
            fetchBalances()
        }
    }

    @ViewBuilder private func row(for account: HistoricalAccount) -> some View {
        Button {
            action(account.details)
        } label: {
            HStack(alignment: .center, spacing: 15) {
                CheckView(active: isSelected(for: account.details))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .bottom, spacing: 10) {
                        Text(account.mnemonic.name)

                        if account.isNotFound {
                            Badge(decoration: .circle(.textError), text: "Not Found")
                        }

                        Spacer()

                        if let balance = account.totalBalance {
                            AmountText(
                                flagStyle: balance.converted.currencyCode.flagStyle,
                                flagSize: .small,
                                content: balance.converted.formatted(),
                                canScale: false
                            )
                            .font(.appTextMedium)
                        }
                    }
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                    .padding(.bottom, 5)

                    Group {
                        Text("Created \(DateFormatter.relative.string(from: account.details.creationDate))")
                        Text(account.details.account.ownerPublicKey.base58)
                            .truncationMode(.middle)
                    }
                    .font(.appTextHeading)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity)
                .lineLimit(1)
            }
        }
        .listRowBackground(Color.backgroundMain)
        .padding(20)
        .swipeActions {
            Button {
                withAnimation {
                    deleteAccount(description: account.details)
                }
            } label: {
                Image.asset(.delete)
            }
            .tint(.bannerError)
        }
        .contextMenu {
            Button {
                copyAccessKey(description: account.details)
            } label: {
                Label("Copy Access Key", systemImage: SystemSymbol.doc.rawValue)
            }

            Button {
                copyVaultAddress(description: account.details)
            } label: {
                Label("Copy Vault Address", systemImage: SystemSymbol.doc.rawValue)
            }
        }
    }

    private func isSelected(for description: AccountDescription) -> Bool {
        switch sessionAuthenticator.state {
        case .loggedIn(let container):
            return container.session.ownerKeyPair.publicKey == description.account.ownerPublicKey

        case .loggedOut, .migrating, .pending:
            return false
        }
    }

    // MARK: - Actions -

    private func copyAccessKey(description: AccountDescription) {
        UIPasteboard.general.string = description.account.mnemonic.words.joined(separator: " ")
    }

    private func copyVaultAddress(description: AccountDescription) {
        let cluster = AccountCluster(
            authority: .derive(
                using: .primary(),
                mnemonic: description.account.mnemonic
            ),
            mint: .usdc,
            timeAuthority: .usdcAuthority
        )

        UIPasteboard.general.string = cluster.vaultPublicKey.base58
    }

    private func deleteAccount(description: AccountDescription) {
        accountManager.setDeleted(
            ownerPublicKey: description.account.owner.publicKey,
            deleted: true
        )

        let accountIndex = accounts.firstIndex { $0.details.account.ownerPublicKey == description.account.ownerPublicKey }
        if let accountIndex = accountIndex {
            accounts.remove(at: accountIndex)
        }
    }

    private func fetchAccounts() {
        accounts = accountManager.fetchHistorical()
            .map {
                HistoricalAccount(details: $0)
            }
            .filter {
                // Don't show deleted accounts
                $0.details.deletionDate == nil
            }
    }

    private func fetchBalances() {
        // Capture rate before entering async context
        let rate = balanceRate

        Task {
            await withThrowingTaskGroup(of: Void.self) { group in
                accounts.forEach { historicalAccount in
                    group.addTask {
                        let owner = historicalAccount.details.account.owner
                        do {
                            // Fetch ALL primary accounts (all mints) for this owner
                            let accountInfos = try await client.fetchPrimaryAccounts(owner: owner)

                            // Calculate total USDC value across all mints
                            var totalUSDCQuarks: UInt64 = 0

                            for info in accountInfos {
                                if info.mint == .usdc {
                                    // Direct USDC balance
                                    totalUSDCQuarks += info.quarks
                                } else {
                                    // Custom token - would need bonding curve calculation
                                    // For now, we'll skip non-USDC tokens in account selection
                                    // as we don't have token metadata available here
                                }
                            }

                            // Convert total USDC to display currency
                            let usdcFiat = Fiat(
                                quarks: totalUSDCQuarks,
                                currencyCode: .usd,
                                decimals: PublicKey.usdc.mintDecimals
                            )

                            let exchangedFiat = try ExchangedFiat(
                                usdc: usdcFiat,
                                rate: rate,
                                mint: .usdc
                            )

                            await update(owner: owner.publicKey) {
                                $0.setBalance(exchangedFiat)
                            }

                        } catch ErrorFetchBalance.notFound {
                            await update(owner: owner.publicKey) {
                                $0.setNotFound()
                            }
                        } catch {
                            // Silently ignore conversion errors
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func update(owner: PublicKey, handler: @MainActor (inout HistoricalAccount) -> Void) {
        let index = accounts.firstIndex { $0.details.account.ownerPublicKey == owner }

        guard let index = index else {
            return
        }

        handler(&accounts[index])
    }
}

// MARK: - HistoricalAccount -

@MainActor
class HistoricalAccount: Identifiable {

    nonisolated
    var id: String {
        details.account.ownerPublicKey.base58
    }

    nonisolated
    let details: AccountDescription

    let cluster: AccountCluster
    let mnemonic: MnemonicPhrase

    private(set) var totalBalance: ExchangedFiat?
    private(set) var isNotFound: Bool = false

    init(details: AccountDescription) {
        self.details  = details
        self.mnemonic = details.account.mnemonic
        self.cluster  = AccountCluster(
            authority: .derive(using: .primary(), mnemonic: details.account.mnemonic),
            mint: .usdc,
            timeAuthority: .usdcAuthority
        )
    }

    func setBalance(_ exchangedFiat: ExchangedFiat) {
        totalBalance = exchangedFiat
    }

    func setNotFound() {
        isNotFound = true
    }
}
