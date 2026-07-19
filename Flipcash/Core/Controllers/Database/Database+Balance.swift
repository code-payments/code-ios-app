//
//  Database+Balance.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore
import SQLite

nonisolated private let logger = Logger(label: "flipcash.database")

nonisolated extension Database {
    
    // MARK: - Get -
    
    func getBalances() throws -> [StoredBalance] {
        let statement = try reader.prepareRowIterator("""
        SELECT
            b.quarks,
            b.mint,
            b.costBasis,
            b.updatedAt,

            m.symbol,
            m.name,
            m.imageURL,
            m.sellFeeBps,
            m.supplyFromBonding,
            m.vmAuthority
        FROM
            balance b

        LEFT JOIN mint m ON m.mint = b.mint

        ORDER BY b.quarks;
        """)
        
        let b = BalanceTable()
        let m = MintTable()
        
        let balances = try statement.map { row in
            try StoredBalance(
                quarks:            row[b.quarks],
                symbol:            row[m.symbol],
                name:              row[m.name],
                supplyFromBonding: row[m.supplyFromBonding],
                sellFeeBps:        row[m.sellFeeBps],
                mint:              row[b.mint],
                vmAuthority:       row[m.vmAuthority],
                updatedAt:         row[b.updatedAt],
                imageURL:          row[m.imageURL],
                costBasis:         row[b.costBasis] ?? 0
            )
        }
        
        return balances
    }
    
    func getMintMetadata(mint: PublicKey) throws -> StoredMintMetadata? {
        let stored = try fetchStoredMint(mint)
        if stored == nil {
            logger.warning("Missing mint in database", metadata: ["mint": "\(mint.base58)"])
        }
        return stored
    }

    /// Row lookup without the missing-row warning — for callers where
    /// absence is an expected case (e.g. the upsert's write gate).
    private func fetchStoredMint(_ mint: PublicKey) throws -> StoredMintMetadata? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            m.mint,
            m.name,
            m.symbol,
            m.decimals,
            m.bio,
            m.imageURL,
            m.vmAddress,
            m.vmAuthority,
            m.lockDuration,
            m.currencyConfig,
            m.liquidityPool,
            m.seed,
            m.authority,
            m.mintVault,
            m.coreMintVault,
            m.coreMintFees,
            m.supplyFromBonding,
            m.sellFeeBps,
            m.socialLinks,
            m.billColors,
            m.createdAt,
            m.updatedAt
        FROM
            mint m
        WHERE
            m.mint = ?
        LIMIT 1;
        """, bindings: Blob(bytes: mint.bytes))

        let m = MintTable()

        let mints = try statement.compactMap { row in
            StoredMintMetadata(
                mint:              row[m.mint],
                name:              row[m.name],
                symbol:            row[m.symbol],
                decimals:          row[m.decimals],
                bio:               row[m.bio],
                imageURL:          row[m.imageURL],
                vmAddress:         row[m.vmAddress],
                vmAuthority:       row[m.vmAuthority],
                lockDuration:      row[m.lockDuration],
                currencyConfig:    row[m.currencyConfig],
                liquidityPool:     row[m.liquidityPool],
                seed:              row[m.seed],
                authority:         row[m.authority],
                mintVault:         row[m.mintVault],
                coreMintVault:     row[m.coreMintVault],
                coreMintFees:      row[m.coreMintFees],
                supplyFromBonding: row[m.supplyFromBonding],
                sellFeeBps:        row[m.sellFeeBps],
                socialLinks:       row[m.socialLinks],
                billColors:        row[m.billColors],
                createdAt:         row[m.createdAt],
                updatedAt:         row[m.updatedAt]
            )
        }

        return mints.first
    }
    
    func getVMAuthority(mint: PublicKey) throws -> PublicKey? {
        let statement = try reader.prepareRowIterator("""
        SELECT
            m.vmAuthority
        FROM
            mint m
        WHERE
            m.mint = ?
        LIMIT 1;
        """, bindings: Blob(bytes: mint.bytes))
        
        let m = MintTable()
        
        let authority = try statement.compactMap { row in
            row[m.vmAuthority]
        }.first
        
        return authority
    }
    
    // MARK: - Live Supply -

    func updateLiveSupply(updates: [ReserveStateUpdate], date: Date) throws {
        try transaction {
            let table = MintTable()
            for update in updates {
                // Only touch rows whose supply actually moved — a re-delivered
                // identical supply must not count as a change, or every stream
                // tick posts `.databaseDidChange` and re-renders every
                // database-driven screen. NULL is always a change.
                let row = table.table.filter(
                    table.mint == update.mint &&
                    (table.supplyFromBonding == nil || table.supplyFromBonding != update.supplyFromBonding)
                )
                try $0.writer.run(
                    row.update(
                        table.supplyFromBonding <- update.supplyFromBonding,
                        table.updatedAt         <- date
                    )
                )
            }
        }
    }

    // MARK: - Insert -
    
    func insertBalance(quarks: UInt64, mint: PublicKey, costBasis: Double, date: Date) throws {
        let table = BalanceTable()
        // The filter becomes the DO UPDATE's WHERE clause (fork behavior —
        // see "SQLite.swift Fork" in CLAUDE.md): a conflicting row only
        // rewrites when a value actually changed, so the balance poller's
        // unchanged upserts stop counting as changes and stop posting
        // `.databaseDidChange`. Fresh inserts are unaffected.
        try writer.run(
            table.table
                .filter(table.quarks != quarks || table.costBasis != costBasis)
                .upsert(
                    table.mint      <- mint,
                    table.quarks    <- quarks,
                    table.costBasis <- costBasis,
                    table.updatedAt <- date,

                    onConflictOf: table.mint,
                )
        )
    }

    func insert(mints: [MintMetadata], date: Date) throws {
        try transaction {
            for mint in mints {
                try $0.insert(mint: mint, date: date)
            }
        }
    }

    private func insert(mint: MintMetadata, date: Date) throws {
        let table = MintTable()

        let socialLinksJSON: String? = {
            guard !mint.socialLinks.isEmpty else { return nil }
            guard let data = try? JSONEncoder().encode(mint.socialLinks) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        let billColorsJSON: String? = {
            guard !mint.billColors.isEmpty else { return nil }
            guard let data = try? JSONEncoder().encode(mint.billColors) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        // Skip the write when it wouldn't change the stored row (updatedAt
        // aside). The balance poller re-fetches held mints every cycle;
        // letting identical data count as a change turns every poll into a
        // `.databaseDidChange` broadcast that re-renders every
        // database-driven screen.
        if let stored = try? fetchStoredMint(mint.address),
           storedRowUnchanged(stored, by: mint, socialLinksJSON: socialLinksJSON, billColorsJSON: billColorsJSON) {
            return
        }

        // TODO: Collapse into a single statement with COALESCE(excluded.supplyFromBonding,
        // supplyFromBonding) once Setter(excluded:) is made public in our SQLite.swift fork.
        // See CLAUDE.md "SQLite.swift Fork" for details.
        try writer.run(
            table.table.upsert(
                table.mint              <- mint.address,
                table.name              <- mint.name,
                table.symbol            <- mint.symbol,
                table.decimals          <- mint.decimals,
                table.bio               <- mint.description,
                table.imageURL          <- mint.imageURL,

                table.vmAddress         <- mint.vmMetadata?.vm,
                table.vmAuthority       <- mint.vmMetadata?.authority,
                table.lockDuration      <- mint.vmMetadata?.lockDurationInDays,

                table.currencyConfig    <- mint.launchpadMetadata?.currencyConfig,
                table.liquidityPool     <- mint.launchpadMetadata?.liquidityPool,
                table.seed              <- mint.launchpadMetadata?.seed,
                table.authority         <- mint.launchpadMetadata?.authority,
                table.mintVault         <- mint.launchpadMetadata?.mintVault,
                table.coreMintVault     <- mint.launchpadMetadata?.coreMintVault,
                table.coreMintFees      <- mint.launchpadMetadata?.coreMintFees,
                table.sellFeeBps        <- mint.launchpadMetadata?.sellFeeBps,

                table.socialLinks       <- socialLinksJSON,
                table.billColors        <- billColorsJSON,

                table.createdAt         <- mint.createdAt,

                table.updatedAt         <- date,

                onConflictOf: table.mint,
            )
        )

        if let supplyFromBonding = mint.launchpadMetadata?.supplyFromBonding {
            let row = table.table.filter(table.mint == mint.address)
            try writer.run(
                row.update(table.supplyFromBonding <- supplyFromBonding)
            )
        }
    }

    /// Whether upserting `mint` would leave `stored` unchanged (updatedAt
    /// aside). Mirrors the SET clause above, including the supply rule: the
    /// trailing supplyFromBonding update only runs when the incoming
    /// metadata carries one.
    private func storedRowUnchanged(
        _ stored: StoredMintMetadata,
        by mint: MintMetadata,
        socialLinksJSON: String?,
        billColorsJSON: String?
    ) -> Bool {
        stored.name == mint.name &&
        stored.symbol == mint.symbol &&
        stored.decimals == mint.decimals &&
        stored.bio == mint.description &&
        stored.imageURL == mint.imageURL &&
        stored.vmAddress == mint.vmMetadata?.vm &&
        stored.vmAuthority == mint.vmMetadata?.authority &&
        stored.lockDuration == mint.vmMetadata?.lockDurationInDays &&
        stored.currencyConfig == mint.launchpadMetadata?.currencyConfig &&
        stored.liquidityPool == mint.launchpadMetadata?.liquidityPool &&
        stored.seed == mint.launchpadMetadata?.seed &&
        stored.authority == mint.launchpadMetadata?.authority &&
        stored.mintVault == mint.launchpadMetadata?.mintVault &&
        stored.coreMintVault == mint.launchpadMetadata?.coreMintVault &&
        stored.coreMintFees == mint.launchpadMetadata?.coreMintFees &&
        stored.sellFeeBps == mint.launchpadMetadata?.sellFeeBps &&
        stored.socialLinks == socialLinksJSON &&
        stored.billColors == billColorsJSON &&
        sameStoredDate(stored.createdAt, mint.createdAt) &&
        (mint.launchpadMetadata?.supplyFromBonding == nil ||
         stored.supplyFromBonding == mint.launchpadMetadata?.supplyFromBonding)
    }

    /// Compares dates in the DB's storage form (`Date.datatypeValue`, the
    /// exact string SQLite persists) — a fresh server date with
    /// sub-millisecond fraction never compares `==` to its round-tripped copy.
    private func sameStoredDate(_ lhs: Date?, _ rhs: Date?) -> Bool {
        lhs.map(\.datatypeValue) == rhs.map(\.datatypeValue)
    }
}
