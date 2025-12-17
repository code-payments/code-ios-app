//
//  SwapInstructionBuilder+Buy.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/16/25.
//

extension SwapInstructionBuilder {
    // MARK: - Buy Tokens (Core Mint -> Launchpad Currency Mint)
    
    /// Builds instructions for buying tokens using Core Mint to purchase Launchpad Currency.
    ///
    /// - Parameters:
    ///   - serverParameters: Server-provided parameters including compute budget and memo
    ///   - nonce: The nonce account
    ///   - authority: The authority signing the transaction
    ///   - swapAuthority: The swap authority signing the transaction
    ///   - coreMintMetadata: Metadata for the Core Mint (source)
    ///   - targetMintMetadata: Metadata for the target mint (destination)
    ///   - coreMintTemporary: Temporary account for Core Mint
    ///   - coreMintOwner: Owner of the Core Mint account
    ///   - amount: Amount to buy
    ///   - minOutput: Minimum output required
    ///   - maxSlippage: Maximum slippage tolerance
    /// - Returns: Array of instructions in the correct order
    public static func buildBuyInstructions(
        serverParameters: SwapResponseServerParameters,
        nonce: PublicKey,
        authority: PublicKey,
        swapAuthority: PublicKey, // temporaryHolder
        coreMintMetadata: MintMetadata,
        targetMintMetadata: MintMetadata,
        amount: UInt64,
        minOutput: UInt64,
        maxSlippage: UInt64,
    ) -> [Instruction] {
        guard let coreVM = coreMintMetadata.vmMetadata else {
            fatalError("Core mint must have VM metadata")
        }
        guard let targetVM = targetMintMetadata.vmMetadata else {
            fatalError("Target mint must have VM metadata")
        }
        
        guard let targetLaunchpad = targetMintMetadata.launchpadMetadata else {
            fatalError("Target mint must have launchpad metadata")
        }
        
        let serverParams = extractServerParameters(serverParameters)
        
        guard let coreTimelockAccounts = coreMintMetadata.timelockSwapAccounts(owner: authority) else {
            fatalError("Failed to derive PDA for \(coreMintMetadata.symbol)")
        }
        
        let createTemporaryCoreMint = AssociatedTokenProgram.CreateIdempotent(
            subsidizer: serverParams.payer,
            owner: swapAuthority,
            mint: coreMintMetadata.address
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
            createTemporaryCoreMint.instruction()
        )
        
        // 6. VM::TransferForSwap (Core Mint VM swap ATA -> Core Mint temporary account)
        instructions.append(
            VMProgram.TransferForSwap(
                vmAuthority: coreVM.authority,
                vm: coreVM.vm,
                swapper: authority,
                swapPda: coreTimelockAccounts.pda.publicKey,
                swapAta: coreTimelockAccounts.ata.publicKey,
                destination: createTemporaryCoreMint.address,
                amount: amount,
                bump: coreTimelockAccounts.pda.bump,
            ).instruction()
        )
        
        guard let feeTargetAccount = PublicKey.deriveAssociatedAccount(
            from: targetLaunchpad.authority,
            mint: targetMintMetadata.address
        )?.publicKey else {
            fatalError("Failed to derive fee target account for \(targetMintMetadata.symbol)")
        }
        
        // 7. CurrencyCreator::BuyAndDepositIntoVm
        instructions.append(
            CurrencyCreatorProgram.BuyAndDepositIntoVm(
                amount: amount,
                minOutAmount: minOutput,
                vmMemoryIndex: UInt16(serverParams.memoryIndex),
                buyer: swapAuthority,
                pool: targetLaunchpad.liquidityPool,
                currency: targetLaunchpad.currencyConfig,
                targetMint: targetMintMetadata.address,
                baseMint: coreMintMetadata.address,
                vaultTarget: targetLaunchpad.mintVault,
                vaultBase: targetLaunchpad.coreMintVault,
                buyerBase: createTemporaryCoreMint.address,
                feeTarget: feeTargetAccount,
                feeBase: targetLaunchpad.coreMintFees,
                vmAuthority: targetVM.authority,
                vm: targetVM.vm,
                vmMemory: serverParams.memoryAccount,
                vmOmnibus: targetVM.omnibus,
                vtaOwner: authority,
            ).instruction()
        )
        
        // 8. Token::CloseAccount (closes Core Mint temporary account)
        instructions.append(
            TokenProgram.CloseAccount(
                account: createTemporaryCoreMint.address,
                destination: serverParams.payer,
                owner: swapAuthority,
            ).instruction()
        )
        
        // 9. VM::CloseSwapAccountIfEmpty (closes Core Mint VM swap ATA if empty)
        instructions.append(
            VMProgram.CloseSwapAccountIfEmpty(
                vmAuthority: coreVM.authority,
                vm: coreVM.vm,
                swapper: authority,
                swapPda: coreTimelockAccounts.pda.publicKey,
                swapAta: coreTimelockAccounts.ata.publicKey,
                destination: serverParams.payer,
                bump: coreTimelockAccounts.pda.bump,
            ).instruction()
        )
        
        return instructions
    }
}
