//
//  LaunchpadMint.swift
//  FlipcashCore
//

import Foundation

/// PDA helpers for the Reserve (currency creator) on-chain program.
/// Seed layouts mirror code-payments/flipcash-program @ api/src/pda.rs.
public enum LaunchpadMint {

    /// Pads a UTF-8 name to a 32-byte zero-padded array.
    /// Mirrors `to_name(val)` from api/src/utils.rs. Panics if name exceeds 32 bytes.
    static func paddedName(_ name: String) -> Data {
        let utf8 = Array(name.utf8)
        precondition(utf8.count <= 32, "Currency name exceeds 32 bytes")
        var padded = Data(count: 32)
        padded.replaceSubrange(0..<utf8.count, with: utf8)
        return padded
    }

    /// Derives the mint PDA. Seeds: [b"mint", authority, paddedName(name), seed].
    public static func deriveMint(
        authority: PublicKey,
        name: String,
        seed: PublicKey
    ) -> (PublicKey, UInt8)? {
        let seeds: [Data] = [
            Data("mint".utf8),
            authority.data,
            paddedName(name),
            seed.data,
        ]
        guard let pda = ProgramDerivedAccount.findProgramAddress(
            seeds: seeds,
            program: CurrencyCreatorProgram.address
        ) else {
            return nil
        }
        return (pda.publicKey, pda.bump)
    }

    /// Derives the currency PDA. Seeds: [b"currency", mint].
    public static func deriveCurrency(mint: PublicKey) -> (PublicKey, UInt8)? {
        guard let pda = ProgramDerivedAccount.findProgramAddress(
            seeds: [Data("currency".utf8), mint.data],
            program: CurrencyCreatorProgram.address
        ) else {
            return nil
        }
        return (pda.publicKey, pda.bump)
    }

    /// Derives the pool PDA. Seeds: [b"pool", currency].
    public static func derivePool(currency: PublicKey) -> (PublicKey, UInt8)? {
        guard let pda = ProgramDerivedAccount.findProgramAddress(
            seeds: [Data("pool".utf8), currency.data],
            program: CurrencyCreatorProgram.address
        ) else {
            return nil
        }
        return (pda.publicKey, pda.bump)
    }

    /// Derives the per-pool vault (treasury) PDA. Seeds: [b"treasury", pool, mint].
    public static func deriveVault(pool: PublicKey, mint: PublicKey) -> (PublicKey, UInt8)? {
        guard let pda = ProgramDerivedAccount.findProgramAddress(
            seeds: [Data("treasury".utf8), pool.data, mint.data],
            program: CurrencyCreatorProgram.address
        ) else {
            return nil
        }
        return (pda.publicKey, pda.bump)
    }
}
