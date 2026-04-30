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
}
