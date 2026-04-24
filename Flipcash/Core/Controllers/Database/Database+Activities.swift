//
//  Database+Activities.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
import SQLite

extension Database {
    
    // MARK: - Get -
    
    func getLatestActivityID() throws -> PublicKey? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            a.id
        FROM activity a
        WHERE a.state = 2
        ORDER BY a.date DESC
        LIMIT 1;
        """)
        
        let aTable = ActivityTable()
        
        let ids = try statement.map { row in
            row[aTable.id]
        }
        
        return ids.first
    }
    
    func getPendingActivityIDs() throws -> [PublicKey] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            a.id
        FROM activity a
        WHERE a.state = 1
        ORDER BY a.date DESC;
        """)
        
        let aTable = ActivityTable()
        
        let ids = try statement.map { row in
            row[aTable.id]
        }
        
        return ids
    }
    
    /// Async wrapper that runs the synchronous ``getActivities(mint:)`` off
    /// the main thread. The underlying SQLite.swift `Connection` already
    /// serialises access through its own dispatch queue; this wrapper only
    /// hops off main so the caller's actor isn't blocked on up-to-1024
    /// `NSDateFormatter.dateFromString(_:)` calls.
    func getActivities(mint: PublicKey?) async throws -> [Activity] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let activities = try self.getActivities(mint: mint)
                    continuation.resume(returning: activities)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func getActivities(mint: PublicKey?) throws -> [Activity] {
        
        var filter: String = ""
        var blob: Blob? = nil
        if let mint {
            filter = "WHERE a.mint = ?"
            blob = Blob(bytes: mint.bytes)
        }
        
        let statement = try reader.prepareRowIterator("""
        SELECT
            a.id,
            a.kind,
            a.state,
            a.title,
            a.quarks,
            a.nativeAmount,
            a.currency,
            a.mint,
            a.date,

            c.vault,
            c.canCancel
            
        FROM activity a
        
        LEFT JOIN cashLinkMetadata c ON c.id = a.id
        
        \(filter)
        
        ORDER BY a.date DESC
        LIMIT 1024;
        """, bindings: blob)
        
        let a = ActivityTable()
        
        let activities = try statement.map { row in
            let kind = Activity.Kind(rawValue: row[a.kind])!
            let mint = row[a.mint]
            let currency = row[a.currency]
            let onChain = TokenAmount(quarks: row[a.quarks], mint: mint)
            let nativeAmount = FiatAmount(
                value: Decimal(row[a.nativeAmount]),
                currency: currency,
            )
            // Synthesize the FX rate from the stored amounts. For USDF this is
            // the correct native-per-USD FX; for bonded mints it is a per-token
            // rate (the proto doesn't carry an exchange rate on this surface,
            // and storing one is out of scope for this fix).
            let fx: Decimal = onChain.decimalValue > 0
                ? nativeAmount.value / onChain.decimalValue
                : 1
            return Activity.init(
                id: row[a.id],
                state: .init(rawValue: row[a.state]) ?? .unknown,
                kind: kind,
                title: row[a.title],
                exchangedFiat: ExchangedFiat(
                    onChainAmount: onChain,
                    nativeAmount: nativeAmount,
                    currencyRate: Rate(fx: fx, currency: currency),
                ),
                date: row[a.date],
                metadata: metadata(for: kind, row: row)
            )
        }
        
        return activities
    }
    
    private func metadata(for kind: Activity.Kind, row: RowIterator.Element) -> Activity.Metadata? {
        switch kind {
        case .gave, .received, .withdrew, .deposited, .paid, .distributed, .bought, .sold, .unknown:
            return nil
        case .cashLink:
            let table = CashLinkMetadataTable()
            return .cashLink(
                Activity.CashLinkMetadata(
                    vault:     row[table.vault],
                    canCancel: row[table.canCancel]
                )
            )
        }
    }
    
    // MARK: - Insert -
    
    func insertActivities(activities: [Activity]) throws {
        try activities.forEach {
            try insertActivity(activity: $0)
        }
    }
    
    private func insertActivity(activity: Activity) throws {
        let table = ActivityTable()
        try writer.run(
            table.table.upsert(
                table.id           <- activity.id,
                table.kind         <- activity.kind.rawValue,
                table.state        <- activity.state.rawValue,
                table.title        <- activity.title,
                table.quarks       <- activity.exchangedFiat.onChainAmount.quarks,
                table.nativeAmount <- activity.exchangedFiat.nativeAmount.doubleValue,
                table.currency     <- activity.exchangedFiat.nativeAmount.currency,
                table.mint         <- activity.exchangedFiat.mint,
                table.date         <- activity.date,
                
                onConflictOf: table.id,
            )
        )
        
        switch activity.kind {
        case .gave, .received, .withdrew, .deposited, .paid, .distributed, .bought, .sold, .unknown:
            break
        case .cashLink:
            if case .cashLink(let metadata) = activity.metadata {
                try insertCashLinkMetaData(id: activity.id, metadata: metadata)
            }
        }
    }
    
    private func insertCashLinkMetaData(id: PublicKey, metadata: Activity.CashLinkMetadata) throws {
        let table = CashLinkMetadataTable()
        try writer.run(
            table.table.upsert(
                table.id        <- id,
                table.vault     <- metadata.vault,
                table.canCancel <- metadata.canCancel,
                
                onConflictOf: table.id,
            )
        )
    }
}
