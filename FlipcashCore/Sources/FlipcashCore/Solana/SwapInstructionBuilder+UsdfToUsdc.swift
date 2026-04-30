//
//  SwapInstructionBuilder+UsdfToUsdc.swift
//  FlipcashCore
//

import Foundation

extension SwapInstructionBuilder {

    /// Builds the 9-instruction sequence for the USDF → USDC withdraw via Coinbase Stable Swapper.
    ///
    /// - Parameters:
    ///   - serverParameters: Stablecoin-specific server params (nonce, blockhash, compute budget,
    ///     memo, payer, feeDestination, poolFeeRecipient).
    ///   - authority: Flipcash user's public key — owner of the VM swap accounts.
    ///   - swapAuthority: One-time ephemeral keypair public key that signs the Coinbase swap instruction.
    ///   - destinationOwner: Owner of the account where USDC tokens land after the swap.
    ///   - fromMintMetadata: USDF mint metadata (must have `vmMetadata`).
    ///   - toMintMetadata: USDC mint metadata.
    ///   - amount: USDF quarks to transfer out of the VM swap PDA.
    ///   - feeAmount: USDF quarks paid as the VM transfer fee.
    ///   - minOutput: Minimum USDC quarks acceptable. The server reconstructs the
    ///     on-chain transaction with `minAmountOut == swap_amount` for the 1:1
    ///     stable pair, so production callers pass `amount`.
    public static func buildUsdfToUsdcSwapInstructions(
        serverParameters: SwapResponseServerParameters.CoinbaseStableSwapServerParameters,
        authority: PublicKey,
        swapAuthority: PublicKey,
        destinationOwner: PublicKey,
        fromMintMetadata: MintMetadata,
        toMintMetadata: MintMetadata,
        amount: UInt64,
        feeAmount: UInt64,
        minOutput: UInt64
    ) -> [Instruction] {
        guard let fromVm = fromMintMetadata.vmMetadata else {
            fatalError("Source mint missing VM metadata: \(fromMintMetadata.symbol)")
        }

        guard let fromTimelockAccounts = fromMintMetadata.timelockSwapAccounts(owner: authority) else {
            fatalError("Failed to derive timelock swap accounts for source mint: \(fromMintMetadata.symbol)")
        }

        // Coinbase Stable Swapper PDAs
        guard let pool = CoinbaseStableSwapperProgram.derivePoolAddress() else {
            fatalError("Failed to derive Coinbase pool address")
        }
        guard let inVault = CoinbaseStableSwapperProgram.deriveTokenVaultAddress(
            pool: pool.publicKey,
            mint: fromMintMetadata.address
        ) else {
            fatalError("Failed to derive Coinbase in-vault address")
        }
        guard let outVault = CoinbaseStableSwapperProgram.deriveTokenVaultAddress(
            pool: pool.publicKey,
            mint: toMintMetadata.address
        ) else {
            fatalError("Failed to derive Coinbase out-vault address")
        }
        guard let inVaultTokenAccount = CoinbaseStableSwapperProgram.deriveVaultTokenAccountAddress(
            vault: inVault.publicKey
        ) else {
            fatalError("Failed to derive Coinbase in-vault token account")
        }
        guard let outVaultTokenAccount = CoinbaseStableSwapperProgram.deriveVaultTokenAccountAddress(
            vault: outVault.publicKey
        ) else {
            fatalError("Failed to derive Coinbase out-vault token account")
        }
        guard let whitelist = CoinbaseStableSwapperProgram.deriveWhitelistAddress() else {
            fatalError("Failed to derive Coinbase whitelist address")
        }

        // Fee recipient's from-mint ATA (USDF ATA owned by poolFeeRecipient)
        guard let feeRecipientFromMintAta = PublicKey.deriveAssociatedAccount(
            from: serverParameters.poolFeeRecipient,
            mint: fromMintMetadata.address
        ) else {
            fatalError("Failed to derive fee recipient from-mint ATA")
        }

        // ATA create instructions (also carry the derived .address for later use)
        let createSwapAuthorityFromMintAta = AssociatedTokenProgram.CreateIdempotent(
            subsidizer: serverParameters.payer,
            owner: swapAuthority,
            mint: fromMintMetadata.address
        )

        let createDestinationOwnerToMintAta = AssociatedTokenProgram.CreateIdempotent(
            subsidizer: serverParameters.payer,
            owner: destinationOwner,
            mint: toMintMetadata.address
        )

        var instructions: [Instruction] = []

        // 1. System::AdvanceNonce
        instructions.append(
            SystemProgram.AdvanceNonce(
                nonce: serverParameters.nonce,
                authority: serverParameters.payer
            ).instruction()
        )

        // 2. ComputeBudget::SetComputeUnitLimit
        instructions.append(
            ComputeBudgetProgram.SetComputeUnitLimit(
                units: serverParameters.computeUnitLimit
            ).instruction()
        )

        // 3. ComputeBudget::SetComputeUnitPrice
        instructions.append(
            ComputeBudgetProgram.SetComputeUnitPrice(
                microLamports: serverParameters.computeUnitPrice
            ).instruction()
        )

        // 4. Memo::Memo
        instructions.append(
            MemoProgram.Memo(
                message: serverParameters.memoValue
            ).instruction()
        )

        // 5. AssociatedToken::CreateIdempotent (swap-authority's from-mint ATA)
        instructions.append(createSwapAuthorityFromMintAta.instruction())

        // 6. AssociatedToken::CreateIdempotent (destination-owner's to-mint ATA)
        instructions.append(createDestinationOwnerToMintAta.instruction())

        // 7. VM::TransferForSwapWithFee
        //    Moves USDF from the user's VM swap PDA ATA → swap-authority's from-mint ATA,
        //    with a fee portion going to serverParameters.feeDestination.
        instructions.append(
            VMProgram.TransferForSwapWithFee(
                vmAuthority: fromVm.authority,
                vm: fromVm.vm,
                swapper: authority,
                swapPda: fromTimelockAccounts.pda.publicKey,
                swapAta: fromTimelockAccounts.ata.publicKey,
                swapDestination: createSwapAuthorityFromMintAta.address,
                feeDestination: serverParameters.feeDestination,
                swapAmount: amount,
                feeAmount: feeAmount,
                bump: fromTimelockAccounts.pda.bump
            ).instruction()
        )

        // 8. CoinbaseStableSwapper::Swap
        //    Swaps USDF in the swap-authority's ATA for USDC into the destination-owner's ATA.
        instructions.append(
            CoinbaseStableSwapperProgram.Swap(
                pool: pool.publicKey,
                inVault: inVault.publicKey,
                outVault: outVault.publicKey,
                inVaultTokenAccount: inVaultTokenAccount.publicKey,
                outVaultTokenAccount: outVaultTokenAccount.publicKey,
                userFromTokenAccount: createSwapAuthorityFromMintAta.address,
                toTokenAccount: createDestinationOwnerToMintAta.address,
                feeRecipientTokenAccount: feeRecipientFromMintAta.publicKey,
                feeRecipient: serverParameters.poolFeeRecipient,
                fromMint: fromMintMetadata.address,
                toMint: toMintMetadata.address,
                user: swapAuthority,
                whitelist: whitelist.publicKey,
                amountIn: amount,
                minAmountOut: minOutput
            ).instruction()
        )

        // 9. Token::CloseAccount (reclaim the swap-authority's ephemeral from-mint ATA)
        instructions.append(
            TokenProgram.CloseAccount(
                account: createSwapAuthorityFromMintAta.address,
                destination: serverParameters.payer,
                owner: swapAuthority
            ).instruction()
        )

        return instructions
    }
}
