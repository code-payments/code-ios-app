//
//  VerifiedProtoStore.swift
//  FlipcashCore
//

import Foundation

/// Persistence surface required by `VerifiedProtoService`. Keeping this narrow lets
/// the service live in FlipcashCore without depending on the main-app `Database`.
///
/// Batch write methods take the whole stream tick in one call so the implementation
/// can wrap it in a single SQLite transaction — the stream delivers ~200 rates per
/// tick and per-row commits add up quickly.
public protocol VerifiedProtoStore: Sendable {
    func allRates() throws -> [StoredRateRow]
    func allReserves() throws -> [StoredReserveRow]
    func writeRates(_ rows: [StoredRateRow]) throws
    func writeReserves(_ rows: [StoredReserveRow]) throws
}

public struct StoredRateRow: Equatable, Sendable {
    public let currency: String
    public let rateProto: Data

    public init(currency: String, rateProto: Data) {
        self.currency = currency
        self.rateProto = rateProto
    }
}

public struct StoredReserveRow: Equatable, Sendable {
    public let mint: String
    public let reserveProto: Data

    public init(mint: String, reserveProto: Data) {
        self.mint = mint
        self.reserveProto = reserveProto
    }
}
