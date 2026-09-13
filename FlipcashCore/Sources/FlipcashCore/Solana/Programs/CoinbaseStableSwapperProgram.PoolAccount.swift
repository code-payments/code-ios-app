//
//  CoinbaseStableSwapperProgram.PoolAccount.swift
//  FlipcashCore
//

import Foundation

extension CoinbaseStableSwapperProgram {

    /// The on-chain liquidity pool account.
    ///
    /// Layout, decoded from the live pool account `CrDL9SoCyW1tBgn8k7rgGSpWhnszneWDbvKvqPAU4PL9`
    /// (owner `pqgqKahpG1y2wsgxFhzaAnkV1cL9vk8MSg9qm4q646F`):
    /// ```
    ///   0   [8]  discriminator            sha256("account:LiquidityPool")[0..8]
    ///   8   [32] operations_authority
    ///   40  [32] pause_authority
    ///   72  [32] unnamed pubkey           <- not described by the published IDL
    ///   104 [32] unnamed pubkey           <- not described by the published IDL
    ///   136 [32] fee_recipient
    ///   168      vec<pubkey> (length 2 on the live account), then supported_tokens,
    ///            fee_rate, swaps_paused, liquidity_paused, bump — not parsed by this type
    /// ```
    /// The program's published Anchor IDL does not describe this struct. It lists three
    /// pubkeys, then `supported_tokens`, which puts `fee_recipient` at offset 72; mainnet has
    /// it at 136. Regenerating this layout from that IDL reintroduces the bug this type exists
    /// to fix, and neither of the two pubkeys the IDL omits has a published name to give it.
    public struct PoolAccount: Equatable, Sendable {

        /// `sha256("account:LiquidityPool")[0..8]`, Anchor's account discriminator for this type.
        private static let discriminator: [UInt8] = [66, 38, 17, 64, 188, 80, 68, 129]

        private static let feeRecipientOffset = 8 + 32 + 32 + 32 + 32

        public let feeRecipient: PublicKey

        /// Parses the raw pool account data, returning `nil` when the data is too short,
        /// the leading discriminator doesn't match `LiquidityPool`, or the fee recipient
        /// bytes are not a valid public key.
        public init?(accountData: Data) {
            guard accountData.prefix(Self.discriminator.count).elementsEqual(Self.discriminator) else {
                return nil
            }

            var payload = accountData.tail(from: Self.feeRecipientOffset)
            guard let feeRecipient = try? PublicKey(payload.consume(PublicKey.length)) else {
                return nil
            }

            self.feeRecipient = feeRecipient
        }
    }
}
