//
//  Database+Limits.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {

    // MARK: - Get -

    func getLimits() throws -> Limits? {
        try getSingleton(Limits.self, in: LimitsTable())
    }

    // MARK: - Insert -

    func insertLimits(_ limits: Limits) throws {
        try upsertSingleton(limits, in: LimitsTable())
    }
}
