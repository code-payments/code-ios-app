//
//  TransactionBuilder.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/3/25.
//

enum TransactionBuilder {}

// MARK: - Helper Methods

extension TransactionBuilder {
    
    /// Derives the temporary token account for a given owner and mint
    private static func deriveTemporaryAccount(owner: PublicKey, mint: PublicKey) -> PublicKey {
        guard let pda = PublicKey.deriveAssociatedAccount(from: owner, mint: mint) else {
            fatalError("Failed to derive temporary account for owner: \(owner), mint: \(mint)")
        }
        return pda.publicKey
    }
    
    /// Derives the VM swap account for a given owner and mint
    private static func deriveVMSwapAccount(owner: PublicKey, mint: PublicKey, vmMetadata: VMMetadata) -> PublicKey {
        // The VM swap account is typically the associated token account of the VM for the given mint
        guard let pda = PublicKey.deriveAssociatedAccount(from: vmMetadata.vm, mint: mint) else {
            fatalError("Failed to derive VM swap account for VM: \(vmMetadata.vm), mint: \(mint)")
        }
        return pda.publicKey
    }
}

// MARK: - Swap Transaction Builder

extension TransactionBuilder {
    static func swap(
        responseParams: SwapResponseServerParameters,
        metadata: VerifiedSwapMetadata,
        authority: PublicKey,
        swapAuthority: PublicKey,
        direction: SwapDirection,
        amount: UInt64,
        minOutput: UInt64 = 0,
        slippageBasisPoints: UInt64 = 0
    ) -> SolanaTransaction {
        // Extract server-provided parameters
        let (payer, blockhash, alts): (PublicKey, Hash?, [AddressLookupTable]) = switch responseParams.kind {
        case .stateful(let params):
            (params.payer, metadata.serverParameters.blockhash, params.alts)
        case .stateless(let params):
            (params.payer, params.recentBlockhash, params.alts)
        }
        
        let coreMint = MintMetadata.usdf
        
        let instructions = switch direction {
        case .buy(let targetMint):
            SwapInstructionBuilder.buildBuyInstructions(
                serverParameters: responseParams,
                nonce: metadata.serverParameters.nonce,
                authority: authority,
                swapAuthority: swapAuthority,
                coreMintMetadata: coreMint,
                targetMintMetadata: targetMint,
                amount: amount,
                minOutput: minOutput,
                maxSlippage: slippageBasisPoints,
            )
            
        case .sell(let sourceMint):
            SwapInstructionBuilder.buildSellInstructions(
                serverParameters: responseParams,
                nonce: metadata.serverParameters.nonce,
                authority: authority,
                swapAuthority: swapAuthority,
                sourceMintMetadata: sourceMint,
                coreMintMetadata: coreMint,
                amount: amount,
                minOutput: minOutput,
                maxSlippage: slippageBasisPoints,
            )
        }
        
        return SolanaTransaction.init(
            payer: payer,
            recentBlockhash: blockhash,
            addressLookupTables: alts,
            instructions: instructions
        )
    }
}
