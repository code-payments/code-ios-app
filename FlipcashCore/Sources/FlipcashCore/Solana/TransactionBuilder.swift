//
//  TransactionBuilder.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/3/25.
//

enum TransactionBuilder {}

// MARK: - Swap Transaction Builder

extension TransactionBuilder {
    static func swap(
        responseParams: SwapResponseServerParameters,
        metadata: VerifiedSwapMetadata,
        authority: PublicKey,
        swapAuthority: PublicKey,
        direction: SwapDirection,
        amount: UInt64,
        minOutput: UInt64 = 0
    ) throws -> SolanaTransaction {
        // Extract server-provided parameters
        let (payer, blockhash, alts): (PublicKey, Hash, [AddressLookupTable]) = switch responseParams.kind {
        case .stateful(let params):
            (params.payer, metadata.serverParameters.blockhash, params.alts)
        case .newCurrency:
            // New-currency launches go through TransactionBuilder.swapNewCurrency,
            // which consumes the ReserveNewCurrency params directly.
            throw SwapTransactionBuildError.unsupportedServerParameters
        case .stablecoin:
            // Stablecoin (USDF → USDC) withdraws go through swapUsdfToUsdc.
            throw SwapTransactionBuildError.unsupportedServerParameters
        }

        let coreMint = MintMetadata.usdf

        let instructions = switch direction {
        case .buy(let targetMint):
            try SwapInstructionBuilder.buildBuyInstructions(
                serverParameters: responseParams,
                nonce: metadata.serverParameters.nonce,
                authority: authority,
                swapAuthority: swapAuthority,
                coreMintMetadata: coreMint,
                targetMintMetadata: targetMint,
                amount: amount,
                minOutput: minOutput,
            )

        case .sell(let sourceMint):
            try SwapInstructionBuilder.buildSellInstructions(
                serverParameters: responseParams,
                nonce: metadata.serverParameters.nonce,
                authority: authority,
                swapAuthority: swapAuthority,
                sourceMintMetadata: sourceMint,
                coreMintMetadata: coreMint,
                amount: amount,
                minOutput: minOutput,
            )

        case .swap(let sourceMint, let targetMint):
            try SwapInstructionBuilder.buildSwapInstructions(
                serverParameters: responseParams,
                nonce: metadata.serverParameters.nonce,
                authority: authority,
                swapAuthority: swapAuthority,
                sourceMintMetadata: sourceMint,
                targetMintMetadata: targetMint,
                coreMintMetadata: coreMint,
                amount: amount,
            )

        case .withdraw:
            // Stablecoin (USDF → USDC) withdraws go through swapUsdfToUsdc.
            throw SwapTransactionBuildError.unsupportedServerParameters
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

    /// Builds the `StatelessSwap` transaction (USDC → USDF auto-conversion on
    /// app open). Uses a regular recent blockhash rather than a durable nonce,
    /// and the owner is the sole client-side signer.
    static func statelessSwap(
        serverParameters: StatelessSwapServerParameters,
        owner: PublicKey,
        fromMint: MintMetadata,
        toMint: MintMetadata,
        amount: UInt64
    ) -> SolanaTransaction {
        let instructions = SwapInstructionBuilder.buildStatelessSwapInstructions(
            serverParameters: serverParameters,
            owner: owner,
            fromMint: fromMint,
            toMint: toMint,
            amount: amount
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
    ) throws -> SolanaTransaction {
        let instructions = try SwapInstructionBuilder.newCurrencyLaunch(
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
