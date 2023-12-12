//
//  AccountSelectionScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-03-04.
//

import SwiftUI
import CodeUI
import CodeServices

struct AccountSelectionScreen: View {
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var exchange: Exchange
    
    @Binding public var isPresented: Bool
    
    private let sessionAuthenticator: SessionAuthenticator
    private let accountManager: AccountManager
    
    @State private var accounts: [HistoricalAccount2] = []
//    AccountDescription.mockMany().map {
//        HistoricalAccount2(
//            balance: KinAmount(kin: 4_785_290, rate: Rate(fx: 0.00003925, currency: .usd)),
//            details: $0,
//            isTimelock: false
//        )
//    }
    
    private let action: (AccountDescription) -> Void
    
    private var currentRate: Rate {
        exchange.localRate
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
                VStack {
                    ScrollBox(color: .backgroundMain) {
                        LazyTable(contentPadding: .scrollBox) {
                            ForEach(accounts) { account in
                                Button {
                                    action(account.details)
                                } label: {
                                    HStack(alignment: .center, spacing: 15) {
                                        CheckView(active: isSelected(for: account.details))
                                        VStack(alignment: .leading, spacing: 4) {
                                            
                                            HStack(alignment: .bottom, spacing: 10) {
                                                Text("\(account.formattedKin()) \(Localized.Core.kin)")
                                                if account.isNotFound {
                                                    Badge(decoration: .circle(.textError), text: "Not Found")
                                                } else if account.organizer.isUnlocked {
                                                    Badge(decoration: .circle(.textError), text: "Unlocked")
                                                } else if account.isMigrationRequired {
                                                    Badge(decoration: .circle(.textWarning), text: "Legacy")
                                                }
                                                Spacer()
                                                Text(account.formattedFiat(rate: currentRate))
                                            }
                                            .font(.appTextMedium)
                                            .foregroundColor(.textMain)
                                            .padding(.bottom, 5)
                                            
                                            Group {
                                                Text("Created \(DateFormatter.relative.string(from: account.details.creationDate))")
                                                Text("On \(account.details.deviceName)")
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
                                .padding([.top, .bottom], 20)
                                .padding(.trailing, 20)
                                .vSeparator(color: .rowSeparator)
                                .padding(.leading, 20)
                                .contextMenu(ContextMenu {
                                    Button {
                                        copySecretPhrase(description: account.details)
                                    } label: {
                                        Label("Copy Secret Phrase", systemImage: SystemSymbol.doc.rawValue)
                                    }

                                    Button {
                                        copyOwnerAddress(description: account.details)
                                    } label: {
                                        Label("Copy Owner Address", systemImage: SystemSymbol.doc.rawValue)
                                    }

                                    Button {
                                        deleteAccount(description: account.details)
                                    } label: {
                                        Label("Delete Account", systemImage: "trash")
                                    }
                                })
                            }
                        }
                    }
                }
            }
            .navigationBarTitle(Text(Localized.Title.selectAccount), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
        }
        .onAppear {
            Analytics.open(screen: .accountSelection)
            ErrorReporting.breadcrumb(.accountSelectionScreen)
            fetchAccounts()
            fetchBalances()
        }
    }
    
    private func isSelected(for description: AccountDescription) -> Bool {
        switch sessionAuthenticator.state {
        case .loggedIn(let container):
            return container.session.organizer.ownerKeyPair.publicKey == description.account.ownerPublicKey
            
        case .loggedOut, .migrating, .pending:
            return false
        }
    }
    
    // MARK: - Actions -
    
    private func copySecretPhrase(description: AccountDescription) {
        UIPasteboard.general.string = description.account.mnemonic.words.joined(separator: " ")
    }
    
    private func copyOwnerAddress(description: AccountDescription) {
        UIPasteboard.general.string = description.account.ownerPublicKey.base58
    }
    
//    private func copyTokenAddress(description: AccountDescription) {
//        UIPasteboard.general.string = description.account.tokenPublicKey.base58
//    }
    
    private func deleteAccount(description: AccountDescription) {
        accountManager.delete(ownerPublicKey: description.account.owner.publicKey)
        
        let accountIndex = accounts.firstIndex { $0.details.account.ownerPublicKey == description.account.ownerPublicKey }
        if let accountIndex = accountIndex {
            accounts.remove(at: accountIndex)
        }
    }
    
    private func fetchAccounts() {
        accounts = accountManager.fetchHistorical()
        .map {
            HistoricalAccount2(details: $0)
        }.filter {
            // Don't show deleted accounts
            $0.details.deletionDate == nil
        }
    }
    
    private func fetchBalances() {
        Task {
            await withThrowingTaskGroup(of: Void.self) { group in
                accounts.forEach { historicalAccount in
                    group.addTask {
                        let owner = historicalAccount.details.account.owner
                        do {
                            let infos = try await client.fetchAccountInfos(owner: owner)
                            await update(owner: owner.publicKey) {
                                $0.setAccountInfo(infos)
                            }
                            
                        } catch ErrorFetchAccountInfos.notFound {
                            await update(owner: owner.publicKey) {
                                $0.isNotFound = true
                            }
                            
                        } catch ErrorFetchAccountInfos.migrationRequired {
                            await update(owner: owner.publicKey) {
                                $0.isMigrationRequired = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func update(owner: PublicKey, handler: (inout HistoricalAccount2) -> Void) {
        let index = accounts.firstIndex { $0.details.account.ownerPublicKey == owner }
        
        guard let index = index else {
            return
        }
        
        handler(&accounts[index])
    }
}

// MARK: - HistoricalAccount -

private class HistoricalAccount2: Identifiable {
    
    var id: String {
        details.account.ownerPublicKey.base58
    }
    
    let details: AccountDescription
    
    private(set) var organizer: Organizer
    
    var isNotFound: Bool = false
    var isMigrationRequired: Bool = false

    init(details: AccountDescription) {
        self.details = details
        self.organizer = Organizer(mnemonic: details.account.mnemonic)
    }
    
    func setAccountInfo(_ accountInfos: [PublicKey: AccountInfo]) {
        organizer.setAccountInfo(accountInfos)
    }
    
    func formattedKin() -> String {
        organizer.availableBalance.formattedTruncatedKin()
    }
    
    func formattedFiat(rate: Rate) -> String {
        organizer.availableBalance.formattedFiat(rate: rate, showOfKin: false)
    }
}

// MARK: - Previews -

struct AccountSelectionScreen_Previews: PreviewProvider {
    static var previews: some View {
        AccountSelectionScreen(
            isPresented: .constant(true),
            sessionAuthenticator: .mock,
            action: { _ in }
        )
        .environmentObjectsForSession()
    }
}
