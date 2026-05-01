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
        case .newCurrency:
            // New-currency launches go through TransactionBuilder.swapNewCurrency,
            // which consumes the ReserveNewCurrency params directly.
            fatalError("TransactionBuilder.swap cannot be used with a new-currency launch")
        case .stablecoin:
            // Stablecoin (USDF → USDC) withdraws go through swapUsdfToUsdc.
            fatalError("TransactionBuilder.swap cannot be used with a stablecoin withdraw")
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

        case .withdraw:
            // Stablecoin (USDF → USDC) withdraws go through swapUsdfToUsdc.
            fatalError("TransactionBuilder.swap cannot build a stablecoin withdraw transaction")
        }
        
        return SolanaTransaction.init(
            payer: payer,
            recentBlockhash: blockhash,
            addressLookupTables: alts,
            instructions: instructions
        )
    }

    /// Builds the USDF → USDC withdraw transaction via the Coinbase Stable Swapper.
    ///
    /// - Parameters:
    ///   - serverParameters: Stablecoin server params (payer, nonce, blockhash, compute budget, etc.)
    ///   - authority: Flipcash user's public key — owner of the VM swap accounts.
    ///   - swapAuthority: One-time ephemeral keypair public key that signs the Coinbase swap.
    ///   - destinationOwner: Owner of the account where USDC tokens land.
    ///   - amount: USDF quarks being swapped.
    ///   - feeAmount: USDF quarks taken as the VM transfer fee.
    static func swapUsdfToUsdc(
        serverParameters: SwapResponseServerParameters.CoinbaseStableSwapServerParameters,
        authority: PublicKey,
        swapAuthority: PublicKey,
        destinationOwner: PublicKey,
        amount: UInt64,
        feeAmount: UInt64
    ) -> SolanaTransaction {
        let instructions = SwapInstructionBuilder.buildUsdfToUsdcSwapInstructions(
            serverParameters: serverParameters,
            authority: authority,
            swapAuthority: swapAuthority,
            destinationOwner: destinationOwner,
            fromMintMetadata: .usdf,
            toMintMetadata: .usdc,
            amount: amount,
            feeAmount: feeAmount,
            minOutput: amount
        )

        return SolanaTransaction(
            payer: serverParameters.payer,
            recentBlockhash: serverParameters.blockhash,
            addressLookupTables: serverParameters.alts,
            instructions: instructions
        )
    }

    /// Builds the atomic launch-and-first-buy transaction for a new
    /// launchpad currency. Only the creator (owner == swap authority ==
    /// serverParams.authority) can execute this path.
    static func swapNewCurrency(
        responseParams: SwapResponseServerParameters.ReserveNewCurrency,
        authority: PublicKey,
        swapAmount: UInt64,
        feeAmount: UInt64
    ) -> SolanaTransaction {
        let instructions = SwapInstructionBuilder.newCurrencyLaunch(
            serverParams: responseParams,
            authority: authority,
            swapAmount: swapAmount,
            feeAmount: feeAmount
        )

        return SolanaTransaction(
            payer: responseParams.payer,
            recentBlockhash: responseParams.blockhash,
            addressLookupTables: responseParams.alts,
            instructions: instructions
        )
    }
}
