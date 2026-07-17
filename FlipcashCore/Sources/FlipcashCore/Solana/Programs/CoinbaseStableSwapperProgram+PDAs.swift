//
//  CoinbaseStableSwapperProgram+PDAs.swift
//  FlipcashCore
//

import Foundation

extension CoinbaseStableSwapperProgram {

    /// PDA: ["liquidity_pool"] @ CoinbaseStableSwapperProgram
    public static func derivePoolAddress() -> ProgramDerivedAccount? {
        ProgramDerivedAccount.findProgramAddress(
            seeds: [Data("liquidity_pool".utf8)],
            program: address
        )
    }

    /// PDA: ["token_vault", pool, mint] @ CoinbaseStableSwapperProgram
    public static func deriveTokenVaultAddress(pool: PublicKey, mint: PublicKey) -> ProgramDerivedAccount? {
        ProgramDerivedAccount.findProgramAddress(
            seeds: [
                Data("token_vault".utf8),
                pool.data,
                mint.data,
            ],
            program: address
        )
    }

    /// PDA: ["vault_token_account", vault] @ CoinbaseStableSwapperProgram
    public static func deriveVaultTokenAccountAddress(vault: PublicKey) -> ProgramDerivedAccount? {
        ProgramDerivedAccount.findProgramAddress(
            seeds: [
                Data("vault_token_account".utf8),
                vault.data,
            ],
            program: address
        )
    }

    /// PDA: ["address_whitelist"] @ CoinbaseStableSwapperProgram
    public static func deriveWhitelistAddress() -> ProgramDerivedAccount? {
        ProgramDerivedAccount.findProgramAddress(
            seeds: [Data("address_whitelist".utf8)],
            program: address
        )
    }

    /// The pool-side accounts a `Swap` instruction targets for a mint pair.
    public struct SwapAccounts: Equatable, Sendable {
        public let pool: PublicKey
        public let inVault: PublicKey
        public let outVault: PublicKey
        public let inVaultTokenAccount: PublicKey
        public let outVaultTokenAccount: PublicKey
        public let whitelist: PublicKey
    }

    /// Derives every pool-side account `Swap` needs for the given mint pair,
    /// or `nil` when any derivation fails.
    public static func deriveSwapAccounts(
        fromMint: PublicKey,
        toMint: PublicKey
    ) -> SwapAccounts? {
        guard
            let pool = derivePoolAddress(),
            let inVault = deriveTokenVaultAddress(pool: pool.publicKey, mint: fromMint),
            let outVault = deriveTokenVaultAddress(pool: pool.publicKey, mint: toMint),
            let inVaultTokenAccount = deriveVaultTokenAccountAddress(vault: inVault.publicKey),
            let outVaultTokenAccount = deriveVaultTokenAccountAddress(vault: outVault.publicKey),
            let whitelist = deriveWhitelistAddress()
        else {
            return nil
        }

        return SwapAccounts(
            pool: pool.publicKey,
            inVault: inVault.publicKey,
            outVault: outVault.publicKey,
            inVaultTokenAccount: inVaultTokenAccount.publicKey,
            outVaultTokenAccount: outVaultTokenAccount.publicKey,
            whitelist: whitelist.publicKey
        )
    }
}
