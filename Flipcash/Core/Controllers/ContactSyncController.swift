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
/// State machine, single entry point ``sync()``:
/// 1. Enumerate `CNContactStore`, normalize phones to E.164 (deduped), compute the
///    new checksum.
/// 2. If the new checksum equals the stored one, probe `CheckSync` to detect
///    server drift. If the server agrees, return.
/// 3. Upload — delta vs. the local snapshot (or full on first sync / empty
///    snapshot). On `.checksumDrift`, fall back to full upload in the same call.
/// 4. Persist the new snapshot, checksum, and `lastSyncedAt`.
/// 5. Stream `GetFlipcashContacts` and replace the matched-set table.
///
/// Step 1 lives in ``runSync()`` (it depends on the live `CNContactStore`);
/// Steps 2–5 live in ``performSync(contacts:)`` so tests can drive them with
/// synthetic input.
///
/// **Trigger model — the controller is dormant at construction.** Nothing runs
/// until Phase 4 UI explicitly calls ``activate()``. That call:
/// 1. Registers a `CNContactStoreDidChange` AsyncSequence observer.
/// 2. Kicks off the first ``sync()``.
///
/// ``didBecomeActive()`` (from `AppDelegate.scenePhaseChanged(.active)`) is a
/// no-op until ``activate()`` has been called at least once this session — so
/// cold launches and pre-Send foregrounds do zero contact work. Once Phase 4
/// has activated the controller (the user opened Send with permission
/// granted), subsequent foregrounds trigger ``sync()``.
///
/// **Login gating is structural.** The controller is only constructed inside
/// a logged-in `SessionContainer` (`SessionAuthenticator.createSessionContainer`)
/// and is released on logout via `state = .loggedOut`, so syncing while logged
/// out is structurally impossible.
///
/// **No permission prompt is ever issued from this controller.** The only API
/// that prompts is `CNContactStore.requestAccess(for:)`, which is reachable
/// only via `ContactsAuthorizer.authorize()` from the Phase 4 button. Within
/// `runSync`, `CNContactStore.authorizationStatus(for:)` is read-only and
/// short-circuits when the status is anything but `.authorized`. The CN
/// enumeration call would throw rather than prompt if reached without
/// authorization, but the status gate prevents that.
///
/// **Concurrency.** The class is implicitly `@MainActor` (Flipcash module
/// default) for state coordination (`isSyncing`, `syncTask`, `observerTask`).
/// Heavy work — `CNContactStore.enumerateContacts`, synchronous SQLite I/O,
/// and the server RPCs — runs off the main actor via `@concurrent nonisolated`
/// on ``runSync()``. The `let` dependencies are `nonisolated` so the off-main
/// work can read them without hopping.
///
/// The `change_history` column on `Database.ContactSyncState` is always
/// persisted as `nil`: `CNContactStore.enumeratorForChangeHistoryFetchRequest:`
/// is `NS_SWIFT_UNAVAILABLE` (see `CNContactStore.h`), so the local
/// "did anything change since last cursor" pre-read can't be done from Swift
/// without an Objective-C bridge. Every trigger re-enumerates `CNContactStore`;
/// the upload (and matched-set stream) are still skipped when the new
/// checksum matches.
///
/// Inject via `@Environment(ContactSyncController.self)`.
@Observable
final class ContactSyncController {

    @ObservationIgnored nonisolated private let client: any ContactSyncing
    @ObservationIgnored nonisolated private let database: Database
    @ObservationIgnored nonisolated private let owner: AccountCluster

    /// `internal` (not `private`) so `FlipcashTests` can assert the dropped
    /// trigger / debouncing behavior via `@testable import Flipcash`. Never
    /// written from test code; production callers don't need it.
    @ObservationIgnored internal private(set) var isSyncing = false

    /// `internal` (not `private`) so tests can await sync completion via
    /// `syncTask?.value`. Never written from test code.
    @ObservationIgnored internal private(set) var syncTask: Task<Void, Never>?

    /// `internal` (not `private`) so tests can assert ``activate()`` idempotency
    /// and ``didBecomeActive()`` gating. Never written from test code.
    @ObservationIgnored internal private(set) var observerTask: Task<Void, Never>?

    nonisolated private var ownerKeyPair: KeyPair {
        owner.authority.keyPair
    }

    // MARK: - Init -

    init(client: any ContactSyncing, database: Database, owner: AccountCluster) {
        self.client   = client
        self.database = database
        self.owner    = owner
    }

    deinit {
        syncTask?.cancel()
        observerTask?.cancel()
    }

    // MARK: - Lifecycle -

    /// Idempotent. Called by Phase 4 UI when the user is in a Send-related
    /// context AND contact authorization is `.authorized`. Registers the CN
    /// change observer (if not already) and triggers a sync. After this is
    /// called once in a session, ``didBecomeActive()`` is no longer a no-op.
    ///
    /// Caller MUST verify authorization status before calling — this method
    /// does not prompt or check. `CNContactStore.requestAccess` lives in
    /// `ContactsAuthorizer.authorize()` and is invoked from the Send permission
    /// screen; only after that resolves to `.authorized` should this be called.
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

    /// Called from `AppDelegate.scenePhaseChanged(.active)` as a one-liner per
    /// the codebase's fire-and-forget convention. **No-op until the controller
    /// has been ``activate()``'d in this session** — cold launches and
    /// pre-Send foregrounds do zero contact work.
    nonisolated func didBecomeActive() {
        Task { @MainActor [weak self] in
            guard let self, self.observerTask != nil else { return }
            self.sync()
        }
    }

    // MARK: - Sync -

    /// Drops if a sync is already in flight; otherwise launches one. Heavy
    /// work hops off the main actor via the `@concurrent nonisolated` ``runSync()``.
    func sync() {
        guard !isSyncing else {
            logger.debug("Sync already in flight — dropping trigger")
            return
        }
        isSyncing = true
        syncTask = Task { [weak self] in
            await self?.runSync()
            self?.isSyncing = false
            self?.syncTask = nil
        }
    }

    @concurrent nonisolated private func runSync() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
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

    /// Drives the state machine against the provided contacts. `internal` (not
    /// `private`) so tests can drive it with synthetic input — the real CN
    /// enumeration (``readContacts()``) is the only path that's hard to mock
    /// from the tests, and splitting it out makes the rest verifiable.
    internal nonisolated func performSync(contacts: [Database.LocalContact]) async throws {
        let storedState = try database.contactSyncState()
        let phones      = contacts.map(\.e164)
        let newChecksum = Self.checksum(of: phones)

        // Step 1 — steady-state idle: local unchanged AND server agrees.
        if let storedChecksum = storedState.checksum, storedChecksum == newChecksum {
            let result = try await client.checkContactSync(
                checksum: storedChecksum,
                owner:    ownerKeyPair
            )
            if case .ok = result {
                logger.info("Sync skipped — local unchanged, server agrees")
                return
            }
            logger.info("Server reported drift — re-uploading")
        }

        let snapshot = try database.localContactsSnapshot()

        // Step 2 — full or delta upload. Drift on delta falls back to full in
        // the same call.
        if let oldChecksum = storedState.checksum, !snapshot.isEmpty {
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
        } else {
            try await uploadFull(phones: phones, checksum: newChecksum)
        }

        // Step 3 — persist new state. `changeHistory` stays nil per the
        // doc-comment.
        try database.replaceLocalContactsSnapshot(contacts)
        try database.setContactSyncState(.init(
            checksum:      newChecksum,
            changeHistory: nil,
            lastSyncedAt:  .now
        ))

        // Step 4 — refresh matched-set table from the server stream.
        try await refreshFlipcashContacts(checksum: newChecksum)
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
        // `streamFlipcashContacts` is a sync function on `@MainActor` FlipClient
        // — hop to obtain the AsyncThrowingStream, then iterate off-main.
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

    /// Enumerate the local store, normalize phones to E.164, dedupe by E.164
    /// keeping the first occurrence's `contactId` (linked contacts commonly
    /// share a number).
    ///
    /// A fresh `CNContactStore` is constructed per call — the type is not
    /// declared `Sendable` so it can't be stored as a `nonisolated let`, and
    /// `CNContactStore()` is documented as thread-safe and cheap to allocate
    /// (it's a handle to the OS store, not the data itself).
    nonisolated private func readContacts() throws -> [Database.LocalContact] {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: [
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactIdentifierKey   as CNKeyDescriptor,
        ])

        var seen:   Set<String> = []
        var locals: [Database.LocalContact] = []

        try store.enumerateContacts(with: request) { contact, _ in
            for labelled in contact.phoneNumbers {
                guard let phone = Phone(labelled.value.stringValue) else { continue }
                if seen.insert(phone.e164).inserted {
                    locals.append(.init(e164: phone.e164, contactId: contact.identifier))
                }
            }
        }
        return locals
    }

    // MARK: - Pure helpers (exposed `internal` for unit tests) -

    /// 32-byte XOR-of-SHA256 over E.164 strings. Order-independent (XOR is
    /// commutative) so contact reorderings produce the same checksum — matches
    /// the server's algorithm.
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

    /// Adds/removes between an old snapshot and a new contact list. Sorted for
    /// deterministic on-wire bytes and log diff-ability.
    nonisolated static func delta(oldSnapshot: [String], newContacts: [String]) -> (adds: [String], removes: [String]) {
        let oldSet = Set(oldSnapshot)
        let newSet = Set(newContacts)
        return (
            adds:    Array(newSet.subtracting(oldSet)).sorted(),
            removes: Array(oldSet.subtracting(newSet)).sorted()
        )
    }

    // MARK: - Error handling -

    /// Logging is nonisolated (swift-log `Logger` is a `Sendable` value); the
    /// `ErrorReporting` hops to the main actor inside ``reportError(_:reason:)``.
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
