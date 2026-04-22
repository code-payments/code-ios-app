//
//  SwapInstructionBuilder+NewCurrency.swift
//  FlipcashCore
//

import Foundation

extension SwapInstructionBuilder {

    /// Builds the atomic launch-and-first-buy instruction list for a new
    /// launchpad currency. Per the ReserveNewCurrencyServerParameter proto
    /// comment, the transaction interleaves Reserve::InitializeCurrency +
    /// InitializePool + VM::InitializeVm with the standard ATA creates /
    /// VM::TransferForSwapWithFee / Reserve::BuyTokens / close-account sequence.
    ///
    /// Only the creator (owner == swap_authority == serverParams.authority) can
    /// execute this path; the caller must enforce that.
    ///
    /// - Parameters:
    ///   - serverParams: ReserveNewCurrency server-provided parameters
    ///   - authority: The owner/authority signing the transaction (also the VM/currency authority)
    ///   - swapAmount: Amount of Core Mint (USDF) quarks that will be spent on the first-ever buy (becomes tokens)
    ///   - feeAmount: Amount of Core Mint (USDF) quarks paid as a launch fee to `serverParams.feeDestination`
    /// - Returns: Ordered list of instructions for the launch-and-first-buy transaction
    static func newCurrencyLaunch(
        serverParams: SwapResponseServerParameters.ReserveNewCurrency,
        authority: PublicKey,
        swapAmount: UInt64,
        feeAmount: UInt64
    ) -> [Instruction] {
        let coreMint = MintMetadata.usdf
        guard let coreVM = coreMint.vmMetadata else {
            fatalError("USDF must have VM metadata")
        }

        // Derive all launchpad PDAs from server params.
        guard let (targetMint, mintBump) = LaunchpadMint.deriveMint(
            authority: serverParams.authority,
            name: serverParams.name,
            seed: serverParams.seed
        ) else {
            fatalError("Failed to derive target mint PDA")
        }

        guard let (currency, currencyBump) = LaunchpadMint.deriveCurrency(mint: targetMint) else {
            fatalError("Failed to derive currency PDA")
        }

        guard let (pool, poolBump) = LaunchpadMint.derivePool(currency: currency) else {
            fatalError("Failed to derive pool PDA")
        }

        guard let (vaultA, vaultABump) = LaunchpadMint.deriveVault(pool: pool, mint: targetMint) else {
            fatalError("Failed to derive vault A PDA")
        }

        guard let (vaultB, vaultBBump) = LaunchpadMint.deriveVault(pool: pool, mint: coreMint.address) else {
            fatalError("Failed to derive vault B PDA")
        }

        // Derive the new VM that will hold deposits of the newly-launched
        // currency. The VM is keyed on (mint=targetMint, authority, lockDuration).
        // Seeds: ["code_vm", targetMint, authority, [lockDuration]].
        let lockDuration = Byte(serverParams.vmLockDurationInDays)
        guard let newVmAccount = PublicKey.deriveVMAccount(
            mint: targetMint,
            timeAuthority: serverParams.authority,
            lockout: lockDuration
        ) else {
            fatalError("Failed to derive new VM account")
        }

        guard let newVmOmnibus = PublicKey.deriveVmOmnibusAddress(vm: newVmAccount.publicKey) else {
            fatalError("Failed to derive new VM omnibus")
        }

        // Owner's deposit PDA on the new target-mint VM — used as the ATA
        // holder for the newly-minted target tokens.
        guard let ownerVMDepositPda = PublicKey.deriveDepositAccount(
            owner: authority,
            mint: targetMint,
            timeAuthority: serverParams.authority,
            lockout: lockDuration
        ) else {
            fatalError("Failed to derive owner VM deposit PDA")
        }

        // Owner's Core Mint (USDF) ATA — plain associated token account.
        guard let ownerCoreMintATA = PublicKey.deriveAssociatedAccount(
            from: authority,
            mint: coreMint.address
        ) else {
            fatalError("Failed to derive owner Core Mint ATA")
        }

        // Owner's target-mint VM Deposit ATA — the ATA of the VM deposit PDA
        // for the newly-launched mint.
        guard let ownerTargetVMDepositATA = PublicKey.deriveAssociatedAccount(
            from: ownerVMDepositPda.publicKey,
            mint: targetMint
        ) else {
            fatalError("Failed to derive owner target VM deposit ATA")
        }

        // Existing USDF VM swap accounts — source of the Core Mint transfer.
        guard let coreSwapAccounts = coreMint.timelockSwapAccounts(owner: authority) else {
            fatalError("Failed to derive Core Mint timelock swap accounts")
        }

        var instructions: [Instruction] = []

        // 1. System::AdvanceNonce
        instructions.append(
            SystemProgram.AdvanceNonce(
                nonce: serverParams.nonce,
                authority: serverParams.payer
            ).instruction()
        )

        // 2. [Optional] ComputeBudget::SetComputeUnitLimit
        if serverParams.computeUnitLimit != 0 {
            instructions.append(
                ComputeBudgetProgram.SetComputeUnitLimit(
                    units: serverParams.computeUnitLimit
                ).instruction()
            )
        }

        // 3. [Optional] ComputeBudget::SetComputeUnitPrice
        if serverParams.computeUnitPrice != 0 {
            instructions.append(
                ComputeBudgetProgram.SetComputeUnitPrice(
                    microLamports: serverParams.computeUnitPrice
                ).instruction()
            )
        }

        // 4. [Optional] Memo::Memo
        if !serverParams.memoValue.isEmpty {
            instructions.append(
                MemoProgram.Memo(
                    message: serverParams.memoValue
                ).instruction()
            )
        }

        // 5. Reserve::InitializeCurrency
        instructions.append(
            CurrencyCreatorProgram.InitializeCurrency(
                authority: serverParams.authority,
                mint: targetMint,
                currency: currency,
                name: serverParams.name,
                symbol: serverParams.symbol,
                seed: serverParams.seed,
                currencyBump: currencyBump,
                mintBump: mintBump
            ).instruction()
        )

        // 6. Reserve::InitializePool
        instructions.append(
            CurrencyCreatorProgram.InitializePool(
                authority: serverParams.authority,
                currency: currency,
                targetMint: targetMint,
                baseMint: coreMint.address,
                pool: pool,
                vaultA: vaultA,
                vaultB: vaultB,
                sellFeeBps: UInt16(serverParams.sellFeeBps),
                poolBump: poolBump,
                vaultABump: vaultABump,
                vaultBBump: vaultBBump
            ).instruction()
        )

        // 7. VM::InitializeVm — new VM keyed on the newly-launched mint;
        //    holds the creator's first-buy deposit and any future deposits of
        //    this currency.
        instructions.append(
            VMProgram.InitializeVm(
                vmAuthority: serverParams.authority,
                vm: newVmAccount.publicKey,
                omnibus: newVmOmnibus.publicKey,
                mint: targetMint,
                lockDuration: lockDuration,
                vmBump: newVmAccount.bump,
                vmOmnibusBump: newVmOmnibus.bump
            ).instruction()
        )

        // 8. ATA::CreateIdempotent — owner's Core Mint (USDF) ATA
        let createCoreMintATA = AssociatedTokenProgram.CreateIdempotent(
            subsidizer: serverParams.authority,
            address: ownerCoreMintATA.publicKey,
            owner: authority,
            mint: coreMint.address
        )
        instructions.append(createCoreMintATA.instruction())

        // 9. ATA::CreateIdempotent — owner's target-mint VM Deposit ATA
        instructions.append(
            AssociatedTokenProgram.CreateIdempotent(
                subsidizer: serverParams.authority,
                address: ownerTargetVMDepositATA.publicKey,
                owner: ownerVMDepositPda.publicKey,
                mint: targetMint
            ).instruction()
        )

        // 10. VM::TransferForSwapWithFee — existing USDF VM swap ATA splits into
        //     swap destination (owner's Core Mint ATA) and fee destination.
        instructions.append(
            VMProgram.TransferForSwapWithFee(
                vmAuthority: coreVM.authority,
                vm: coreVM.vm,
                swapper: authority,
                swapPda: coreSwapAccounts.pda.publicKey,
                swapAta: coreSwapAccounts.ata.publicKey,
                swapDestination: ownerCoreMintATA.publicKey,
                feeDestination: serverParams.feeDestination,
                swapAmount: swapAmount,
                feeAmount: feeAmount,
                bump: coreSwapAccounts.pda.bump
            ).instruction()
        )

        // 11. Reserve::BuyTokens — swap USDF for new-currency tokens, depositing
        //     the output into the owner's target-mint VM Deposit ATA.
        //     min_amount_out is 0 (no slippage protection on the first-ever buy).
        instructions.append(
            CurrencyCreatorProgram.BuyTokens(
                buyer: authority,
                pool: pool,
                targetMint: targetMint,
                baseMint: coreMint.address,
                vaultA: vaultA,
                vaultB: vaultB,
                buyerTarget: ownerTargetVMDepositATA.publicKey,
                buyerBase: ownerCoreMintATA.publicKey,
                amount: swapAmount,
                minOutAmount: 0
            ).instruction()
        )

        // 12. Token::CloseAccount — closes owner's Core Mint ATA, rent to authority
        instructions.append(
            TokenProgram.CloseAccount(
                account: ownerCoreMintATA.publicKey,
                destination: serverParams.authority,
                owner: authority
            ).instruction()
        )

        return instructions
    }
}
