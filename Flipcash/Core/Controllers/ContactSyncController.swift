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
    @ObservationIgnored private var joinObserverTask: Task<Void, Never>?
    @ObservationIgnored private var needsResync = false

    /// Resolved directory cache surfaced to the picker. Updated after every
    /// successful sync; consumers observe it and re-render on changes.
    private(set) var resolvedContacts: ResolvedContacts = .empty

    /// `true` once the first sync attempt has settled the directory — success
    /// or failure — and never resets. Distinguishes "the first sync is still
    /// in flight" from "a sync settled and found nothing".
    private(set) var hasResolvedOnce: Bool = false

    /// `true` when the picker has something definitive to show: contacts are
    /// present, or the first sync has settled so an empty result is
    /// authoritative (not merely "not loaded yet").
    var isDirectoryReady: Bool {
        hasResolvedOnce || !resolvedContacts.isEmpty
    }

    /// Set once, during the user's first contact scan, to the number of the
    /// user's contacts the server matched. `SendRootScreen` forwards it to
    /// `session.dialogItem` — surfaced above the Send sheet by `DialogWindow` —
    /// then clears it. Gated on the first sync (no prior checksum) so it never
    /// re-fires on later syncs or screen opens.
    var onFlipcashMatchCount: Int?

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
        self.client                      = client
        self.database                    = database
        self.owner                       = owner
        self.authorizationStatusProvider = authorizationStatusProvider
    }

    deinit {
        syncTask?.cancel()
        observerTask?.cancel()
        joinObserverTask?.cancel()
    }

    // MARK: - Lifecycle -

    /// Idempotent. Registers the CN-change observer and triggers a sync.
    /// Caller must verify the contacts authorization status allows access
    /// (`.authorized` or `.limited`) before calling — this method does not
    /// prompt.
    func activate() {
        if observerTask == nil {
            // Detached: subscribing to `CNContactStoreDidChange` on the main
            // actor warns on first invocation.
            observerTask = Task.detached { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .CNContactStoreDidChange) {
                    guard let self else { return }
                    await MainActor.run { self.sync() }
                }
            }
        }
        if joinObserverTask == nil {
            // A peer joining doesn't change our uploaded set, so `sync()` would no-op.
            joinObserverTask = Task.detached { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .contactDidJoinReceived) {
                    guard let self else { return }
                    await self.refreshMatchedSet()
                }
            }
        }
        // Surface cached contacts before the network sync so an offline relaunch
        // renders immediately instead of spinning.
        if !hasResolvedOnce {
            Task { [weak self] in await self?.resolveDirectory() }
        }
        sync()
    }

    /// Detects a contacts-permission revoke and, independently, triggers a sync
    /// when activated.
    ///
    /// The revoke check runs even before ``activate()`` — a set uploaded in a
    /// prior session must still be wiped after a cold launch while access is
    /// denied. It is cheap when nothing was ever uploaded: it reads the stored
    /// status and short-circuits without touching the Contacts store. The sync
    /// remains a no-op until ``activate()`` has registered the observer.
    nonisolated func didBecomeActive() {
        // Detached so the nonisolated revoke check stays off-main under SE-0461.
        Task.detached { [weak self] in
            await self?.clearServerContactSetIfRevoked()
            await MainActor.run { [weak self] in
                guard let self, self.observerTask != nil else { return }
                self.sync()
            }
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
        // Detached: SE-0461 runs nonisolated async on the caller's actor;
        // `Task.detached` breaks that so `runSync` stays off-main.
        syncTask = Task.detached { [weak self] in
            await self?.runSync()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isSyncing = false
                self.syncTask = nil
                // A finished attempt — success or failure — is a definitive
                // result. Mark resolved so the picker leaves its loading state
                // even when nothing matched or the sync failed, rather than
                // spinning forever.
                self.hasResolvedOnce = true
                if self.needsResync {
                    self.needsResync = false
                    self.sync()
                }
            }
        }
    }

    /// Callers must spawn this via `Task.detached`; under SE-0461 the
    /// `nonisolated` annotation alone is not enough to keep it off-main.
    nonisolated private func runSync() async {
        let status = authorizationStatusProvider()
        guard status.allowsContactAccess else {
            logger.debug("Skipping sync — contacts not accessible", metadata: [
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
        // No prior checksum means this is the user's first scan — the only time
        // the "already on Flipcash" dialog is allowed to fire.
        let isFirstScan = storedState.checksum == nil
        // The snapshot stores every `(e164, contactId)` pair so the picker
        // can show each contact with each of their phone numbers. Upload
        // + checksum operate on the unique e164 set — the server doesn't
        // care which addr-book contacts a phone is on. Preserve first-seen
        // order so the upload payload is deterministic across runs.
        var seenPhones: Set<String> = []
        let phones      = contacts.map(\.e164).filter { seenPhones.insert($0).inserted }
        let newChecksum = Self.checksum(of: phones)

        var serverDrifted = false
        if let storedChecksum = storedState.checksum, storedChecksum == newChecksum {
            let result = try await client.checkContactSync(
                checksum: storedChecksum,
                owner:    ownerKeyPair
            )
            switch result {
            case .ok:
                // A contact may have joined without changing our checksum.
                logger.info("Local set unchanged, server agrees — refreshing matched set")
                try await refreshFlipcashContacts(checksum: storedChecksum)
                await resolveDirectory()
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
                var seenSnapshot: Set<String> = []
                let snapshotPhones = snapshot.map(\.e164).filter { seenSnapshot.insert($0).inserted }
                let (adds, removes) = Self.delta(
                    oldSnapshot: snapshotPhones,
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
            state: .init(checksum: newChecksum)
        )

        await resolveDirectory()

        if isFirstScan, let matched = try? database.flipcashContacts(), !matched.isEmpty {
            await MainActor.run { self.onFlipcashMatchCount = matched.count }
        }
    }

    /// Re-pulls the server's matched set and re-resolves the picker without
    /// re-uploading the local address book. Triggered by a CONTACT_JOIN push so
    /// a peer who just joined reclassifies to "On Flipcash" live. No-op until a
    /// prior sync has produced a checksum.
    internal nonisolated func refreshMatchedSet() async {
        do {
            guard let checksum = try database.contactSyncState().checksum else { return }
            try await refreshFlipcashContacts(checksum: checksum)
            await resolveDirectory()
        } catch is CancellationError {
            return
        } catch {
            logger.error("Matched-set refresh failed", metadata: ["error": "\(error)"])
        }
    }

    // MARK: - Directory resolution -

    /// Re-resolve the picker's display data from the freshly-persisted
    /// snapshot. Safe to call from any actor — the load itself is detached
    /// and the observable updates hop back to main.
    nonisolated func resolveDirectory() async {
        let resolved = await RecipientLoader.load(database: database)
        await MainActor.run {
            self.resolvedContacts = resolved
        }
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

    // MARK: - Permission revoke -

    /// Wipes the server's stored contact set when contacts access is now
    /// denied/restricted for a user who had previously uploaded one.
    ///
    /// A non-nil checksum only exists after a sync, which only runs while
    /// authorized, so it doubles as the "we previously had access" marker.
    /// Idempotent: a successful wipe nulls the checksum; a failure leaves it
    /// intact so the next foreground retries.
    internal nonisolated func clearServerContactSetIfRevoked() async {
        let hadServerSet: Bool
        do {
            hadServerSet = try database.contactSyncState().checksum != nil
        } catch {
            logger.error("Clear-on-revoke aborted — could not read sync state", metadata: [
                "error": "\(error)",
            ])
            return
        }
        guard hadServerSet else { return }

        // `.limited` is a narrower grant, not a revoke; `.notDetermined` is an
        // OS-level reset we don't wipe on. Switched exhaustively so a new
        // `CNAuthorizationStatus` case forces a decision.
        let isRevoked = switch authorizationStatusProvider() {
        case .denied, .restricted: true
        case .notDetermined, .authorized, .limited: false
        @unknown default: false
        }
        guard isRevoked else { return }

        do {
            try await clearServerContactSet()
            logger.info("Cleared server contact set after permission revoke")
        } catch {
            logger.info("Clear-on-revoke deferred — will retry next foreground", metadata: [
                "error": "\(error)",
            ])
        }
    }

    /// Wipes the server's stored contact set as part of account deletion.
    /// Best-effort: deletion proceeds even if the wipe fails — there's no
    /// retry once the session tears down. No-ops when nothing was uploaded.
    ///
    /// `@concurrent` keeps it off-main when awaited from the `@MainActor`
    /// delete-account flow, which SE-0461 would otherwise inherit.
    @concurrent internal func clearServerContactSetForAccountDeletion() async {
        let hadServerSet: Bool
        do {
            hadServerSet = try database.contactSyncState().checksum != nil
        } catch {
            logger.error("Account-deletion contact wipe aborted — could not read sync state", metadata: [
                "error": "\(error)",
            ])
            return
        }
        guard hadServerSet else { return }

        do {
            try await clearServerContactSet()
            logger.info("Cleared server contact set for account deletion")
        } catch {
            logger.info("Account-deletion contact wipe failed — best effort", metadata: [
                "error": "\(error)",
            ])
        }
    }

    /// Empties the server's stored set via a `phones: []` full upload (no
    /// dedicated RPC) and drains the local contact tables + picker cache.
    /// Writes the checksum-bearing sync state last so a mid-drain failure
    /// leaves `checksum != nil` and the next foreground re-runs the full wipe.
    private nonisolated func clearServerContactSet() async throws {
        try await client.uploadAllContacts(
            phones:   [],
            checksum: Self.checksum(of: []),
            owner:    ownerKeyPair
        )
        try database.replaceLocalContactsSnapshot([])
        try database.replaceFlipcashContacts([], matchedAt: .now)
        try database.setContactSyncState(.empty)
        await MainActor.run {
            self.resolvedContacts = .empty
        }
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

    /// Parses each raw number against `region`, normalizes to E.164, and
    /// keeps every `(e164, contactId)` pair so the picker can show each
    /// contact with each of their phone numbers, and a phone shared
    /// across contacts shows once per contact name. Dedupe is on the
    /// tuple — same pair seen twice (e.g. a label-duplicated entry on
    /// one card) collapses to a single row.
    nonisolated static func normalizeContacts(
        rawNumbers: [(raw: String, contactId: String)],
        region: Region
    ) -> [Database.LocalContact] {
        var seen:   Set<Database.LocalContact> = []
        var locals: [Database.LocalContact] = []
        for entry in rawNumbers {
            guard let phone = Phone(entry.raw, defaultRegion: region) else { continue }
            let local = Database.LocalContact(e164: phone.e164, contactId: entry.contactId)
            if seen.insert(local).inserted {
                locals.append(local)
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
            logger.info("Sync completed with no matched contacts")
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
