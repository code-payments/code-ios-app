//
//  InMemoryVerifiedProtoStore.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore

final class InMemoryVerifiedProtoStore: VerifiedProtoStore, @unchecked Sendable {
    private let lock = NSLock()
    private var rates: [String: StoredRateRow] = [:]
    private var reserves: [String: StoredReserveRow] = [:]
    private(set) var writeRateCalls: [StoredRateRow] = []
    private(set) var writeReserveCalls: [StoredReserveRow] = []

    var writeRateError: Error?
    var writeReserveError: Error?

    func allRates() throws -> [StoredRateRow] {
        lock.lock(); defer { lock.unlock() }
        return Array(rates.values)
    }

    func allReserves() throws -> [StoredReserveRow] {
        lock.lock(); defer { lock.unlock() }
        return Array(reserves.values)
    }

    func writeRate(_ row: StoredRateRow) throws {
        if let writeRateError { throw writeRateError }
        lock.lock(); defer { lock.unlock() }
        rates[row.currency] = row
        writeRateCalls.append(row)
    }

    func writeReserve(_ row: StoredReserveRow) throws {
        if let writeReserveError { throw writeReserveError }
        lock.lock(); defer { lock.unlock() }
        reserves[row.mint] = row
        writeReserveCalls.append(row)
    }
}
