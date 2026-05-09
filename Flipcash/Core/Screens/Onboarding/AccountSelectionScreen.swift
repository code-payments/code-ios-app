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
    @Environment(RatesController.self) private var ratesController: RatesController?

    private let sessionAuthenticator: SessionAuthenticator
    private let accountManager: AccountManager

    @State private var accounts: [HistoricalAccount] = []
    @State private var dialogItem: DialogItem?

    private let action: (AccountDescription) -> Void
    private let onEnterDifferentKey: (() -> Void)?

    private var balanceRate: Rate {
        ratesController?.rateForBalanceCurrency() ?? .oneToOne
    }

    // MARK: - Init -

    public init(sessionAuthenticator: SessionAuthenticator, action: @escaping (AccountDescription) -> Void, onEnterDifferentKey: (() -> Void)? = nil) {
        self.sessionAuthenticator = sessionAuthenticator
        self.accountManager = sessionAuthenticator.accountManager
        self.action = action
        self.onEnterDifferentKey = onEnterDifferentKey
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                List {
                    ForEach(accounts) { account in
                        row(for: account)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparatorTint(Color.rowSeparator)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                if let onEnterDifferentKey {
                    Button("Enter a Different Access Key", action: onEnterDifferentKey)
                        .buttonStyle(.subtle)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Select Account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchAccounts()
            fetchBalances()
        }
        .dialog(item: $dialogItem)
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
                                flagStyle: balance.nativeAmount.currency.flagStyle,
                                flagSize: .small,
                                content: balance.nativeAmount.formatted(),
                                canScale: false
                            )
                            .font(.appTextMedium)
                        }
                    }
                    .font(.appTextMedium)
                    .foregroundStyle(.textMain)
                    .padding(.bottom, 5)

                    Group {
                        Text("Created \(DateFormatter.relative.string(from: account.details.creationDate))")
                        Text(account.details.account.ownerPublicKey.base58)
                            .truncationMode(.middle)
                    }
                    .font(.appTextHeading)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity)
                .lineLimit(1)
            }
        }
        .disabled(isSelected(for: account.details))
        .listRowBackground(Color.backgroundMain)
        .padding(20)
        .swipeActions(allowsFullSwipe: false) {
            if !isSelected(for: account.details) {
                Button {
                    confirmDelete(account: account.details)
                } label: {
                    Image.asset(.delete)
                }
                .tint(.bannerError)
            }
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
            mint: .usdf,
            timeAuthority: .usdcAuthority
        )

        UIPasteboard.general.string = cluster.vaultPublicKey.base58
    }

    private func confirmDelete(account: AccountDescription) {
        dialogItem = .init(
            style: .destructive,
            title: "Remove Account?",
            subtitle: "Make sure you have a backup of your Access Key before removing this account.",
            dismissable: true
        ) {
            DialogAction.destructive("Remove") { [account] in
                withAnimation {
                    deleteAccount(description: account)
                }
            }
            DialogAction.cancel {}
        }
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
        let rate = balanceRate

        Task {
            await withThrowingTaskGroup(of: Void.self) { group in
                accounts.forEach { historicalAccount in
                    group.addTask {
                        let owner = historicalAccount.details.account.owner
                        do {
                            let accountInfos = try await client.fetchPrimaryAccounts(owner: owner)
                            let mints = Set(accountInfos.map { $0.mint })
                            let mintMetadata = try await client.fetchMints(mints: Array(mints))

                            let totalBalance = accountInfos
                                .map { info in
                                    ExchangedFiat.compute(
                                        onChainAmount: TokenAmount(quarks: info.quarks, mint: info.mint),
                                        rate: rate,
                                        supplyQuarks: mintMetadata[info.mint]?.launchpadMetadata?.supplyFromBonding
                                    )
                                }
                                .total(rate: rate)

                            await update(owner: owner.publicKey) {
                                $0.setBalance(totalBalance)
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

    private func update(owner: PublicKey, handler: @MainActor (inout HistoricalAccount) -> Void) {
        let index = accounts.firstIndex { $0.details.account.ownerPublicKey == owner }

        guard let index = index else {
            return
        }

        handler(&accounts[index])
    }
}

// MARK: - HistoricalAccount -

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
            mint: .usdf,
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
