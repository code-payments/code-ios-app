//
//  SwapInstructionBuilder+Swap.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/16/25.
//

extension SwapInstructionBuilder {
    
    private static func printInstructionDebugInfo(_ instructions: [Instruction]) {
        print("\n========== INSTRUCTION DEBUG INFO ==========")
        for (index, instruction) in instructions.enumerated() {
            let txInstruction = instruction
            print("\n--- Instruction \(index) ---")
            print("Program ID: \(txInstruction.program)")
            print("Keys (\(txInstruction.accounts.count)):")
            for (keyIndex, key) in txInstruction.accounts.enumerated() {
                print("  [\(keyIndex)] \(key.publicKey) - writable: \(key.isWritable), signer: \(key.isSigner)")
            }
            print("Data (\(txInstruction.data.count) bytes): \(txInstruction.data.hexEncodedString())")
        }
        print("\n===========================================\n")
    }
    
    // MARK: - Swap Tokens (Launchpad Currency Mint -> Launchpad Currency Mint)
    
    /// Builds instructions for swapping between two Launchpad currencies.
    ///
    /// - Parameters:
    ///   - serverParameters: Server-provided parameters including compute budget and memo
    ///   - nonce: The nonce account
    ///   - authority: The authority account that has ownership of the accounts.
    ///   - swapAuthority: The user authority account that will sign to authorize the swap.
    ///   - sourceMintMetadata: Metadata for the source mint
    ///   - targetMintMetadata: Metadata for the target mint
    ///   - coreMintMetadata: Metadata for the Core Mint (intermediary)
    ///   - amount: Amount to swap
    ///   - minOutput: Minimum output from buy/sell
    ///   - maxSlippage: Maximum slippage for swap
    /// - Returns: Array of instructions in the correct order
    public static func buildSwapInstructions(
        serverParameters: SwapResponseServerParameters,
        nonce: PublicKey,
        authority: PublicKey, // swapper
        swapAuthority: PublicKey, // temporaryHolder
        coreMintMetadata: MintMetadata,
        sourceMintMetadata: MintMetadata,
        targetMintMetadata: MintMetadata,
        amount: UInt64,
        minOutput: UInt64,
        maxSlippage: UInt64,
    ) -> [Instruction] {
        guard let sourceVM = sourceMintMetadata.vmMetadata else {
            fatalError("Source mint must have VM metadata")
        }
        guard let sourceLaunchpad = sourceMintMetadata.launchpadMetadata else {
            fatalError("Source mint must have launchpad metadata")
        }
        guard let targetVM = targetMintMetadata.vmMetadata else {
            fatalError("Target mint must have VM metadata")
        }
        guard let targetLaunchpad = targetMintMetadata.launchpadMetadata else {
            fatalError("Target mint must have launchpad metadata")
        }
        
        guard let sourceTimelockAccounts = sourceMintMetadata.timelockSwapAccounts(owner: authority) else {
            fatalError("Failed to derive PDA for \(coreMintMetadata.symbol)")
        }
        
        let serverParams = extractServerParameters(serverParameters)
        
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
        
        // 5. AssociatedTokenAccount::CreateIdempotent (open core mint temporary account)
        instructions.append(
            temporaryCoreMintAta.instruction()
        )
        
        // 6. AssociatedTokenAccount::CreateIdempotent (open source mint temporary account)
        instructions.append(
            temporarySourceMintAta.instruction()
        )
        
        // 7. VM::TransferForSwap (source_mint VM swap ATA -> source mint temporary account)
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
        
        // Fee target accounts are derived as ATAs from the launchpad authority for the mint
        // This matches the pattern used in Buy and Sell operations
        guard let sourceFeeTargetAccount = PublicKey.deriveAssociatedAccount(
            from: sourceVM.authority,
            mint: sourceMintMetadata.address
        )?.publicKey else {
            fatalError("Failed to derive fee target account for \(sourceMintMetadata.symbol)")
        }
        
        guard let destinationFeeTargetAccount = PublicKey.deriveAssociatedAccount(
            from: targetVM.authority,
            mint: targetMintMetadata.address
        )?.publicKey else {
            fatalError("Failed to derive fee target account for \(targetMintMetadata.symbol)")
        }
        
        // 8. CurrencyCreator::SellTokens (bounded sell transferring source mint into temporary account)
        instructions.append(
            CurrencyCreatorProgram.SellTokens(
                amount: amount,
                minOutput: minOutput,
                seller: swapAuthority,
                pool: sourceLaunchpad.liquidityPool,
                currency: sourceLaunchpad.currencyConfig,
                targetMint: sourceMintMetadata.address,
                baseMint: coreMintMetadata.address,
                vaultTarget: sourceLaunchpad.mintVault,
                vaultBase: sourceLaunchpad.coreMintVault,
                sellerTarget: temporarySourceMintAta.address,
                sellerBase: temporaryCoreMintAta.address,
                feeTarget: sourceFeeTargetAccount,
                feeBase: sourceLaunchpad.coreMintFees,
            ).instruction()
        )
        
        // 9. CurrencyCreator::BuyAndDepositIntoVm (unlimited buy depositing target mint tokens into the target mint VM)
        instructions.append(
            CurrencyCreatorProgram.BuyAndDepositIntoVm(
                amount: 0,
                minOutAmount: minOutput,
                vmMemoryIndex: UInt16(serverParams.memoryIndex),
                buyer: swapAuthority,
                pool: targetLaunchpad.liquidityPool,
                currency: targetLaunchpad.currencyConfig,
                targetMint: targetMintMetadata.address,
                baseMint: coreMintMetadata.address,
                vaultTarget: targetLaunchpad.mintVault,
                vaultBase: targetLaunchpad.coreMintVault,
                buyerBase: temporaryCoreMintAta.address,
                feeTarget: destinationFeeTargetAccount,
                feeBase: targetLaunchpad.coreMintFees,
                vmAuthority: targetVM.authority,
                vm: targetVM.vm,
                vmMemory: serverParams.memoryAccount,
                vmOmnibus: targetVM.omnibus,
                vtaOwner: authority,
            ).instruction()
        )
        
        // 10. Token::CloseAccount (closes Core Mint temporary account)
        instructions.append(
            TokenProgram.CloseAccount(
                account: temporaryCoreMintAta.address,
                destination: serverParams.payer,
                owner: swapAuthority
            ).instruction()
        )
        
        // 11. Token::CloseAccount (closes source mint temporary account)
        instructions.append(
            TokenProgram.CloseAccount(
                account: temporarySourceMintAta.address,
                destination: serverParams.payer,
                owner: swapAuthority
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
        
        printInstructionDebugInfo(instructions)
        
        return instructions
    }
}
