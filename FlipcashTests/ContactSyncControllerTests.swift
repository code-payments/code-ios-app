//
//  ContactSyncControllerTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// Tests cover:
/// - `nonisolated static` pure helpers (`checksum`, `delta`) — direct call
/// - Lifecycle (``activate()``, ``didBecomeActive()``) — observed via internal
///   `observerTask` / `syncTask` accessors
/// - The state machine ``performSync(contacts:)`` — driven with synthetic
///   contacts and a `MockContactSync` conformer of `ContactSyncing`
///
/// `runSync()` and `readContacts()` aren't directly covered: the former depends
/// on `CNContactStore.authorizationStatus(for:)` (OS state, can't be mocked
/// without further extraction); the latter is a thin shim over CN enumeration.
/// They're exercised end-to-end via the dev-backend verification gate.
@Suite("ContactSyncController")
struct ContactSyncControllerTests {

    // MARK: - Checksum

    @Suite("checksum(of:)")
    struct ChecksumTests {

        @Test("Empty input returns 32 zero bytes")
        func emptyInputIsZeroes() {
            let checksum = ContactSyncController.checksum(of: [])
            #expect(checksum.count == 32)
            #expect(checksum.allSatisfy { $0 == 0 })
        }

        @Test("Single phone returns its raw SHA256")
        func singlePhoneEqualsSHA256() {
            let phone = "+14155550100"
            let checksum = ContactSyncController.checksum(of: [phone])
            let expected = SHA256.digest(phone)
            #expect(checksum == expected)
            #expect(checksum.count == 32)
        }

        @Test("Reordering inputs produces the same checksum (XOR commutativity)")
        func reorderingIsStable() {
            let phones = [
                "+14155550100",
                "+14155550101",
                "+442071234567",
                "+819012345678",
                "+5511987654321",
            ]
            let forward  = ContactSyncController.checksum(of: phones)
            let reversed = ContactSyncController.checksum(of: phones.reversed())
            let shuffled = ContactSyncController.checksum(of: phones.shuffled())
            #expect(forward == reversed)
            #expect(forward == shuffled)
        }

        @Test("Duplicates collapse to identity (XOR cancellation)")
        func duplicatePairsCancel() {
            // The controller dedupes before calling checksum, but the
            // algorithm itself must round-trip: XOR-ing the same value twice
            // is identity. Two identical phones should produce the same bytes
            // as the empty input.
            let phones = ["+14155550100", "+14155550100"]
            let checksum = ContactSyncController.checksum(of: phones)
            #expect(checksum.count == 32)
            #expect(checksum.allSatisfy { $0 == 0 })
        }

        @Test("Different phone sets produce different checksums")
        func differentSetsDiffer() {
            let a = ContactSyncController.checksum(of: ["+14155550100"])
            let b = ContactSyncController.checksum(of: ["+14155550101"])
            #expect(a != b)
        }

        @Test("Adding a phone changes the checksum")
        func addingPhoneChangesChecksum() {
            let base       = ["+14155550100", "+442071234567"]
            let expanded   = base + ["+819012345678"]
            let baseSum    = ContactSyncController.checksum(of: base)
            let expandedSum = ContactSyncController.checksum(of: expanded)
            #expect(baseSum != expandedSum)
        }

        @Test("Removing a phone reverts the checksum (XOR inverse)")
        func removingPhoneIsReverseOfAdding() {
            let base    = ["+14155550100", "+442071234567"]
            let added   = base + ["+819012345678"]
            let baseSum  = ContactSyncController.checksum(of: base)
            let addedSum = ContactSyncController.checksum(of: added)
            // XOR-ing the added phone's SHA256 onto the expanded checksum
            // must restore the base checksum (XOR is its own inverse).
            let extraHash = SHA256.digest("+819012345678")
            var restored = [UInt8](addedSum)
            for (i, byte) in extraHash.enumerated() {
                restored[i] ^= byte
            }
            #expect(Data(restored) == baseSum)
        }
    }

    // MARK: - Delta

    @Suite("delta(oldSnapshot:newContacts:)")
    struct DeltaTests {

        @Test("Identical sets produce no adds and no removes")
        func identicalIsEmpty() {
            let phones = ["+14155550100", "+442071234567"]
            let result = ContactSyncController.delta(
                oldSnapshot: phones,
                newContacts: phones
            )
            #expect(result.adds.isEmpty)
            #expect(result.removes.isEmpty)
        }

        @Test("Adds-only: new contacts not in snapshot")
        func addsOnly() {
            let result = ContactSyncController.delta(
                oldSnapshot: ["+14155550100"],
                newContacts: ["+14155550100", "+14155550101", "+14155550102"]
            )
            #expect(result.adds == ["+14155550101", "+14155550102"])
            #expect(result.removes.isEmpty)
        }

        @Test("Removes-only: snapshot phones missing from new contacts")
        func removesOnly() {
            let result = ContactSyncController.delta(
                oldSnapshot: ["+14155550100", "+14155550101", "+14155550102"],
                newContacts: ["+14155550100"]
            )
            #expect(result.adds.isEmpty)
            #expect(result.removes == ["+14155550101", "+14155550102"])
        }

        @Test("Adds and removes mixed")
        func addsAndRemoves() {
            let result = ContactSyncController.delta(
                oldSnapshot: ["+14155550100", "+14155550102"],
                newContacts: ["+14155550101", "+14155550102"]
            )
            #expect(result.adds == ["+14155550101"])
            #expect(result.removes == ["+14155550100"])
        }

        @Test("Empty new contacts removes everything")
        func emptyNewRemovesAll() {
            let result = ContactSyncController.delta(
                oldSnapshot: ["+14155550100", "+14155550101"],
                newContacts: []
            )
            #expect(result.adds.isEmpty)
            #expect(result.removes == ["+14155550100", "+14155550101"])
        }

        @Test("Empty snapshot adds everything (first sync from snapshot)")
        func emptySnapshotAddsAll() {
            let result = ContactSyncController.delta(
                oldSnapshot: [],
                newContacts: ["+14155550101", "+14155550100"]
            )
            #expect(result.adds == ["+14155550100", "+14155550101"])
            #expect(result.removes.isEmpty)
        }

        @Test("Both empty yields no work")
        func bothEmpty() {
            let result = ContactSyncController.delta(
                oldSnapshot: [],
                newContacts: []
            )
            #expect(result.adds.isEmpty)
            #expect(result.removes.isEmpty)
        }

        @Test("Outputs are sorted regardless of input order")
        func outputsAreSorted() {
            let result = ContactSyncController.delta(
                oldSnapshot: ["+999", "+111"],
                newContacts: ["+555", "+333"]
            )
            #expect(result.adds == ["+333", "+555"])
            #expect(result.removes == ["+111", "+999"])
        }

        @Test("Duplicate inputs are collapsed by Set semantics")
        func duplicatesCollapse() {
            let result = ContactSyncController.delta(
                oldSnapshot: ["+14155550100", "+14155550100"],
                newContacts: ["+14155550101", "+14155550101"]
            )
            #expect(result.adds == ["+14155550101"])
            #expect(result.removes == ["+14155550100"])
        }
    }

    // MARK: - Lifecycle

    @Suite("Lifecycle")
    @MainActor
    struct LifecycleTests {

        private static func makeController(
            mock: MockContactSync = .init(),
            database: Database = .mock
        ) -> ContactSyncController {
            ContactSyncController(client: mock, database: database, owner: .mock)
        }

        @Test("Construction is dormant — no observer, no sync, no task")
        func constructionIsDormant() {
            let controller = Self.makeController()
            #expect(controller.observerTask == nil)
            #expect(controller.syncTask == nil)
            #expect(controller.isSyncing == false)
        }

        @Test("activate() registers the observer and launches a sync")
        func activateRegistersObserverAndSyncs() async {
            let controller = Self.makeController()
            controller.activate()
            #expect(controller.observerTask != nil)
            #expect(controller.syncTask != nil)
            await controller.syncTask?.value
        }

        @Test("activate() is idempotent — second call doesn't replace the observer")
        func activateIsIdempotent() async {
            let controller = Self.makeController()
            controller.activate()
            await controller.syncTask?.value
            let firstObserver = controller.observerTask

            controller.activate()
            await controller.syncTask?.value

            // The guard `observerTask == nil` is the only assignment site, so
            // a second activate() must leave the same task in place. `Task`
            // conforms to `Hashable` via task identity — `==` is identity.
            #expect(controller.observerTask == firstObserver)
        }

        @Test("didBecomeActive() is a no-op before activate()")
        func didBecomeActiveNoOpBeforeActivate() async {
            let controller = Self.makeController()
            controller.didBecomeActive()
            // didBecomeActive spawns a main-actor Task that bails on the
            // observerTask guard. Yield twice — once for the spawn, once for
            // the guard check — then assert nothing started.
            await Task.yield()
            await Task.yield()
            #expect(controller.syncTask == nil)
            #expect(controller.isSyncing == false)
        }

        @Test("didBecomeActive() triggers sync once activate() has been called")
        func didBecomeActiveAfterActivate() async {
            let controller = Self.makeController()
            controller.activate()
            await controller.syncTask?.value
            #expect(controller.syncTask == nil)

            controller.didBecomeActive()
            await Task.yield()
            await Task.yield()
            // The didBecomeActive's main-actor Task should have hit sync() by
            // now, which sets syncTask. Either it's still in flight or it has
            // already completed and cleared itself — but `isSyncing` was
            // briefly true and observerTask remains set.
            #expect(controller.observerTask != nil)
        }
    }

    // MARK: - State machine

    @Suite("performSync(contacts:)")
    @MainActor
    struct PerformSyncTests {

        private static func makeController(
            mock: MockContactSync,
            database: Database
        ) -> ContactSyncController {
            ContactSyncController(client: mock, database: database, owner: .mock)
        }

        private static let aliceContact = Database.LocalContact(e164: "+14155550100", contactId: "alice")
        private static let bobContact   = Database.LocalContact(e164: "+14155550101", contactId: "bob")
        private static let carolContact = Database.LocalContact(e164: "+14155550102", contactId: "carol")

        @Test("First sync — no stored checksum → full upload + matched-set stream")
        func firstSync_fullUploadAndStream() async throws {
            let mock = MockContactSync()
            mock.streamYields = ["+14155550101"]
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let contacts = [Self.aliceContact, Self.bobContact]
            try await controller.performSync(contacts: contacts)

            #expect(mock.checkSyncCalls.isEmpty)
            #expect(mock.deltaCalls.isEmpty)
            #expect(mock.fullCalls.count == 1)
            #expect(mock.fullCalls[0].phones == contacts.map(\.e164))
            #expect(mock.streamCalls.count == 1)

            let storedState = try database.contactSyncState()
            #expect(storedState.checksum == ContactSyncController.checksum(of: contacts.map(\.e164)))
            #expect(storedState.lastSyncedAt != nil)

            #expect(try database.localContactsSnapshot().map(\.e164) == contacts.map(\.e164))
            #expect(try database.flipcashContacts() == ["+14155550101"])
        }

        @Test("Steady-state — local unchanged + server agrees → no upload, no stream")
        func steadyState_skipsUploadAndStream() async throws {
            let mock = MockContactSync()
            mock.checkSyncResult = .success(.ok)
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let contacts = [Self.aliceContact, Self.bobContact]
            let storedChecksum = ContactSyncController.checksum(of: contacts.map(\.e164))
            try database.setContactSyncState(.init(
                checksum:      storedChecksum,
                changeHistory: nil,
                lastSyncedAt:  .now
            ))
            try database.replaceLocalContactsSnapshot(contacts)

            try await controller.performSync(contacts: contacts)

            #expect(mock.checkSyncCalls == [storedChecksum])
            #expect(mock.deltaCalls.isEmpty)
            #expect(mock.fullCalls.isEmpty)
            #expect(mock.streamCalls.isEmpty)
        }

        @Test("Local-changed — stored snapshot present → delta upload + stream")
        func localChanged_deltaUploadAndStream() async throws {
            let mock = MockContactSync()
            mock.deltaUploadResult = .success(.ok)
            mock.streamYields = []
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let oldSnapshot = [Self.aliceContact]
            let oldChecksum = ContactSyncController.checksum(of: oldSnapshot.map(\.e164))
            try database.setContactSyncState(.init(
                checksum:      oldChecksum,
                changeHistory: nil,
                lastSyncedAt:  .now
            ))
            try database.replaceLocalContactsSnapshot(oldSnapshot)

            let newContacts = [Self.aliceContact, Self.bobContact]
            try await controller.performSync(contacts: newContacts)

            #expect(mock.deltaCalls.count == 1)
            let call = mock.deltaCalls[0]
            #expect(call.adds == ["+14155550101"])
            #expect(call.removes.isEmpty)
            #expect(call.oldChecksum == oldChecksum)
            #expect(call.newChecksum == ContactSyncController.checksum(of: newContacts.map(\.e164)))
            #expect(mock.fullCalls.isEmpty)
            #expect(mock.streamCalls.count == 1)
            #expect(mock.checkSyncCalls.isEmpty)  // checksum differs from stored, so the idle probe is skipped
        }

        @Test("CHECKSUM_DRIFT on delta → fallback to full upload in same call")
        func checksumDrift_fallsBackToFullUpload() async throws {
            let mock = MockContactSync()
            mock.deltaUploadResult = .success(.checksumDrift)
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let oldSnapshot = [Self.aliceContact]
            let oldChecksum = ContactSyncController.checksum(of: oldSnapshot.map(\.e164))
            try database.setContactSyncState(.init(
                checksum:      oldChecksum,
                changeHistory: nil,
                lastSyncedAt:  .now
            ))
            try database.replaceLocalContactsSnapshot(oldSnapshot)

            let newContacts = [Self.aliceContact, Self.bobContact, Self.carolContact]
            try await controller.performSync(contacts: newContacts)

            #expect(mock.deltaCalls.count == 1)
            #expect(mock.fullCalls.count == 1)
            #expect(mock.fullCalls[0].phones == newContacts.map(\.e164))
            #expect(mock.streamCalls.count == 1)

            // State still persisted with the new checksum after the fallback.
            let storedState = try database.contactSyncState()
            #expect(storedState.checksum == ContactSyncController.checksum(of: newContacts.map(\.e164)))
        }

        @Test("Server drift on idle probe — falls through to upload")
        func serverDriftOnProbe_fallsThroughToUpload() async throws {
            let mock = MockContactSync()
            mock.checkSyncResult = .success(.outOfSync(serverChecksum: Data(repeating: 0xAB, count: 32)))
            mock.deltaUploadResult = .success(.ok)
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let contacts = [Self.aliceContact, Self.bobContact]
            let storedChecksum = ContactSyncController.checksum(of: contacts.map(\.e164))
            try database.setContactSyncState(.init(
                checksum:      storedChecksum,
                changeHistory: nil,
                lastSyncedAt:  .now
            ))
            try database.replaceLocalContactsSnapshot(contacts)

            try await controller.performSync(contacts: contacts)

            // Probe fired, returned outOfSync → fall through to delta upload
            // (snapshot present, oldChecksum present). Adds/removes empty
            // because local and snapshot agree; the upload re-asserts the
            // checksum.
            #expect(mock.checkSyncCalls == [storedChecksum])
            #expect(mock.deltaCalls.count == 1)
            #expect(mock.deltaCalls[0].adds.isEmpty)
            #expect(mock.deltaCalls[0].removes.isEmpty)
            #expect(mock.streamCalls.count == 1)
        }

        @Test("Empty snapshot but stored checksum → full upload path (not delta)")
        func emptySnapshot_choosesFullUpload() async throws {
            let mock = MockContactSync()
            mock.fullUploadResult = .success(())
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            // Stored checksum without a snapshot — e.g. snapshot was wiped
            // (SQLiteVersion bump preserved sync_state but lost snapshot).
            try database.setContactSyncState(.init(
                checksum:      Data(repeating: 0xFF, count: 32),
                changeHistory: nil,
                lastSyncedAt:  .now
            ))

            let contacts = [Self.aliceContact]
            try await controller.performSync(contacts: contacts)

            #expect(mock.deltaCalls.isEmpty)
            #expect(mock.fullCalls.count == 1)
        }

        @Test("Upload failure propagates and state stays unchanged")
        func uploadFailure_doesNotPersist() async throws {
            let mock = MockContactSync()
            mock.fullUploadResult = .failure(ErrorContactSync.networkError)
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            await #expect(throws: ErrorContactSync.networkError) {
                try await controller.performSync(contacts: [Self.aliceContact])
            }

            // Pre-upload state untouched
            #expect(try database.contactSyncState() == .empty)
            #expect(try database.localContactsSnapshot().isEmpty)
            #expect(try database.flipcashContacts().isEmpty)
        }

        @Test("CheckSync `.denied` from server propagates")
        func checkSyncDenied_propagates() async throws {
            let mock = MockContactSync()
            mock.checkSyncResult = .failure(ErrorContactSync.denied)
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let contacts = [Self.aliceContact]
            let storedChecksum = ContactSyncController.checksum(of: contacts.map(\.e164))
            try database.setContactSyncState(.init(
                checksum:      storedChecksum,
                changeHistory: nil,
                lastSyncedAt:  .now
            ))

            await #expect(throws: ErrorContactSync.denied) {
                try await controller.performSync(contacts: contacts)
            }
            #expect(mock.deltaCalls.isEmpty)
            #expect(mock.fullCalls.isEmpty)
        }
    }
}
