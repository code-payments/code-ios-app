//
//  VerifiedProtoStore.swift
//  FlipcashCore
//

import Foundation

/// Persistence surface required by `VerifiedProtoService`. Keeping this narrow lets
/// the service live in FlipcashCore without depending on the main-app `Database`.
public protocol VerifiedProtoStore: Sendable {
    func allRates() throws -> [StoredRateRow]
    func allReserves() throws -> [StoredReserveRow]
    func writeRate(_ row: StoredRateRow) throws
    func writeReserve(_ row: StoredReserveRow) throws
}

public struct StoredRateRow: Equatable, Sendable {
    public let currency: String
    public let rateProto: Data
    public let receivedAt: Date

    public init(currency: String, rateProto: Data, receivedAt: Date) {
        self.currency = currency
        self.rateProto = rateProto
        self.receivedAt = receivedAt
    }
}

public struct StoredReserveRow: Equatable, Sendable {
    public let mint: String
    public let reserveProto: Data
    public let receivedAt: Date

    public init(mint: String, reserveProto: Data, receivedAt: Date) {
        self.mint = mint
        self.reserveProto = reserveProto
        self.receivedAt = receivedAt
    }
}
