//
//  SwapInstructionBuilder+Sell.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/16/25.
//

extension SwapInstructionBuilder {
    // MARK: - Sell Tokens (Launchpad Currency Mint -> Core Mint)
    
    /// Builds instructions for selling tokens, converting Launchpad Currency to Core Mint.
    ///
    /// - Parameters:
    ///   - serverParameters: Server-provided parameters including compute budget and memo
    ///   - nonce: The nonce account
    ///   - authority: The authority signing the transaction
    ///   - sourceMintMetadata: Metadata for the source mint (launchpad currency)
    ///   - coreMintMetadata: Metadata for the Core Mint (destination)
    ///   - fromMintTemporary: Temporary account for the source mint
    ///   - fromMintOwner: Owner of the from mint account
    ///   - vmSwapAccount: VM swap ATA for the source mint
    ///   - amount: Amount to sell
    ///   - minOutput: Minimum output required
    ///   - additionalAccounts: Additional accounts required by the currency creator program
    /// - Returns: Array of instructions in the correct order
    public static func buildSellInstructions(
        serverParameters: SwapResponseServerParameters,
        nonce: PublicKey,
        authority: PublicKey,
        swapAuthority: PublicKey, // temporaryHolder
        sourceMintMetadata: MintMetadata,
        coreMintMetadata: MintMetadata,
        amount: UInt64,
        minOutput: UInt64,
        maxSlippage: UInt64,
    ) -> [Instruction] {
        guard let coreVM = coreMintMetadata.vmMetadata else {
            fatalError("Source mint must have VM metadata")
        }
        guard let sourceVM = sourceMintMetadata.vmMetadata else {
            fatalError("Source mint must have VM metadata")
        }
        guard let sourceLaunchpad = sourceMintMetadata.launchpadMetadata else {
            fatalError("Source mint must have launchpad metadata")
        }
        
        guard let sourceTimelockAccounts = sourceMintMetadata.timelockSwapAccounts(owner: authority) else {
            fatalError("Failed to derive PDA for \(sourceMintMetadata.symbol)")
        }
        
        let serverParams = extractServerParameters(serverParameters)
        
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
        
        // 5. AssociatedTokenAccount::CreateIdempotent (open source mint temporary account)
        instructions.append(
            temporarySourceMintAta.instruction()
        )
        
        // 6. VM::TransferForSwap (source Mint VM swap ATA -> source Mint temporary account)
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
        
        guard let feeTargetAccount = PublicKey.deriveAssociatedAccount(
            from: sourceVM.authority,
            mint: sourceMintMetadata.address
        )?.publicKey else {
            fatalError("Failed to derive fee base account for \(sourceMintMetadata.symbol)")
        }
        
        // 7. CurrencyCreator::SellAndDepositIntoVm
        instructions.append(
            CurrencyCreatorProgram.SellAndDepositIntoVm(
                amount: amount,
                minOutAmount: minOutput,
                vmMemoryIndex: UInt16(serverParams.memoryIndex),
                seller: swapAuthority,
                pool: sourceLaunchpad.liquidityPool,
                currency: sourceLaunchpad.currencyConfig,
                targetMint: sourceMintMetadata.address,
                baseMint: coreMintMetadata.address,
                vaultTarget: sourceLaunchpad.mintVault,
                vaultBase: sourceLaunchpad.coreMintVault,
                sellerTarget: temporarySourceMintAta.address,
                feeTarget: feeTargetAccount,
                feeBase: sourceLaunchpad.coreMintFees,
                vmAuthority: coreVM.authority,
                vm: coreVM.vm,
                vmMemory: serverParams.memoryAccount,
                vmOmnibus: coreVM.omnibus,
                vtaOwner: authority,
            ).instruction()
        )
        
        // 8. Token::CloseAccount (closes source Mint temporary account)
        instructions.append(
            TokenProgram.CloseAccount(
                account: temporarySourceMintAta.address,
                destination: serverParams.payer,
                owner: swapAuthority,
            ).instruction()
        )
        
        // 9. VM::CloseSwapAccountIfEmpty (closes source Mint VM swap ATA if empty)
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
