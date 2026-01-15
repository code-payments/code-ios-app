//
//  TransactionBuilder.swift
//  Code
//
//  Created by Dima Bart on 2025-09-23.
//

import Foundation
import SolanaSwift

extension PublicKey {
    static let usdfMint     = try! PublicKey(string: "5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ")
    static let tokenProgram = try! PublicKey(string: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
}

enum TransactionBuilder {
    static func usdfTransfer(fromOwner: PublicKey, toOwner: PublicKey, quarks: UInt64, shouldCreateTokenAccount: Bool, recentBlockhash: String) throws -> Transaction {
        var instructions: [TransactionInstruction] = []
        
        // Derive associated token accounts
        let usdfATASource = try PublicKey.associatedTokenAddress(
            walletAddress: fromOwner,
            tokenMintAddress: .usdfMint,
            tokenProgramId: .tokenProgram
        )
        
        let usdfATADestination = try PublicKey.associatedTokenAddress(
            walletAddress: toOwner,
            tokenMintAddress: .usdfMint,
            tokenProgramId: .tokenProgram
        )
        
        // If needed, create the associated token account
        if shouldCreateTokenAccount {
            instructions.append(
                try AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                    mint: .usdfMint,
                    owner: toOwner,
                    payer: fromOwner,
                    tokenProgramId: PublicKey.tokenProgram
                )
            )
        }

        // Checked transfer
        instructions.append(
            TokenProgram.transferCheckedInstruction(
                source: usdfATASource,
                mint: .usdfMint,
                destination: usdfATADestination,
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
