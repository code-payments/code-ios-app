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
    private(set) var writeRateCalls: [[StoredRateRow]] = []
    private(set) var writeReserveCalls: [[StoredReserveRow]] = []

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

    func writeRates(_ rows: [StoredRateRow]) throws {
        lock.lock()
        if let writeRateError {
            lock.unlock()
            throw writeRateError
        }
        defer { lock.unlock() }
        for row in rows {
            rates[row.currency] = row
        }
        writeRateCalls.append(rows)
    }

    func writeReserves(_ rows: [StoredReserveRow]) throws {
        lock.lock()
        if let writeReserveError {
            lock.unlock()
            throw writeReserveError
        }
        defer { lock.unlock() }
        for row in rows {
            reserves[row.mint] = row
        }
        writeReserveCalls.append(rows)
    }
}
