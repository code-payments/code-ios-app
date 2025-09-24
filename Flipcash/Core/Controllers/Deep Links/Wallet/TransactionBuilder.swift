//
//  TransactionBuilder.swift
//  Code
//
//  Created by Dima Bart on 2025-09-23.
//

import Foundation
import SolanaSwift

extension PublicKey {
    static let usdcMint     = try! PublicKey(string: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
    static let tokenProgram = try! PublicKey(string: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
}

enum TransactionBuilder {
    static func usdcTransfer(fromOwner: PublicKey, toOwner: PublicKey, quarks: UInt64, shouldCreateTokenAccount: Bool, recentBlockhash: String) throws -> Transaction {
        var instructions: [TransactionInstruction] = []
        
        // Derive associated token accounts
        let usdcATASource = try PublicKey.associatedTokenAddress(
            walletAddress: fromOwner,
            tokenMintAddress: .usdcMint,
            tokenProgramId: .tokenProgram
        )
        
        let usdcATADestination = try PublicKey.associatedTokenAddress(
            walletAddress: toOwner,
            tokenMintAddress: .usdcMint,
            tokenProgramId: .tokenProgram
        )
        
        // If needed, create the associated token account
        if shouldCreateTokenAccount {
            instructions.append(
                try AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                    mint: .usdcMint,
                    owner: toOwner,
                    payer: fromOwner,
                    tokenProgramId: PublicKey.tokenProgram
                )
            )
        }

        // Checked transfer
        instructions.append(
            TokenProgram.transferCheckedInstruction(
                source: usdcATASource,
                mint: .usdcMint,
                destination: usdcATADestination,
                owner: fromOwner,
                multiSigners: [],
                amount: quarks,
                decimals: 6
            )
        )

        return Transaction(
            instructions: instructions,
            recentBlockhash: recentBlockhash,
            feePayer: fromOwner
        )
    }
}
