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
    
    /// Swap performs an on-chain swap. The high-level flow mirrors SubmitIntent
    /// closely. However, due to the time-sensitive nature and unreliability of
    /// swaps, they do not fit within the broader intent system. This results in
    /// a few key differences:
    ///  * Transactions are submitted on a best-effort basis outside of the Code
    ///    Sequencer within the RPC handler
    ///  * Balance changes are applied after the transaction has finalized
    ///  * Transactions use recent blockhashes over a nonce
    ///
    /// The transaction will have the following instruction format:
    ///   1. ComputeBudget::SetComputeUnitLimit
    ///   2. ComputeBudget::SetComputeUnitPrice
    ///   3. SwapValidator::PreSwap
    ///   4. Dynamic swap instruction
    ///   5. SwapValidator::PostSwap
    ///
    /// Note: Currently limited to swapping USDC to Kin.
    /// Note: Kin is deposited into the primary account.
    ///
    static func swap(from usdc: AccountCluster, to primary: PublicKey, parameters: SwapConfigParameters) -> SolanaTransaction {
        
        let payer = parameters.payer
        let destination = primary
        
        let stateAccount = PreSwapStateAccount(
            owner: .mock,
            source: usdc.vaultPublicKey,
            destination: destination,
            nonce: parameters.nonce
        )
        
        let remainingAccounts = parameters.swapAccounts.filter {
            ($0.isSigner || $0.isWritable) &&
            ($0.publicKey != usdc.authorityPublicKey &&
             $0.publicKey != usdc.vaultPublicKey && 
             $0.publicKey != destination)
        }
        
        return SolanaTransaction(
            payer: payer,
            recentBlockhash: parameters.blockhash,
            instructions: [
                ComputeBudgetProgram.SetComputeUnitLimit(
                    limit: parameters.computeUnitLimit
                ).instruction(),
                
                ComputeBudgetProgram.SetComputeUnitPrice(
                    microLamports: parameters.computeUnitPrice
                ).instruction(),
                
                SwapValidatorProgram.PreSwap(
                    preSwapState: stateAccount.state.publicKey,
                    user: usdc.authorityPublicKey,
                    source: usdc.vaultPublicKey,
                    destination: destination,
                    nonce: parameters.nonce,
                    payer: payer,
                    remainingAccounts: remainingAccounts
                ).instruction(),
                
                Instruction(
                    program: parameters.swapProgram,
                    accounts: parameters.swapAccounts,
                    data: parameters.swapData
                ),
                
                SwapValidatorProgram.PostSwap(
                    stateBump: stateAccount.state.bump,
                    maxToSend: parameters.maxToSend,
                    minToReceive: parameters.minToReceive,
                    preSwapState: stateAccount.state.publicKey,
                    source: usdc.vaultPublicKey,
                    destination: destination,
                    payer: payer
                ).instruction(),
            ]
        )
    }
    
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
        tipAccount: TipAccount? = nil,
        legacy: Bool = false
    ) -> SolanaTransaction {
        
        var instructions: [Instruction] = [
            SystemProgram.AdvanceNonce(
                nonce: nonce,
                authority: .subsidizer
            ).instruction(),
            
            MemoProgram.Memo(
                transferType: .p2p,
                kreIndex: UInt16(kreIndex)
            ).instruction(),
        ]
        
        if let tipAccount {
            instructions.append(
                MemoProgram.Memo(tipAccount: tipAccount).instruction()
            )
        }
        
        instructions.append(contentsOf: [
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
        ])
        
        return SolanaTransaction(
            payer: .subsidizer,
            recentBlockhash: recentBlockhash,
            instructions: instructions
        )
    }
}
