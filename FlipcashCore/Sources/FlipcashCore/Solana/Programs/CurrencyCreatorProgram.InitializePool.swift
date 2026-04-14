//
//  CurrencyCreatorProgram.InitializePool.swift
//  FlipcashCore
//

import Foundation

extension CurrencyCreatorProgram {

    /// Initializes the liquidity pool for a launchpad currency, creating the pool
    /// PDA and both vault (treasury) PDAs for the target/base mint pair.
    ///
    /// Account structure (mirrors api/src/sdk.rs build_initialize_pool_ix):
    /// 0. [WRITE, SIGNER] Authority
    /// 1. []              Currency PDA
    /// 2. [WRITE]         Target mint (newly-initialized launchpad mint)
    /// 3. []              Base mint (USDF)
    /// 4. [WRITE]         Pool PDA        (seeds: ["pool", currency])
    /// 5. [WRITE]         Vault A PDA     (seeds: ["treasury", pool, target_mint])
    /// 6. [WRITE]         Vault B PDA     (seeds: ["treasury", pool, base_mint])
    /// 7. []              SPL Token program
    /// 8. []              System program
    /// 9. []              Sysvar rent
    public struct InitializePool: Equatable, Hashable, Codable {

        public let authority: PublicKey
        public let currency: PublicKey
        public let targetMint: PublicKey
        public let baseMint: PublicKey
        public let pool: PublicKey
        public let vaultA: PublicKey
        public let vaultB: PublicKey
        public let sellFeeBps: UInt16
        public let poolBump: UInt8
        public let vaultABump: UInt8
        public let vaultBBump: UInt8

        public init(
            authority: PublicKey,
            currency: PublicKey,
            targetMint: PublicKey,
            baseMint: PublicKey,
            pool: PublicKey,
            vaultA: PublicKey,
            vaultB: PublicKey,
            sellFeeBps: UInt16,
            poolBump: UInt8,
            vaultABump: UInt8,
            vaultBBump: UInt8
        ) {
            self.authority = authority
            self.currency = currency
            self.targetMint = targetMint
            self.baseMint = baseMint
            self.pool = pool
            self.vaultA = vaultA
            self.vaultB = vaultB
            self.sellFeeBps = sellFeeBps
            self.poolBump = poolBump
            self.vaultABump = vaultABump
            self.vaultBBump = vaultBBump
        }
    }
}

// MARK: - InstructionType -

extension CurrencyCreatorProgram.InitializePool: InstructionType {

    public init(instruction: Instruction) throws {
        // Data layout after discriminator byte:
        //   sell_fee      [u8; 2]
        //   pool_bump     u8
        //   vault_a_bump  u8
        //   vault_b_bump  u8
        //   _padding      [u8; 1]
        let data = try CurrencyCreatorProgram.parse(.initializePool, instruction: instruction, expectingAccounts: 10)

        guard data.count >= 6 else {
            throw CommandParseError.payloadNotFound
        }

        let bytes = Array(data)
        let sellFee = UInt16(bytes: Array(bytes[0..<2]))!

        self.init(
            authority: instruction.accounts[0].publicKey,
            currency: instruction.accounts[1].publicKey,
            targetMint: instruction.accounts[2].publicKey,
            baseMint: instruction.accounts[3].publicKey,
            pool: instruction.accounts[4].publicKey,
            vaultA: instruction.accounts[5].publicKey,
            vaultB: instruction.accounts[6].publicKey,
            sellFeeBps: sellFee,
            poolBump: bytes[2],
            vaultABump: bytes[3],
            vaultBBump: bytes[4]
        )
    }

    public func instruction() -> Instruction {
        let accounts: [AccountMeta] = [
            .writable(publicKey: authority, signer: true),
            .readonly(publicKey: currency),
            .writable(publicKey: targetMint),
            .readonly(publicKey: baseMint),
            .writable(publicKey: pool),
            .writable(publicKey: vaultA),
            .writable(publicKey: vaultB),
            .readonly(publicKey: TokenProgram.address),
            .readonly(publicKey: SystemProgram.address),
            .readonly(publicKey: SysVar.rent.address),
        ]

        return Instruction(
            program: CurrencyCreatorProgram.address,
            accounts: accounts,
            data: encode()
        )
    }

    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: CurrencyCreatorProgram.Command.initializePool.rawValue.bytes)
        data.append(contentsOf: sellFeeBps.bytes)   // sell_fee [u8; 2]
        data.append(poolBump)                        // bump u8
        data.append(vaultABump)                      // vault_a_bump u8
        data.append(vaultBBump)                      // vault_b_bump u8
        data.append(0)                               // _padding [u8; 1]
        return data
    }
}
