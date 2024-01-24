//
//  Organizer.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public class Organizer {
    
    public var slotsBalance: Kin {
        tray.slotsBalance
    }
    
    public var availableBalance: Kin {
        tray.availableBalance
    }
    
    public var availableDepositBalance: Kin {
        tray.availableDepositBalance
    }
    
    public var availableIncomingBalance: Kin {
        tray.availableIncomingBalance
    }
    
    public var ownerKeyPair: KeyPair {
        tray.owner.cluster.authority.keyPair
    }
    
    public var primaryVault: PublicKey {
        tray.owner.cluster.timelockAccounts.vault.publicKey
    }
    
    public var incomingVault: PublicKey {
        tray.incoming.cluster.timelockAccounts.vault.publicKey
    }
    
    public var isUnlocked: Bool {
        accountInfos.firstIndex { address, info in
            info.managementState != .locked
        } != nil
    }
    
    public var hasAccountInfos: Bool {
        !accountInfos.isEmpty
    }
    
    public let mnemonic: MnemonicPhrase
    
    public private(set) var tray: Tray
    
    private var accountInfos: [PublicKey: AccountInfo] = [:]

    // MARK: - Init -
    
    public init(mnemonic: MnemonicPhrase) {
        self.mnemonic = mnemonic
        self.tray = Tray(mnemonic: mnemonic)
    }
    
    public func set(tray: Tray) {
        self.tray = tray
    }
    
    // MARK: - Balances & Accounts -
    
    public func info(for accountType: AccountType) -> AccountInfo? {
        let account = tray.cluster(for: accountType).timelockAccounts.vault.publicKey
        return accountInfos[account]
    }
    
    public func setAccountInfo(_ accountInfos: [PublicKey: AccountInfo]) {
        self.accountInfos = accountInfos
        
        tray.createRelationships(for: accountInfos)
        
        propagateBalances()
    }
    
    private func propagateBalances() {
        var balances: [AccountType: Kin] = [:]
        
        for (vaultPublicKey, info) in accountInfos {
            let cluster = tray.cluster(for: info.accountType)
            
            if cluster.timelockAccounts.vault.publicKey == vaultPublicKey {
                balances[info.accountType] = info.balance
            } else {
                
                // The public key above doesn't match any accounts
                // that the Tray is aware of. If we're dealing with
                // temp I/O accounts then we likely just need to
                // update the index and try again
                switch info.accountType {
                case .incoming, .outgoing:
                    
                    // Update the index
                    tray.setIndex(info.index, for: info.accountType)
                    trace(.warning, components: "Updating \(info.accountType) index to: \(info.index)")
                    
                    // Ensure that the account matches
                    let cluster = tray.cluster(for: info.accountType)
                    
                    guard cluster.timelockAccounts.vault.publicKey == vaultPublicKey else {
                        trace(.failure, components: "Indexed account mismatch. This isn't suppose to happen.")
                        continue
                    }
                    
                    balances[info.accountType] = info.balance
                    
                case .primary, .bucket, .remoteSend, .relationship:
                    trace(.failure, components: "Non-indexed account mismatch. Account doesn't match server-provided account. Something is definitely wrong.")
                }
            }
        }
        
        setBalances(balances)
//        tray.prettyPrinted()
    }
    
    func setBalances(_ balances: [AccountType: Kin]) {
        tray.setBalances(balances)
    }
    
    func allAccounts() -> [(type: AccountType, cluster: AccountCluster)] {
        tray.allAccounts()
    }
    
    public func relationship(for domain: Domain) -> Relationship? {
        tray.relationships.relationship(for: domain)
    }
    
    public func relationshipsLargestFirst() -> [Relationship] {
        tray.relationships.relationships(largestFirst: true)
    }
    
    public func mapAccounts<T>(handler: (_ cluster: AccountCluster, _ info: AccountInfo) -> T) -> [T] {
        accountInfos.compactMap { _, info in
            let cluster = tray.cluster(for: info.accountType)
            return handler(cluster, info)
        }
    }
}

// MARK: - Mock -

extension Organizer {
    public static let mock = Organizer(mnemonic: .mock)
    
    public static let mock2: Organizer = {
        let organizer = Organizer(mnemonic: .mock)
        
        var balances: [Kin] = [
            6_000_000, // .bucket1m
            100_000,   // .bucket100k
            20_000,    // .bucket10k
            7_000,     // .bucket1k
            500,       // .bucket100
            30,        // .bucket10
            4,         // .bucket1
            0,         // Outgoing
            0,         // Incoming
            0,         // Primary
        ]
        
        var infos: [PublicKey: AccountInfo] = [:]
        
        organizer.allAccounts().forEach { type, cluster in
            infos[cluster.timelockAccounts.vault.publicKey] = AccountInfo(
                index: cluster.index,
                accountType: type,
                address: cluster.timelockAccounts.vault.publicKey,
                owner: nil,
                authority: nil,
                balanceSource: .blockchain,
                balance: balances.popLast()!,
                managementState: .locked,
                blockchainState: .exists,
                claimState: .unknown,
                mustRotate: false,
                originalKinAmount: nil,
                relationship: nil
            )
        }
        
        organizer.setAccountInfo(infos)
        
        return organizer
    }()
}
