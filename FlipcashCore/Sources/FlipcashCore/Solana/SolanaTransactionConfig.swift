//
//  SolanaTransactionConfig.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// Fee and resource configuration the server provides for a Solana v1 (SIMD-0385) transaction message.
public struct SolanaTransactionConfig: Equatable, Sendable {
    /// The compute unit limit for the transaction.
    public let computeUnitLimit: UInt32
    /// The loaded accounts data size limit for the transaction, in bytes.
    public let loadedAccountsDataSizeLimit: UInt32
    /// The total priority fee for the transaction in lamports, not a per-compute-unit price.
    public let priorityFeeLamports: UInt64
    /// The requested heap size in bytes, where 0 means the runtime default.
    public let heapSize: UInt32

    /// Creates a config from its four values.
    public init(
        computeUnitLimit: UInt32,
        loadedAccountsDataSizeLimit: UInt32,
        priorityFeeLamports: UInt64,
        heapSize: UInt32
    ) {
        self.computeUnitLimit = computeUnitLimit
        self.loadedAccountsDataSizeLimit = loadedAccountsDataSizeLimit
        self.priorityFeeLamports = priorityFeeLamports
        self.heapSize = heapSize
    }
}

extension SolanaTransactionConfig {
    /// Creates a config carrying the proto's values unchanged.
    public init(_ proto: Ocp_Common_V1_SolanaTransactionConfig) {
        self.init(
            computeUnitLimit: proto.computeUnitLimit,
            loadedAccountsDataSizeLimit: proto.loadedAccountsDataSizeLimit,
            priorityFeeLamports: proto.priorityFeeLamports,
            heapSize: proto.heapSize
        )
    }
}
