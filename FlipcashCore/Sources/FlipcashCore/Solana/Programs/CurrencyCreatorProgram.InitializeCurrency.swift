//
//  CurrencyCreatorProgram.InitializeCurrency.swift
//  FlipcashCore
//

import Foundation

extension CurrencyCreatorProgram {

    /// Initializes a new launchpad currency by creating the mint PDA and currency
    /// configuration PDA for the given authority/name/seed tuple.
    ///
    /// Account structure (mirrors api/src/sdk.rs build_initialize_currency_ix):
    /// 0. [WRITE, SIGNER] Authority
    /// 1. [WRITE] Mint PDA            (seeds: ["mint", authority, paddedName, seed])
    /// 2. [WRITE] Currency PDA        (seeds: ["currency", mint])
    /// 3. []      SPL Token program
    /// 4. []      System program
    /// 5. []      Sysvar rent
    public struct InitializeCurrency: Equatable, Hashable, Codable {

        public let authority: PublicKey
        public let mint: PublicKey
        public let currency: PublicKey
        public let name: String
        public let symbol: String
        public let seed: PublicKey
        public let currencyBump: UInt8
        public let mintBump: UInt8

        public init(
            authority: PublicKey,
            mint: PublicKey,
            currency: PublicKey,
            name: String,
            symbol: String,
            seed: PublicKey,
            currencyBump: UInt8,
            mintBump: UInt8
        ) {
            self.authority = authority
            self.mint = mint
            self.currency = currency
            self.name = name
            self.symbol = symbol
            self.seed = seed
            self.currencyBump = currencyBump
            self.mintBump = mintBump
        }
    }
}

// MARK: - InstructionType -

extension CurrencyCreatorProgram.InitializeCurrency: InstructionType {

    public init(instruction: Instruction) throws {
        // Data layout after discriminator byte:
        //   name    [u8; 32]
        //   symbol  [u8; 8]
        //   seed    [u8; 32]
        //   currency_bump u8
        //   mint_bump     u8
        //   _padding [u8; 6]
        let data = try CurrencyCreatorProgram.parse(.initializeCurrency, instruction: instruction, expectingAccounts: 6)

        guard data.count >= 80 else {
            throw CommandParseError.payloadNotFound
        }

        let bytes = Array(data)
        var offset = 0

        let nameBytes = Array(bytes[offset..<offset + 32])
        offset += 32
        let symbolBytes = Array(bytes[offset..<offset + 8])
        offset += 8
        let seedBytes = Array(bytes[offset..<offset + 32])
        offset += 32
        let currencyBump = bytes[offset]
        offset += 1
        let mintBump = bytes[offset]

        let name = String(bytes: nameBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
        let symbol = String(bytes: symbolBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
        let seed = try PublicKey(Data(seedBytes))

        self.init(
            authority: instruction.accounts[0].publicKey,
            mint: instruction.accounts[1].publicKey,
            currency: instruction.accounts[2].publicKey,
            name: name,
            symbol: symbol,
            seed: seed,
            currencyBump: currencyBump,
            mintBump: mintBump
        )
    }

    public func instruction() -> Instruction {
        let accounts: [AccountMeta] = [
            .writable(publicKey: authority, signer: true),
            .writable(publicKey: mint),
            .writable(publicKey: currency),
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
        data.append(contentsOf: CurrencyCreatorProgram.Command.initializeCurrency.rawValue.bytes)
        data.append(LaunchpadMint.paddedName(name))          // name [u8; 32]
        data.append(Self.paddedSymbol(symbol))                // symbol [u8; 8]
        data.append(seed.data)                                // seed [u8; 32]
        data.append(currencyBump)                             // bump u8
        data.append(mintBump)                                 // mint_bump u8
        data.append(Data(repeating: 0, count: 6))             // _padding [u8; 6]
        return data
    }

    /// Pads a UTF-8 symbol to an 8-byte zero-padded array. Mirrors `to_symbol`.
    static func paddedSymbol(_ symbol: String) -> Data {
        let utf8 = Array(symbol.utf8)
        precondition(utf8.count <= 8, "Currency symbol exceeds 8 bytes")
        var padded = Data(count: 8)
        padded.replaceSubrange(0..<utf8.count, with: utf8)
        return padded
    }
}
