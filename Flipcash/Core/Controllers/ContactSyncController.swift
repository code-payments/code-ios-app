//
//  ContactSyncController.swift
//  Flipcash
//

import Contacts
import Foundation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.contact-sync-controller")

/// Synchronizes the local address book with the server's contact-match service.
///
/// Dormant at construction. ``activate()`` registers the CN-change observer
/// and triggers the first sync; ``didBecomeActive()`` is a no-op until that
/// happens. Callers MUST verify contact authorization before invoking
/// ``activate()`` — this type never prompts.
///
/// Inject via `@Environment(ContactSyncController.self)`.
@Observable
final class ContactSyncController {

    @ObservationIgnored nonisolated private let client: any ContactSyncing
    @ObservationIgnored nonisolated private let database: Database
    @ObservationIgnored nonisolated private let owner: AccountCluster
    @ObservationIgnored nonisolated private let authorizationStatusProvider: @Sendable () -> CNAuthorizationStatus

    @ObservationIgnored internal private(set) var isSyncing = false
    @ObservationIgnored internal private(set) var syncTask: Task<Void, Never>?
    @ObservationIgnored internal private(set) var observerTask: Task<Void, Never>?
    @ObservationIgnored private var needsResync = false

    nonisolated private var ownerKeyPair: KeyPair {
        owner.authority.keyPair
    }

    // MARK: - Init -

    init(
        client: any ContactSyncing,
        database: Database,
        owner: AccountCluster,
        authorizationStatusProvider: @escaping @Sendable () -> CNAuthorizationStatus = {
            CNContactStore.authorizationStatus(for: .contacts)
        }
    ) {
        self.client                       = client
        self.database                     = database
        self.owner                        = owner
        self.authorizationStatusProvider  = authorizationStatusProvider
    }

    deinit {
        syncTask?.cancel()
        observerTask?.cancel()
    }

    // MARK: - Lifecycle -

    /// Idempotent. Registers the CN-change observer and triggers a sync.
    /// Caller must verify `CNContactStore.authorizationStatus(for: .contacts)
    /// == .authorized` before calling — this method does not prompt.
    func activate() {
        if observerTask == nil {
            observerTask = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .CNContactStoreDidChange) {
                    guard let self else { return }
                    self.sync()
                }
            }
        }
        sync()
    }

    /// No-op until ``activate()`` has been called this session.
    nonisolated func didBecomeActive() {
        Task { @MainActor [weak self] in
            guard let self, self.observerTask != nil else { return }
            self.sync()
        }
    }

    // MARK: - Sync -

    /// Coalesces an in-flight trigger via `needsResync`; the completion block
    /// re-fires once the current sync finishes.
    func sync() {
        guard !isSyncing else {
            needsResync = true
            logger.debug("Sync already in flight — coalescing trigger")
            return
        }
        isSyncing = true
        needsResync = false
        syncTask = Task { [weak self] in
            await self?.runSync()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isSyncing = false
                self.syncTask = nil
                if self.needsResync {
                    self.needsResync = false
                    self.sync()
                }
            }
        }
    }

    /// `nonisolated` so the heavy work (CN enumeration, SQLite I/O, RPCs)
    /// runs off the main actor — do NOT drop the annotation.
    nonisolated private func runSync() async {
        let status = authorizationStatusProvider()
        guard status == .authorized else {
            logger.debug("Skipping sync — contacts not authorized", metadata: [
                "status": "\(status.rawValue)",
            ])
            return
        }
        do {
            let contacts = try readContacts()
            try await performSync(contacts: contacts)
        } catch let error as ErrorContactSync {
            await handleSyncError(error)
        } catch is CancellationError {
            return
        } catch {
            logger.error("Sync failed with unexpected error", metadata: [
                "error": "\(error)",
            ])
            await reportError(error, reason: "Contact sync failed")
        }
    }

    /// `internal` for testing — also `nonisolated` so off-main isolation is
    /// preserved when called through the production `runSync` path.
    internal nonisolated func performSync(contacts: [Database.LocalContact]) async throws {
        let storedState = try database.contactSyncState()
        let phones      = contacts.map(\.e164)
        let newChecksum = Self.checksum(of: phones)

        var serverDrifted = false
        if let storedChecksum = storedState.checksum, storedChecksum == newChecksum {
            let result = try await client.checkContactSync(
                checksum: storedChecksum,
                owner:    ownerKeyPair
            )
            switch result {
            case .ok:
                logger.info("Sync skipped — local unchanged, server agrees")
                return
            case .outOfSync:
                serverDrifted = true
                logger.info("Server reported drift on idle probe — uploading full set")
            }
        }

        if serverDrifted {
            try await uploadFull(phones: phones, checksum: newChecksum)
        } else if let oldChecksum = storedState.checksum {
            let snapshot = try database.localContactsSnapshot()
            if snapshot.isEmpty {
                try await uploadFull(phones: phones, checksum: newChecksum)
            } else {
                let (adds, removes) = Self.delta(
                    oldSnapshot: snapshot.map(\.e164),
                    newContacts: phones
                )
                let result = try await client.uploadContactDelta(
                    adds:        adds,
                    removes:     removes,
                    oldChecksum: oldChecksum,
                    newChecksum: newChecksum,
                    owner:       ownerKeyPair
                )
                switch result {
                case .ok:
                    logger.info("Delta upload OK", metadata: [
                        "adds":    "\(adds.count)",
                        "removes": "\(removes.count)",
                    ])
                case .checksumDrift:
                    logger.warning("Delta upload reported checksumDrift — falling back to full upload")
                    try await uploadFull(phones: phones, checksum: newChecksum)
                }
            }
        } else {
            try await uploadFull(phones: phones, checksum: newChecksum)
        }

        // Refresh before persist so a stream failure leaves checksum + snapshot
        // unchanged and the next sync re-runs end-to-end.
        try await refreshFlipcashContacts(checksum: newChecksum)

        try database.updateContactSyncSnapshotAndState(
            snapshot: contacts,
            state: .init(
                checksum:      newChecksum,
                changeHistory: nil,
                lastSyncedAt:  .now
            )
        )
    }

    nonisolated private func uploadFull(phones: [String], checksum: Data) async throws {
        try await client.uploadAllContacts(
            phones:   phones,
            checksum: checksum,
            owner:    ownerKeyPair
        )
        logger.info("Full upload OK", metadata: ["count": "\(phones.count)"])
    }

    nonisolated private func refreshFlipcashContacts(checksum: Data) async throws {
        // FlipClient is @MainActor and streamFlipcashContacts is sync — hop to
        // obtain the stream, iterate off-main.
        let stream = await MainActor.run {
            client.streamFlipcashContacts(checksum: checksum, owner: ownerKeyPair)
        }
        var matched: [String] = []
        for try await e164 in stream {
            matched.append(e164)
        }
        try database.replaceFlipcashContacts(matched, matchedAt: .now)
        logger.info("Refreshed flipcash contacts", metadata: ["matched": "\(matched.count)"])
    }

    // MARK: - Address book -

    nonisolated private func readContacts() throws -> [Database.LocalContact] {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: [
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactIdentifierKey   as CNKeyDescriptor,
        ])

        var rawNumbers: [(raw: String, contactId: String)] = []
        try store.enumerateContacts(with: request) { contact, _ in
            for labelled in contact.phoneNumbers {
                rawNumbers.append((labelled.value.stringValue, contact.identifier))
            }
        }

        return Self.normalizeContacts(rawNumbers: rawNumbers, region: Region.current ?? .us)
    }

    /// Parses each raw number against `region`, normalizes to E.164, dedupes
    /// keeping the first occurrence's `contactId`.
    nonisolated static func normalizeContacts(
        rawNumbers: [(raw: String, contactId: String)],
        region: Region
    ) -> [Database.LocalContact] {
        var seen:   Set<String> = []
        var locals: [Database.LocalContact] = []
        for entry in rawNumbers {
            guard let phone = Phone(entry.raw, defaultRegion: region) else { continue }
            if seen.insert(phone.e164).inserted {
                locals.append(.init(e164: phone.e164, contactId: entry.contactId))
            }
        }
        return locals
    }

    // MARK: - Pure helpers -

    /// 32-byte XOR-of-SHA256 over E.164 strings. Order-independent.
    nonisolated static func checksum(of phones: [String]) -> Data {
        var acc = [UInt8](repeating: 0, count: 32)
        for phone in phones {
            let hash = SHA256.digest(phone)
            for (i, byte) in hash.enumerated() {
                acc[i] ^= byte
            }
        }
        return Data(acc)
    }

    /// Adds/removes between an old snapshot and a new contact list, sorted.
    nonisolated static func delta(oldSnapshot: [String], newContacts: [String]) -> (adds: [String], removes: [String]) {
        let oldSet = Set(oldSnapshot)
        let newSet = Set(newContacts)
        return (
            adds:    Array(newSet.subtracting(oldSet)).sorted(),
            removes: Array(oldSet.subtracting(newSet)).sorted()
        )
    }

    // MARK: - Error handling -

    nonisolated private func handleSyncError(_ error: ErrorContactSync) async {
        switch error {
        case .ok:
            return
        case .networkError:
            logger.info("Sync deferred — network error (will retry on next trigger)")
        case .checksumDrift:
            logger.info("Sync deferred — checksum drift (will retry on next trigger)")
        case .checksumMismatch:
            logger.error("Sync failed — checksumMismatch (algorithm divergence)")
            await reportError(error, reason: "Contact sync checksum mismatch")
        case .denied:
            logger.warning("Sync stopped — user not registered as Flipcash")
        case .tooManyContacts:
            logger.warning("Sync stopped — contact count exceeds server cap")
        case .notFound:
            logger.error("Sync failed — phone not found")
            await reportError(error, reason: "Contact sync NOT_FOUND")
        case .unknown:
            logger.error("Sync failed — unknown error")
            await reportError(error, reason: "Contact sync unknown error")
        }
    }

    nonisolated private func reportError(_ error: Error, reason: String) async {
        await MainActor.run {
            ErrorReporting.captureError(error, reason: reason)
        }
    }
}
