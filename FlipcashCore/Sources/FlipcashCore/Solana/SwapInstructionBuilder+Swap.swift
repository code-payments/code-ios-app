//
//  SwapInstructionBuilder+Swap.swift
//  FlipcashCore
//

extension SwapInstructionBuilder {
    // MARK: - Swap Tokens (Launchpad Currency Mint -> Launchpad Currency Mint)

    /// Builds instructions for buying a launchpad currency paying with another
    /// launchpad currency: a bounded sell of the source into a temporary Core
    /// Mint account, then an unlimited buy of the target funded by it.
    ///
    /// - Parameters:
    ///   - serverParameters: Server-provided parameters including compute budget and memo
    ///   - nonce: The nonce account
    ///   - authority: The authority signing the transaction
    ///   - swapAuthority: The swap authority signing the transaction
    ///   - sourceMintMetadata: Metadata for the payment mint (sold)
    ///   - targetMintMetadata: Metadata for the mint being bought
    ///   - coreMintMetadata: Metadata for the Core Mint (intermediate)
    ///   - amount: Amount of the source mint to swap, in quarks
    /// - Returns: Array of instructions in the correct order
    public static func buildSwapInstructions(
        serverParameters: SwapResponseServerParameters,
        nonce: PublicKey,
        authority: PublicKey,
        swapAuthority: PublicKey, // temporaryHolder
        sourceMintMetadata: MintMetadata,
        targetMintMetadata: MintMetadata,
        coreMintMetadata: MintMetadata,
        amount: UInt64,
    ) throws -> [Instruction] {
        guard let sourceVM = sourceMintMetadata.vmMetadata else {
            throw SwapTransactionBuildError.missingMintMetadata(symbol: sourceMintMetadata.symbol)
        }
        guard let sourceLaunchpad = sourceMintMetadata.launchpadMetadata else {
            throw SwapTransactionBuildError.missingMintMetadata(symbol: sourceMintMetadata.symbol)
        }
        guard let targetVM = targetMintMetadata.vmMetadata else {
            throw SwapTransactionBuildError.missingMintMetadata(symbol: targetMintMetadata.symbol)
        }
        guard let targetLaunchpad = targetMintMetadata.launchpadMetadata else {
            throw SwapTransactionBuildError.missingMintMetadata(symbol: targetMintMetadata.symbol)
        }
        guard let sourceTimelockAccounts = sourceMintMetadata.timelockSwapAccounts(owner: authority) else {
            throw SwapTransactionBuildError.missingMintMetadata(symbol: sourceMintMetadata.symbol)
        }

        let serverParams = try extractServerParameters(serverParameters)

        guard let memoryIndex = UInt16(exactly: serverParams.memoryIndex) else {
            throw SwapTransactionBuildError.invalidServerParameter("memoryIndex")
        }

        let temporaryCoreMintAta = AssociatedTokenProgram.CreateIdempotent(
            subsidizer: serverParams.payer,
            owner: swapAuthority,
            mint: coreMintMetadata.address
        )

        let temporarySourceMintAta = AssociatedTokenProgram.CreateIdempotent(
            subsidizer: serverParams.payer,
            owner: swapAuthority,
            mint: sourceMintMetadata.address
        )

        var instructions: [Instruction] = []

        // 1. System::AdvanceNonce
        instructions.append(
            SystemProgram.AdvanceNonce(
                nonce: nonce,
                authority: serverParams.payer
            ).instruction()
        )

        // 2. ComputeBudget::SetComputeUnitLimit
        instructions.append(
            ComputeBudgetProgram.SetComputeUnitLimit(
                units: serverParams.computeUnitLimit
            ).instruction()
        )

        // 3. ComputeBudget::SetComputeUnitPrice
        instructions.append(
            ComputeBudgetProgram.SetComputeUnitPrice(
                microLamports: serverParams.computeUnitPrice
            ).instruction()
        )

        // 4. Memo::Memo
        instructions.append(
            MemoProgram.Memo(
                message: serverParams.memo
            ).instruction()
        )

        // 5. AssociatedTokenAccount::CreateIdempotent (open Core Mint temporary account)
        instructions.append(
            temporaryCoreMintAta.instruction()
        )

        // 6. AssociatedTokenAccount::CreateIdempotent (open source mint temporary account)
        instructions.append(
            temporarySourceMintAta.instruction()
        )

        // 7. VM::TransferForSwap (source mint VM swap ATA -> source mint temporary account)
        instructions.append(
            VMProgram.TransferForSwap(
                vmAuthority: sourceVM.authority,
                vm: sourceVM.vm,
                swapper: authority,
                swapPda: sourceTimelockAccounts.pda.publicKey,
                swapAta: sourceTimelockAccounts.ata.publicKey,
                destination: temporarySourceMintAta.address,
                amount: amount,
                bump: sourceTimelockAccounts.pda.bump,
            ).instruction()
        )

        // 8. CurrencyCreator::SellTokens (bounded sell transferring Core Mint into the temporary account)
        instructions.append(
            CurrencyCreatorProgram.SellTokens(
                seller: swapAuthority,
                pool: sourceLaunchpad.liquidityPool,
                targetMint: sourceMintMetadata.address,
                baseMint: coreMintMetadata.address,
                vaultTarget: sourceLaunchpad.mintVault,
                vaultBase: sourceLaunchpad.coreMintVault,
                sellerTarget: temporarySourceMintAta.address,
                sellerBase: temporaryCoreMintAta.address,
                inAmount: amount,
                minAmountOut: 0
            ).instruction()
        )

        // 9. CurrencyCreator::BuyAndDepositIntoVm (unlimited buy depositing target tokens into the target VM)
        instructions.append(
            CurrencyCreatorProgram.BuyAndDepositIntoVm(
                amount: 0,
                minOutAmount: 0,
                vmMemoryIndex: memoryIndex,
                buyer: swapAuthority,
                pool: targetLaunchpad.liquidityPool,
                targetMint: targetMintMetadata.address,
                baseMint: coreMintMetadata.address,
                vaultTarget: targetLaunchpad.mintVault,
                vaultBase: targetLaunchpad.coreMintVault,
                buyerBase: temporaryCoreMintAta.address,
                vmAuthority: targetVM.authority,
                vm: targetVM.vm,
                vmMemory: serverParams.memoryAccount,
                vmOmnibus: targetVM.omnibus,
                vtaOwner: authority
            ).instruction()
        )

        // 10. Token::CloseAccount (closes Core Mint temporary account)
        instructions.append(
            TokenProgram.CloseAccount(
                account: temporaryCoreMintAta.address,
                destination: serverParams.payer,
                owner: swapAuthority,
            ).instruction()
        )

        // 11. Token::CloseAccount (closes source mint temporary account)
        instructions.append(
            TokenProgram.CloseAccount(
                account: temporarySourceMintAta.address,
                destination: serverParams.payer,
                owner: swapAuthority,
            ).instruction()
        )

        // 12. VM::CloseSwapAccountIfEmpty (closes source mint VM swap ATA if empty)
        instructions.append(
            VMProgram.CloseSwapAccountIfEmpty(
                vmAuthority: sourceVM.authority,
                vm: sourceVM.vm,
                swapper: authority,
                swapPda: sourceTimelockAccounts.pda.publicKey,
                swapAta: sourceTimelockAccounts.ata.publicKey,
                destination: serverParams.payer,
                bump: sourceTimelockAccounts.pda.bump,
            ).instruction()
        )

        return instructions
    }
}
