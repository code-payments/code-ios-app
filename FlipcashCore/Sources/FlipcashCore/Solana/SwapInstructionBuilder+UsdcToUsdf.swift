//
//  SwapInstructionBuilder+UsdcToUsdf.swift
//  FlipcashCore
//
//  Created by Claude on 2025-01-26.
//

import Foundation

extension SwapInstructionBuilder {

    /// Builds instructions for swapping USDC to USDF tokens.
    ///
    /// - Parameters:
    ///   - sender: The sender/payer of the transaction (Phantom wallet)
    ///   - owner: The owner for deriving timelock swap accounts (Flipcash user)
    ///   - amount: Amount of USDC to swap (in quarks)
    ///   - pool: The liquidity pool to use for the swap
    ///   - swapId: Unique identifier for the swap (used in memo)
    /// - Returns: Array of 7 instructions for the USDC→USDF swap
    public static func buildUsdcToUsdfSwapInstructions(
        sender: PublicKey,
        owner: PublicKey,
        amount: UInt64,
        pool: LiquidityPool,
        swapId: PublicKey
    ) -> [Instruction] {
        guard let usdfSwapAccounts = MintMetadata.usdf.timelockSwapAccounts(owner: owner) else {
            fatalError("Failed to derive USDF swap accounts")
        }

        let senderUsdfAta = AssociatedTokenProgram.CreateIdempotent(
            subsidizer: sender,
            owner: sender,
            mint: .usdf
        )

        guard let senderUsdcAta = PublicKey.deriveAssociatedAccount(from: sender, mint: .usdc) else {
            fatalError("Failed to derive USDC ATA")
        }

        var instructions: [Instruction] = []

        // 1. ComputeBudget::SetComputeUnitLimit
        instructions.append(
            ComputeBudgetProgram.SetComputeUnitLimit(units: 200_000).instruction()
        )

        // 2. ComputeBudget::SetComputeUnitPrice
        instructions.append(
            ComputeBudgetProgram.SetComputeUnitPrice(microLamports: 1_000).instruction()
        )

        // 3. AssociatedTokenAccount::CreateIdempotent (USDF ATA for sender)
        instructions.append(senderUsdfAta.instruction())

        // 4. AssociatedTokenAccount::CreateIdempotent (USDF ATA for owner's swap PDA)
        instructions.append(
            AssociatedTokenProgram.CreateIdempotent(
                subsidizer: sender,
                owner: usdfSwapAccounts.pda.publicKey,
                mint: .usdf
            ).instruction()
        )

        // 5. Memo::Memo (swap ID for tracking)
        instructions.append(
            MemoProgram.Memo(message: swapId.base58).instruction()
        )

        // 6. Usdf::Swap (sender's USDC ATA → sender's USDF ATA)
        instructions.append(
            UsdfProgram.Swap(
                amount: amount,
                usdfToOther: false,
                user: sender,
                pool: pool.address,
                usdfVault: pool.usdfVault,
                otherVault: pool.otherVault,
                userUsdfToken: senderUsdfAta.address,
                userOtherToken: senderUsdcAta.publicKey
            ).instruction()
        )

        // 7. Token::Transfer (sender's USDF ATA → owner's USDF swap PDA ATA)
        instructions.append(
            TokenProgram.Transfer(
                amount: amount,
                owner: sender,
                source: senderUsdfAta.address,
                destination: usdfSwapAccounts.ata.publicKey
            ).instruction()
        )

        return instructions
    }
}
