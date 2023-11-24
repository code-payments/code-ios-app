//
//  AccountContainer.swift
//  Code
//
//  Created by Dima Bart on 2023-06-27.
//

import Foundation
import CodeServices

@MainActor
class AccountContainer: ObservableObject {
    
    @Published private(set) var accounts: [HistoricalAccount] = []
    
    private let client: Client
    private let accountManager: AccountManager
    
    // MARK: - Init -
    
    init(client: Client, accountManager: AccountManager) {
        self.client = client
        self.accountManager = accountManager
    }
    
    @discardableResult
    func fetchAccounts() async -> [HistoricalAccount] {
        let accounts = accountManager.fetchHistorical()
            .map {
                HistoricalAccount(details: $0)
            }.filter {
                // Don't show deleted accounts
                $0.details.deletionDate == nil
            }
        
        do {
            try await fetchBalances(for: accounts)
        } catch {}
        
        self.accounts = accounts
        return accounts
    }
    
    private func fetchBalances(for accounts: [HistoricalAccount]) async throws {
        let client = self.client
        await withThrowingTaskGroup(of: Void.self) { group in
            accounts.forEach { historicalAccount in
                group.addTask {
                    let owner = historicalAccount.details.account.owner
                    do {
                        let infos = try await client.fetchAccountInfos(owner: owner)
                        historicalAccount.setAccountInfo(infos)
                        
                    } catch ErrorFetchAccountInfos.notFound {
                        historicalAccount.isNotFound = true
                        
                    } catch ErrorFetchAccountInfos.migrationRequired {
                        historicalAccount.isMigrationRequired = true
                    }
                }
            }
        }
    }
}

class HistoricalAccount: Identifiable {
    
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
