//
//  SwapInstructionBuilder+UsdcToUsdf.swift
//  FlipcashCore
//

import Foundation

/// Which of the owner's USDF accounts a USDC→USDF swap credits.
public enum UsdfSwapDestination: Equatable, Sendable {
    /// The owner's USDF VM **swap** PDA ATA — the in-VM buy/launch funding path.
    case swapPda
    /// The owner's USDF VM **Deposit** PDA ATA — the Geyser-watched address the
    /// server credits into the USDF balance. Used by the "Add Money" deposit via
    /// Phantom, where the signed transaction lands USDF directly in the deposit
    /// account (no separate sweep).
    case vmDeposit
}

extension SwapInstructionBuilder {

    /// Builds instructions for swapping USDC to USDF tokens.
    ///
    /// - Parameters:
    ///   - sender: The sender/payer of the transaction (Phantom wallet)
    ///   - owner: The owner for deriving timelock swap accounts (Flipcash user)
    ///   - amount: Amount of USDC to swap (in quarks)
    ///   - pool: The liquidity pool to use for the swap
    ///   - swapId: Unique identifier for the swap (used in memo)
    ///   - destination: Which of the owner's USDF accounts receives the swapped
    ///     USDF. Defaults to `.swapPda` (in-VM buy/launch). `.vmDeposit` lands the
    ///     USDF in the Geyser-watched VM Deposit ATA for the Add Money flow.
    /// - Returns: Array of 8 instructions for the USDC→USDF swap
    public static func buildUsdcToUsdfSwapInstructions(
        sender: PublicKey,
        owner: PublicKey,
        amount: UInt64,
        pool: LiquidityPool,
        swapId: PublicKey,
        destination: UsdfSwapDestination = .swapPda
    ) -> [Instruction] {
        guard let usdfSwapAccounts = MintMetadata.usdf.timelockSwapAccounts(owner: owner) else {
            fatalError("Failed to derive USDF swap accounts")
        }

        // Resolve the destination USDF ATA (and the account that owns it) that
        // the CreateIdempotent + final Token::Transfer credit.
        let destinationAtaOwner: PublicKey
        let destinationAta: PublicKey
        switch destination {
        case .swapPda:
            destinationAtaOwner = usdfSwapAccounts.pda.publicKey
            destinationAta = usdfSwapAccounts.ata.publicKey
        case .vmDeposit:
            guard let usdfVm = MintMetadata.usdf.vmMetadata else {
                fatalError("USDF mint missing VM metadata")
            }
            guard let depositPda = PublicKey.deriveDepositAccount(
                owner: owner,
                mint: .usdf,
                timeAuthority: usdfVm.authority,
                lockout: Byte(usdfVm.lockDurationInDays)
            ) else {
                fatalError("Failed to derive USDF VM Deposit PDA")
            }
            guard let depositAta = PublicKey.deriveAssociatedAccount(
                from: depositPda.publicKey,
                mint: .usdf
            ) else {
                fatalError("Failed to derive USDF VM Deposit ATA")
            }
            destinationAtaOwner = depositPda.publicKey
            destinationAta = depositAta.publicKey
        }

        let senderUsdfAta = AssociatedTokenProgram.CreateIdempotent(
            subsidizer: sender,
            owner: sender,
            mint: .usdf
        )

        // Usdf::Swap reads `userOtherToken` as a Token-program account; an
        // uninitialized canonical USDC ATA causes "Invalid account owner".
        // CreateIdempotent is a no-op when the account already exists.
        let senderUsdcAta = AssociatedTokenProgram.CreateIdempotent(
            subsidizer: sender,
            owner: sender,
            mint: .usdc
        )

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

        // 4. AssociatedTokenAccount::CreateIdempotent (destination USDF ATA —
        //    the owner's swap PDA ATA, or the VM Deposit ATA for Add Money)
        instructions.append(
            AssociatedTokenProgram.CreateIdempotent(
                subsidizer: sender,
                address: destinationAta,
                owner: destinationAtaOwner,
                mint: .usdf
            ).instruction()
        )

        // 5. AssociatedTokenAccount::CreateIdempotent (USDC ATA for sender)
        instructions.append(senderUsdcAta.instruction())

        // 6. Memo::Memo (swap ID for tracking)
        instructions.append(
            MemoProgram.Memo(message: swapId.base58).instruction()
        )

        // 7. Usdf::Swap (sender's USDC ATA → sender's USDF ATA)
        instructions.append(
            UsdfProgram.Swap(
                amount: amount,
                usdfToOther: false,
                user: sender,
                pool: pool.address,
                usdfVault: pool.usdfVault,
                otherVault: pool.otherVault,
                userUsdfToken: senderUsdfAta.address,
                userOtherToken: senderUsdcAta.address
            ).instruction()
        )

        // 8. Token::Transfer (sender's USDF ATA → destination USDF ATA)
        instructions.append(
            TokenProgram.Transfer(
                amount: amount,
                owner: sender,
                source: senderUsdfAta.address,
                destination: destinationAta
            ).instruction()
        )

        return instructions
    }
}
