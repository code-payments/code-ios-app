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
    
    func getActivities() throws -> [Activity] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            a.id,
            a.kind,
            a.state,
            a.title,
            a.quarks,
            a.nativeAmount,
            a.currency,
            a.date,
            
            c.vault,
            c.canCancel
            
        FROM activity a
        
        LEFT JOIN cashLinkMetadata c ON c.id = a.id
        
        ORDER BY a.date DESC
        LIMIT 1024;
        """)
        
        let aTable = ActivityTable()
        
        let activities = try statement.map { row in
            let kind = Activity.Kind(rawValue: row[aTable.kind])!
            return Activity.init(
                id: row[aTable.id],
                state: .init(rawValue: row[aTable.state]) ?? .unknown,
                kind: kind,
                title: row[aTable.title],
                exchangedFiat: ExchangedFiat(
                    usdc: Fiat(quarks: row[aTable.quarks], currencyCode: .usd),
                    converted: try Fiat(
                        fiatDecimal: Decimal(row[aTable.nativeAmount]),
                        currencyCode: row[aTable.currency]
                    )
                ),
                date: row[aTable.date],
                metadata: metadata(for: kind, row: row)
            )
        }
        
        return activities
    }
    
    private func metadata(for kind: Activity.Kind, row: RowIterator.Element) -> Activity.Metadata? {
        switch kind {
        case .welcomeBonus, .gave, .received, .withdrew, .deposited, .unknown:
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
                table.quarks       <- activity.exchangedFiat.usdc.quarks,
                table.nativeAmount <- activity.exchangedFiat.converted.doubleValue,
                table.currency     <- activity.exchangedFiat.converted.currencyCode,
                table.date         <- activity.date,
                
                onConflictOf: table.id,
            )
        )
        
        switch activity.kind {
        case .welcomeBonus, .gave, .received, .withdrew, .deposited, .unknown:
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
