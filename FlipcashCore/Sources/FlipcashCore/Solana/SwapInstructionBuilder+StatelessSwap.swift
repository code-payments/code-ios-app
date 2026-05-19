//
//  SwapInstructionBuilder+StatelessSwap.swift
//  FlipcashCore
//

import Foundation

extension SwapInstructionBuilder {

    /// Builds the instruction list for a `StatelessSwap` against the Coinbase
    /// Stable Swapper. Mirrors the on-chain layout documented on
    /// `Ocp_Transaction_V1_StatelessSwapResponse.ServerParameters.CoinbaseStableSwapperServerParameter`:
    ///
    /// ```
    /// 1. [Optional] ComputeBudget::SetComputeUnitLimit
    /// 2. [Optional] ComputeBudget::SetComputeUnitPrice
    /// 3. [Optional] Memo::Memo
    /// 4. AssociatedTokenAccount::CreateIdempotent (open owner's to_mint VM Deposit ATA)
    /// 5. CoinbaseStableSwapper::Swap (owner's from_mint ATA -> owner's to_mint VM Deposit ATA)
    /// ```
    ///
    /// Used by the on-app-open USDC → USDF sweep: source is the owner's plain
    /// USDC ATA, destination is the owner's USDF VM Deposit ATA (Geyser-monitored
    /// — once funds land there, the server-side watcher transfers them into
    /// the USDF VM).
    ///
    /// - Parameters:
    ///   - serverParameters: Server-provided swap parameters.
    ///   - owner: User authority public key — signs the swap, owns the source ATA.
    ///   - fromMint: Source mint metadata (USDC).
    ///   - toMint: Destination mint metadata (USDF). Must have `vmMetadata`.
    ///   - amount: Source quarks to swap.
    public static func buildStatelessSwapInstructions(
        serverParameters: StatelessSwapServerParameters,
        owner: PublicKey,
        fromMint: MintMetadata,
        toMint: MintMetadata,
        amount: UInt64
    ) -> [Instruction] {
        guard let toVm = toMint.vmMetadata else {
            fatalError("Destination mint missing VM metadata: \(toMint.symbol)")
        }

        // Owner's source-mint ATA — where external USDC deposits land.
        guard let ownerFromAta = PublicKey.deriveAssociatedAccount(
            from: owner,
            mint: fromMint.address
        ) else {
            fatalError("Failed to derive owner's source-mint ATA")
        }

        // Owner's destination-mint VM Deposit ATA — the address Geyser watches.
        // Same derivation as `SwapInstructionBuilder+NewCurrency.swift`: ATA
        // owned by the VM Deposit PDA, not by the user authority directly.
        guard let ownerToVmDepositPda = PublicKey.deriveDepositAccount(
            owner: owner,
            mint: toMint.address,
            timeAuthority: toVm.authority,
            lockout: Byte(toVm.lockDurationInDays)
        ) else {
            fatalError("Failed to derive owner's destination-mint VM Deposit PDA")
        }

        guard let ownerToVmDepositAta = PublicKey.deriveAssociatedAccount(
            from: ownerToVmDepositPda.publicKey,
            mint: toMint.address
        ) else {
            fatalError("Failed to derive owner's destination-mint VM Deposit ATA")
        }

        // Coinbase Stable Swapper PDAs.
        guard let pool = CoinbaseStableSwapperProgram.derivePoolAddress() else {
            fatalError("Failed to derive Coinbase pool address")
        }
        guard let inVault = CoinbaseStableSwapperProgram.deriveTokenVaultAddress(
            pool: pool.publicKey,
            mint: fromMint.address
        ) else {
            fatalError("Failed to derive Coinbase in-vault address")
        }
        guard let outVault = CoinbaseStableSwapperProgram.deriveTokenVaultAddress(
            pool: pool.publicKey,
            mint: toMint.address
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

        // Fee recipient's source-mint ATA — fee is paid in the from-mint,
        // matching the existing USDF→USDC pattern in
        // `SwapInstructionBuilder+UsdfToUsdc.swift`.
        guard let feeRecipientFromAta = PublicKey.deriveAssociatedAccount(
            from: serverParameters.poolFeeRecipient,
            mint: fromMint.address
        ) else {
            fatalError("Failed to derive fee recipient from-mint ATA")
        }

        var instructions: [Instruction] = []

        // 1. [Optional] ComputeBudget::SetComputeUnitLimit
        if serverParameters.computeUnitLimit != 0 {
            instructions.append(
                ComputeBudgetProgram.SetComputeUnitLimit(
                    units: serverParameters.computeUnitLimit
                ).instruction()
            )
        }

        // 2. [Optional] ComputeBudget::SetComputeUnitPrice
        if serverParameters.computeUnitPrice != 0 {
            instructions.append(
                ComputeBudgetProgram.SetComputeUnitPrice(
                    microLamports: serverParameters.computeUnitPrice
                ).instruction()
            )
        }

        // 3. [Optional] Memo::Memo
        if !serverParameters.memoValue.isEmpty {
            instructions.append(
                MemoProgram.Memo(
                    message: serverParameters.memoValue
                ).instruction()
            )
        }

        // 4. AssociatedTokenAccount::CreateIdempotent — open owner's to-mint VM Deposit ATA.
        instructions.append(
            AssociatedTokenProgram.CreateIdempotent(
                subsidizer: serverParameters.payer,
                address: ownerToVmDepositAta.publicKey,
                owner: ownerToVmDepositPda.publicKey,
                mint: toMint.address
            ).instruction()
        )

        // 5. CoinbaseStableSwapper::Swap — owner's from-mint ATA → owner's to-mint VM Deposit ATA.
        //    `minAmountOut: amount` enforces a 1:1 rate; the Coinbase Stable
        //    Swapper is a stable pair so any slippage indicates a misconfigured
        //    pool and the swap should fail server-side rather than silently
        //    lose value.
        instructions.append(
            CoinbaseStableSwapperProgram.Swap(
                pool: pool.publicKey,
                inVault: inVault.publicKey,
                outVault: outVault.publicKey,
                inVaultTokenAccount: inVaultTokenAccount.publicKey,
                outVaultTokenAccount: outVaultTokenAccount.publicKey,
                userFromTokenAccount: ownerFromAta.publicKey,
                toTokenAccount: ownerToVmDepositAta.publicKey,
                feeRecipientTokenAccount: feeRecipientFromAta.publicKey,
                feeRecipient: serverParameters.poolFeeRecipient,
                fromMint: fromMint.address,
                toMint: toMint.address,
                user: owner,
                whitelist: whitelist.publicKey,
                amountIn: amount,
                minAmountOut: amount
            ).instruction()
        )

        return instructions
    }
}
