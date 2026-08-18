//
//  Database+Activities.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {
    
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
    func getActivities(mint: PublicKey) async throws -> [Activity] {
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

    func getActivities(mint: PublicKey) throws -> [Activity] {
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
            a.counterpartyUserID,
            a.counterpartyPhone,

            c.vault,
            c.canCancel,

            s.fromMint,
            s.fromQuarks,
            s.fromNativeAmount,
            s.fromCurrency,
            s.toMint,
            s.toQuarks,
            s.toNativeAmount,
            s.toCurrency,
            s.feeNativeAmount,
            s.feeCurrency,
            s.state AS swapState

        FROM activity a

        LEFT JOIN cashLinkMetadata c ON c.id = a.id
        LEFT JOIN swapMetadata s ON s.id = a.id

        WHERE a.mint = ?

        ORDER BY a.date DESC
        LIMIT 1024;
        """, bindings: Blob(bytes: mint.bytes))
        
        return try statement.map(makeActivity)
    }

    /// The unified, cross-mint recent activity for the wallet preview: the newest
    /// `limit` activities regardless of token. `getActivities(mint:)` is the
    /// per-token slice; this is the "everything" feed.
    func getRecentActivities(limit: Int) throws -> [Activity] {
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
            a.counterpartyUserID,
            a.counterpartyPhone,

            c.vault,
            c.canCancel,

            s.fromMint,
            s.fromQuarks,
            s.fromNativeAmount,
            s.fromCurrency,
            s.toMint,
            s.toQuarks,
            s.toNativeAmount,
            s.toCurrency,
            s.feeNativeAmount,
            s.feeCurrency,
            s.state AS swapState

        FROM activity a

        LEFT JOIN cashLinkMetadata c ON c.id = a.id
        LEFT JOIN swapMetadata s ON s.id = a.id

        ORDER BY a.date DESC
        LIMIT ?;
        """, bindings: limit)

        return try statement.map(makeActivity)
    }

    /// Maps a joined activity row into an ``Activity``. Shared by the per-mint
    /// and cross-mint queries, which select the same columns.
    private func makeActivity(_ row: RowIterator.Element) -> Activity {
        let a = ActivityTable()
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
        return Activity(
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
            metadata: metadata(for: kind, row: row),
            counterparty: Activity.Counterparty(userID: row[a.counterpartyUserID], phone: row[a.counterpartyPhone])
        )
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
        case .swapped:
            return swapMetadata(from: row)
        }
    }

    /// Reads the joined `swapMetadata` columns. A `.swapped` row should always
    /// have a match, but the reads are optional so a legacy/un-persisted swap
    /// degrades to no metadata instead of trapping on a NULL column. `s.state` is
    /// aliased to `swapState` in the SELECT to avoid colliding with `a.state`.
    private func swapMetadata(from row: RowIterator.Element) -> Activity.Metadata? {
        guard
            let fromMint   = row[Expression<PublicKey?>("fromMint")],
            let fromQuarks = row[Expression<UInt64?>("fromQuarks")],
            let fromNative = row[Expression<Double?>("fromNativeAmount")],
            let fromCurr   = row[Expression<CurrencyCode?>("fromCurrency")],
            let toMint     = row[Expression<PublicKey?>("toMint")],
            let feeNative  = row[Expression<Double?>("feeNativeAmount")],
            let feeCurr    = row[Expression<CurrencyCode?>("feeCurrency")]
        else {
            return nil
        }

        let toFiat: FiatAmount?
        if let toNative = row[Expression<Double?>("toNativeAmount")],
           let toCurr = row[Expression<CurrencyCode?>("toCurrency")] {
            toFiat = FiatAmount(value: Decimal(toNative), currency: toCurr)
        } else {
            toFiat = nil
        }

        return .swap(
            Activity.SwapMetadata(
                fromMint: fromMint,
                fromQuarks: fromQuarks,
                fromFiat: FiatAmount(value: Decimal(fromNative), currency: fromCurr),
                toMint: toMint,
                toQuarks: row[Expression<UInt64?>("toQuarks")],
                toFiat: toFiat,
                fee: FiatAmount(value: Decimal(feeNative), currency: feeCurr),
                state: Activity.SwapMetadata.State(rawValue: row[Expression<Int?>("swapState")] ?? 0) ?? .unknown
            )
        )
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
                table.counterpartyUserID <- activity.counterparty?.userID,
                table.counterpartyPhone  <- activity.counterparty?.phone,

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
        case .swapped:
            if case .swap(let metadata) = activity.metadata {
                try insertSwapMetadata(id: activity.id, metadata: metadata)
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

    private func insertSwapMetadata(id: PublicKey, metadata: Activity.SwapMetadata) throws {
        let table = SwapMetadataTable()
        try writer.run(
            table.table.upsert(
                table.id               <- id,
                table.fromMint         <- metadata.fromMint,
                table.fromQuarks       <- metadata.fromQuarks,
                table.fromNativeAmount <- metadata.fromFiat.doubleValue,
                table.fromCurrency     <- metadata.fromFiat.currency,
                table.toMint           <- metadata.toMint,
                table.toQuarks         <- metadata.toQuarks,
                table.toNativeAmount   <- metadata.toFiat?.doubleValue,
                table.toCurrency       <- metadata.toFiat?.currency,
                table.feeNativeAmount  <- metadata.fee.doubleValue,
                table.feeCurrency      <- metadata.fee.currency,
                table.state            <- metadata.state.rawValue,

                onConflictOf: table.id,
            )
        )
    }
}
