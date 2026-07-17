//
//  CoinbaseStableSwapperProgram.PoolAccount.swift
//  FlipcashCore
//

import Foundation

extension CoinbaseStableSwapperProgram {

    /// The on-chain liquidity pool account.
    ///
    /// Layout: `[8 discriminator][32 operations_authority][32 pause_authority][32 fee_recipient]...`
    public struct PoolAccount: Equatable, Sendable {

        public let feeRecipient: PublicKey

        private static let feeRecipientOffset = 8 + 32 + 32

        /// Parses the raw pool account data, returning `nil` when the data is
        /// too short or the fee recipient bytes are not a valid public key.
        public init?(accountData: Data) {
            let offset = Self.feeRecipientOffset
            guard accountData.count >= offset + 32 else {
                return nil
            }

            let start = accountData.index(accountData.startIndex, offsetBy: offset)
            let end = accountData.index(start, offsetBy: 32)
            guard let feeRecipient = try? PublicKey(Data(accountData[start..<end])) else {
                return nil
            }

            self.feeRecipient = feeRecipient
        }
    }
}
