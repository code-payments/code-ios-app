//
//  Activity+Metadata.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-29.
//

import Foundation
import FlipcashAPI

extension Activity {
    public struct CashLinkMetadata: Sendable, Equatable, Hashable {
        public let vault: PublicKey
        public let canCancel: Bool
        
        public init(vault: PublicKey, canCancel: Bool) {
            self.vault = vault
            self.canCancel = canCancel
        }
    }
}

extension Activity.CashLinkMetadata {
    init(_ proto: Flipcash_Activity_V1_IndirectlySentCryptoNotificationMetadata) throws {
        self.init(
            vault: try PublicKey(proto.vault.value),
            canCancel: proto.canInitiateCancelAction
        )
    }
}

extension Activity {
    /// The two legs of a swap plus its fee, carried on a `.swapped` activity so a
    /// row can render "<from> → <to>" and the fee without a second lookup. The
    /// destination amount is only known once the swap executes; until then only
    /// `toMint` is set (`toQuarks`/`toFiat` are `nil`).
    public struct SwapMetadata: Sendable, Equatable, Hashable {

        /// The whole-swap lifecycle state as reported by the server.
        public enum State: Int, Sendable {
            case unknown   = 0
            case pending   = 1
            case succeeded = 2
            case failed    = 3
            case none      = 4
        }

        /// Source mint the user converted away from.
        public let fromMint: PublicKey
        /// On-chain quantity given up, in the source mint's quarks.
        public let fromQuarks: UInt64
        /// Fiat value of the source leg — the amount the row displays.
        public let fromFiat: FiatAmount

        /// Destination mint the user received.
        public let toMint: PublicKey
        /// On-chain quantity received, once the swap has executed.
        public let toQuarks: UInt64?
        /// Fiat value of the destination leg, once the swap has executed.
        public let toFiat: FiatAmount?

        /// Swap fee, known upfront regardless of swap state.
        public let fee: FiatAmount
        public let state: State

        public init(
            fromMint: PublicKey,
            fromQuarks: UInt64,
            fromFiat: FiatAmount,
            toMint: PublicKey,
            toQuarks: UInt64?,
            toFiat: FiatAmount?,
            fee: FiatAmount,
            state: State,
        ) {
            self.fromMint   = fromMint
            self.fromQuarks = fromQuarks
            self.fromFiat   = fromFiat
            self.toMint     = toMint
            self.toQuarks   = toQuarks
            self.toFiat     = toFiat
            self.fee        = fee
            self.state      = state
        }
    }
}

extension Activity.SwapMetadata.State {
    init(_ proto: Flipcash_Activity_V1_SwapState) {
        self = Activity.SwapMetadata.State(rawValue: proto.rawValue) ?? .unknown
    }
}

extension Activity.SwapMetadata {
    /// Missing `to` oneof — an invalid swap notification the client can't render.
    enum ParseError: Error {
        case missingDestination
    }

    init(_ proto: Flipcash_Activity_V1_SwappedCryptoNotificationMetadata) throws {
        let fromFiat = FiatAmount(
            value: Decimal(proto.from.nativeAmount),
            currency: try CurrencyCode(currencyCode: proto.from.currency)
        )

        let toMint: PublicKey
        let toQuarks: UInt64?
        let toFiat: FiatAmount?

        switch proto.to {
        case .toAmount(let amount):
            toMint   = try PublicKey(amount.mint.value)
            toQuarks = amount.quarks
            toFiat   = FiatAmount(
                value: Decimal(amount.nativeAmount),
                currency: try CurrencyCode(currencyCode: amount.currency)
            )
        case .toMint(let mint):
            toMint   = try PublicKey(mint.value)
            toQuarks = nil
            toFiat   = nil
        case .none:
            throw ParseError.missingDestination
        }

        self.init(
            fromMint: try PublicKey(proto.from.mint.value),
            fromQuarks: proto.from.quarks,
            fromFiat: fromFiat,
            toMint: toMint,
            toQuarks: toQuarks,
            toFiat: toFiat,
            fee: FiatAmount(
                value: Decimal(proto.fee.nativeAmount),
                currency: try CurrencyCode(currencyCode: proto.fee.currency)
            ),
            state: .init(proto.swapState)
        )
    }
}
