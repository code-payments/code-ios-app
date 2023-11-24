//
//  TransactionBuilder.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

enum TransactionBuilder {}

extension TransactionBuilder {
    
    static func closeEmptyAccount(
        timelockDerivedAccounts: TimelockDerivedAccounts,
        maxDustAmount: Kin,
        nonce: PublicKey,
        recentBlockhash: Hash,
        legacy: Bool = false
    ) -> SolanaTransaction {
        SolanaTransaction(
            payer: .subsidizer,
            recentBlockhash: recentBlockhash,
            instructions: [
                
                SystemProgram.AdvanceNonce(
                    nonce: nonce,
                    authority: .subsidizer
                ).instruction(),
                
                TimelockProgram.BurnDustWithAuthority(
                    timelock: timelockDerivedAccounts.state.publicKey,
                    vault: timelockDerivedAccounts.vault.publicKey,
                    vaultOwner: timelockDerivedAccounts.owner,
                    timeAuthority: .timeAuthority,
                    mint: .kinMint,
                    payer: .subsidizer,
                    bump: timelockDerivedAccounts.state.bump,
                    maxAmount: maxDustAmount,
                    legacy: legacy
                ).instruction(),
                
                TimelockProgram.CloseAccounts(
                    timelock: timelockDerivedAccounts.state.publicKey,
                    vault: timelockDerivedAccounts.vault.publicKey,
                    closeAuthority: .subsidizer,
                    payer: .subsidizer,
                    bump: timelockDerivedAccounts.state.bump,
                    legacy: legacy
                ).instruction(),
            ]
        )
    }
    
    static func transfer(
        timelockDerivedAccounts: TimelockDerivedAccounts,
        destination: PublicKey,
        amount: Kin,
        nonce: PublicKey,
        recentBlockhash: Hash,
        kreIndex: Int
    ) -> SolanaTransaction {
        SolanaTransaction(
            payer: .subsidizer,
            recentBlockhash: recentBlockhash,
            instructions: [
                
                SystemProgram.AdvanceNonce(
                    nonce: nonce,
                    authority: .subsidizer
                ).instruction(),
 
                MemoProgram.Memo(
                    transferType: .p2p,
                    kreIndex: UInt16(kreIndex)
                ).instruction(),
                
                TimelockProgram.TransferWithAuthority(
                    timelock: timelockDerivedAccounts.state.publicKey,
                    vault: timelockDerivedAccounts.vault.publicKey,
                    vaultOwner: timelockDerivedAccounts.owner,
                    timeAuthority: .timeAuthority,
                    destination: destination,
                    payer: .subsidizer,
                    bump: timelockDerivedAccounts.state.bump,
                    kin: amount
                ).instruction(),
            ]
        )
    }
    
    static func closeDormantAccount(
        authority: PublicKey,
        timelockDerivedAccounts: TimelockDerivedAccounts,
        destination: PublicKey,
        nonce: PublicKey,
        recentBlockhash: Hash,
        kreIndex: Int,
        legacy: Bool = false
    ) -> SolanaTransaction {
        SolanaTransaction(
            payer: .subsidizer,
            recentBlockhash: recentBlockhash,
            instructions: [
                
                SystemProgram.AdvanceNonce(
                    nonce: nonce,
                    authority: .subsidizer
                ).instruction(),
 
                MemoProgram.Memo(
                    transferType: .p2p,
                    kreIndex: UInt16(kreIndex)
                ).instruction(),
                
                TimelockProgram.RevokeLockWithAuthority(
                    timelock: timelockDerivedAccounts.state.publicKey,
                    vault: timelockDerivedAccounts.vault.publicKey,
                    closeAuthority: .subsidizer,
                    payer: .subsidizer,
                    bump: timelockDerivedAccounts.state.bump,
                    legacy: legacy
                ).instruction(),
                
                TimelockProgram.DeactivateLock(
                    timelock: timelockDerivedAccounts.state.publicKey,
                    vaultOwner: authority,
                    payer: .subsidizer,
                    bump: timelockDerivedAccounts.state.bump,
                    legacy: legacy
                ).instruction(),
                
                TimelockProgram.Withdraw(
                    timelock: timelockDerivedAccounts.state.publicKey,
                    vault: timelockDerivedAccounts.vault.publicKey,
                    vaultOwner: authority,
                    destination: destination,
                    payer: .subsidizer,
                    bump: timelockDerivedAccounts.state.bump,
                    legacy: legacy
                ).instruction(),
                
                TimelockProgram.CloseAccounts(
                    timelock: timelockDerivedAccounts.state.publicKey,
                    vault: timelockDerivedAccounts.vault.publicKey,
                    closeAuthority: .subsidizer,
                    payer: .subsidizer,
                    bump: timelockDerivedAccounts.state.bump,
                    legacy: legacy
                ).instruction(),
            ]
        )
    }
}
