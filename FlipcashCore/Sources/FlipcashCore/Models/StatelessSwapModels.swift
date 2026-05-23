//
//  StatelessSwapModels.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPC

// MARK: - Server parameters -

/// Server-provided parameters for executing a `StatelessSwap` against the
/// Coinbase Stable Swapper program. Mirrors
/// `Ocp_Transaction_V1_StatelessSwapResponse.ServerParameters.CoinbaseStableSwapperServerParameter`.
///
/// Unlike `SwapResponseServerParameters.CoinbaseStableSwapServerParameters`,
/// the stateless variant uses a regular recent blockhash (not a durable nonce)
/// and carries no `feeDestination` — the swap moves funds directly between the
/// owner's source ATA and the owner's destination VM Deposit ATA.
public struct StatelessSwapServerParameters: Sendable {
    public let payer: PublicKey
    public let blockhash: Hash
    public let alts: [AddressLookupTable]
    public let computeUnitLimit: UInt32
    public let computeUnitPrice: UInt64
    public let memoValue: String
    public let poolFeeRecipient: PublicKey

    public init(
        payer: PublicKey,
        blockhash: Hash,
        alts: [AddressLookupTable],
        computeUnitLimit: UInt32,
        computeUnitPrice: UInt64,
        memoValue: String,
        poolFeeRecipient: PublicKey
    ) {
        self.payer = payer
        self.blockhash = blockhash
        self.alts = alts
        self.computeUnitLimit = computeUnitLimit
        self.computeUnitPrice = computeUnitPrice
        self.memoValue = memoValue
        self.poolFeeRecipient = poolFeeRecipient
    }
}

extension StatelessSwapServerParameters {
    public init?(_ proto: Ocp_Transaction_V1_StatelessSwapResponse.ServerParameters.CoinbaseStableSwapperServerParameter) {
        guard
            let payer = try? PublicKey(proto.payer.value),
            let blockhash = try? Hash(proto.blockhash.value),
            let poolFeeRecipient = try? PublicKey(proto.poolFeeRecipient.value)
        else {
            return nil
        }

        self.init(
            payer: payer,
            blockhash: blockhash,
            alts: proto.alts.compactMap { AddressLookupTable($0) },
            computeUnitLimit: proto.computeUnitLimit,
            computeUnitPrice: proto.computeUnitPrice,
            memoValue: proto.memoValue,
            poolFeeRecipient: poolFeeRecipient
        )
    }
}

// MARK: - Result -

/// Terminal outcome of a successful `StatelessSwap`. `submitted` is returned
/// when the caller passed `waitForFinalization: false`; `finalized` is
/// returned when the caller waited for on-chain finalization.
public enum StatelessSwapResult: Sendable, Equatable {
    case submitted(signature: Signature)
    case finalized(signature: Signature)

    public var signature: Signature {
        switch self {
        case .submitted(let sig), .finalized(let sig):
            return sig
        }
    }
}

// MARK: - Errors -

/// Errors raised by `SwapService.statelessSwap`. Mirrors the proto error
/// codes plus client-side stream/transport failures.
public enum ErrorStatelessSwap: Error, Sendable {
    /// Denied by a server-side guard (spam, AML, etc).
    case denied(reason: String?)
    /// Invalid client-supplied signature.
    case signatureError
    /// Swap parameters failed server-side validation. `reason` carries the
    /// server's `ReasonStringErrorDetails` when present.
    case invalidSwap(reason: String?)
    /// Transaction reverted on-chain or its blockhash expired (only when
    /// `waitForFinalization: true`).
    case transactionFailed
    /// Stream returned an unexpected/unrecognized response.
    case unknown
    /// gRPC transport error.
    case grpcError(Error)
    /// gRPC stream closed with a non-OK status.
    case grpcStatus(GRPCStatus)
}

extension ErrorStatelessSwap: ServerError {
    public var isReportable: Bool {
        switch self {
        case .signatureError, .invalidSwap, .unknown:
            return true
        case .denied, .transactionFailed, .grpcError, .grpcStatus:
            return false
        }
    }
}

extension ErrorStatelessSwap {
    init(error: Ocp_Transaction_V1_StatelessSwapResponse.Error) {
        switch error.code {
        case .denied:
            let reason = error.errorDetails.compactMap { detail -> String? in
                guard case .denied(let denied) = detail.type else { return nil }
                return denied.reason.isEmpty ? nil : denied.reason
            }.first
            self = .denied(reason: reason)
        case .signatureError:
            self = .signatureError
        case .invalidSwap:
            self = .invalidSwap(reason: error.errorDetails.firstReasonString)
        case .transactionFailed:
            self = .transactionFailed
        case .UNRECOGNIZED:
            self = .unknown
        }
    }
}
