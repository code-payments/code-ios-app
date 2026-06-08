//
//  ContactSyncControllerTests.swift
//  FlipcashTests
//

import Contacts
import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

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

    // MARK: - normalizeContacts (CN string → E.164 dedupe)

    @Suite("normalizeContacts(rawNumbers:region:)")
    struct NormalizeContactsTests {

        @Test("National-format US numbers parse against .us region")
        func nationalUSParses() {
            let result = ContactSyncController.normalizeContacts(
                rawNumbers: [
                    ("415-555-0100", "alice"),
                    ("(415) 555-0101", "bob"),
                    ("4155550102", "carol"),
                ],
                region: .us
            )
            #expect(result.map(\.e164) == ["+14155550100", "+14155550101", "+14155550102"])
            #expect(result.map(\.contactId) == ["alice", "bob", "carol"])
        }

        @Test("National-format UK numbers parse against .gb region")
        func nationalUKParses() {
            let result = ContactSyncController.normalizeContacts(
                rawNumbers: [("020 7946 0958", "alice")],
                region: .gb
            )
            #expect(result.first?.e164 == "+442079460958")
        }

        @Test("International-format numbers parse regardless of region hint")
        func internationalIgnoresRegion() {
            let result = ContactSyncController.normalizeContacts(
                rawNumbers: [("+44 20 7946 0958", "alice")],
                region: .us
            )
            #expect(result.first?.e164 == "+442079460958")
        }

        @Test("Unparseable entries are silently skipped")
        func unparseableSkipped() {
            let result = ContactSyncController.normalizeContacts(
                rawNumbers: [
                    ("not-a-phone", "alice"),
                    ("415-555-0100", "bob"),
                    ("", "carol"),
                ],
                region: .us
            )
            #expect(result.count == 1)
            #expect(result.first?.contactId == "bob")
        }

        @Test("Same e164 under distinct contactIds keeps every (e164, contactId) pair")
        func sharedPhoneAcrossContactsAllSurvive() {
            let result = ContactSyncController.normalizeContacts(
                rawNumbers: [
                    ("415-555-0100", "alice"),
                    ("(415) 555-0100", "bob"),
                    ("+14155550100", "carol"),
                ],
                region: .us
            )
            #expect(result.count == 3)
            #expect(result.allSatisfy { $0.e164 == "+14155550100" })
            #expect(result.map(\.contactId) == ["alice", "bob", "carol"])
        }

        @Test("Same (e164, contactId) tuple seen twice collapses to one")
        func dedupeOnTuple() {
            let result = ContactSyncController.normalizeContacts(
                rawNumbers: [
                    ("415-555-0100", "alice"),
                    ("(415) 555-0100", "alice"),
                    ("+14155550100", "alice"),
                ],
                region: .us
            )
            #expect(result == [.init(e164: "+14155550100", contactId: "alice")])
        }

        @Test("Empty input returns empty result")
        func emptyInput() {
            let result = ContactSyncController.normalizeContacts(rawNumbers: [], region: .us)
            #expect(result.isEmpty)
        }
    }

    // MARK: - Lifecycle

    /// `.serialized` so parallel observer Tasks don't starve the scheduler.
    /// Default auth status is `.notDetermined` — never let runSync reach
    /// real `CNContactStore` access in tests.
    @Suite("Lifecycle", .serialized)
    @MainActor
    struct LifecycleTests {

        private static func makeController(
            mock: MockContactSync = .init(),
            database: Database = .mock,
            status: CNAuthorizationStatus = .notDetermined
        ) -> ContactSyncController {
            ContactSyncController(
                client:                      mock,
                database:                    database,
                owner:                       .mock,
                authorizationStatusProvider: { status }
            )
        }

        /// Counts auth checks and returns `.notDetermined` so `runSync` exits
        /// before any CN access.
        private final class AuthCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var _count = 0
            var count: Int { lock.withLock { _count } }
            func bumpAndReturnNotDetermined() -> CNAuthorizationStatus {
                lock.withLock { _count += 1 }
                return .notDetermined
            }
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

            #expect(controller.observerTask == firstObserver)
        }

        @Test("activate() surfaces the cached directory even when the contact sync fails")
        func activateResolvesCachedDirectoryWhenSyncFails() async throws {
            let mock = MockContactSync()
            mock.fullUploadResult = .failure(ErrorContactSync.transportFailure)
            let database = Database.mock
            try database.replaceLocalContactsSnapshot([
                Database.LocalContact(e164: "+14155550100", contactId: "alice"),
            ])
            try database.replaceFlipcashContacts(["+14155550100"], matchedAt: .now)
            let controller = Self.makeController(mock: mock, database: database, status: .authorized)

            controller.activate()
            await controller.syncTask?.value
            try await Self.awaitResolved(controller)

            // The flag, not the contents: name resolution reads the real
            // CNContactStore, which a unit test can't seed.
            #expect(controller.hasResolvedOnce)
        }

        @Test("Pre-network resolve on an empty DB leaves the picker not-ready — first grant keeps loading instead of flashing the empty state")
        func emptyCacheResolve_leavesPickerNotReady() async {
            let controller = Self.makeController()

            await controller.resolveDirectory()

            #expect(!controller.hasResolvedOnce)
            #expect(!controller.isDirectoryReady)
        }

        @Test("didBecomeActive() is a no-op before activate()")
        func didBecomeActiveNoOpBeforeActivate() async {
            let counter = AuthCounter()
            let controller = ContactSyncController(
                client:                      MockContactSync(),
                database:                    .mock,
                owner:                       .mock,
                authorizationStatusProvider: counter.bumpAndReturnNotDetermined
            )
            controller.didBecomeActive()
            await Task.yield()
            await Task.yield()

            #expect(controller.syncTask == nil)
            #expect(controller.isSyncing == false)
            #expect(counter.count == 0)
        }

        @Test("didBecomeActive() actually triggers a sync after activate()")
        func didBecomeActiveTriggersSyncAfterActivate() async throws {
            let counter = AuthCounter()
            let controller = ContactSyncController(
                client:                      MockContactSync(),
                database:                    .mock,
                owner:                       .mock,
                authorizationStatusProvider: counter.bumpAndReturnNotDetermined
            )

            controller.activate()
            await controller.syncTask?.value
            #expect(counter.count == 1)

            controller.didBecomeActive()
            try await Self.awaitCounter(counter, atLeast: 2, controller: controller)

            #expect(counter.count == 2)
        }

        @Test("sync() coalesces a trigger that arrives while in flight and re-runs once the first completes")
        func syncCoalescesInFlightTriggerAndRerunsAfterCompletion() async throws {
            let counter = AuthCounter()
            let controller = ContactSyncController(
                client:                      MockContactSync(),
                database:                    .mock,
                owner:                       .mock,
                authorizationStatusProvider: counter.bumpAndReturnNotDetermined
            )

            controller.sync()
            #expect(controller.isSyncing == true)

            controller.sync()
            #expect(controller.isSyncing == true)

            try await Self.awaitCounter(counter, atLeast: 2, controller: controller)
            try await Self.awaitSyncIdle(controller: controller)

            #expect(counter.count == 2)
            #expect(controller.isSyncing == false)
            #expect(controller.syncTask == nil)
        }

        private static func awaitSyncIdle(controller: ContactSyncController) async throws {
            let deadline = Date.now.addingTimeInterval(1.0)
            while (controller.isSyncing || controller.syncTask != nil), Date.now < deadline {
                if let task = controller.syncTask {
                    await task.value
                } else {
                    await Task.yield()
                }
            }
        }

        private static func awaitCounter(
            _ counter: AuthCounter,
            atLeast target: Int,
            controller: ContactSyncController
        ) async throws {
            let deadline = Date.now.addingTimeInterval(1.0)
            while counter.count < target, Date.now < deadline {
                if let task = controller.syncTask {
                    await task.value
                } else {
                    await Task.yield()
                }
            }
        }

        private static func awaitResolved(_ controller: ContactSyncController) async throws {
            let deadline = Date.now.addingTimeInterval(1.0)
            while !controller.hasResolvedOnce, Date.now < deadline {
                await Task.yield()
            }
        }
    }

    // MARK: - State machine

    @Suite("performSync(contacts:)", .serialized)
    @MainActor
    struct PerformSyncTests {

        private static func makeController(
            mock: MockContactSync,
            database: Database
        ) -> ContactSyncController {
            ContactSyncController(client: mock, database: database, owner: .mock)
        }

        private static func seedDatabase(
            _ database: Database,
            checksum: Data,
            snapshot: [Database.LocalContact] = []
        ) throws {
            try database.setContactSyncState(.init(checksum: checksum))
            if !snapshot.isEmpty {
                try database.replaceLocalContactsSnapshot(snapshot)
            }
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
            let fullCall = try #require(mock.fullCalls.first)
            #expect(mock.fullCalls.count == 1)
            #expect(fullCall.phones == contacts.map(\.e164))
            #expect(mock.streamCalls.count == 1)

            let storedState = try database.contactSyncState()
            #expect(storedState.checksum == ContactSyncController.checksum(of: contacts.map(\.e164)))

            #expect(Set(try database.localContactsSnapshot().map(\.e164)) == Set(contacts.map(\.e164)))
            #expect(Set(try database.flipcashContacts()) == ["+14155550101"])
        }

        @Test("refreshMatchedSet re-pulls and persists the matched set when a prior sync exists")
        func refreshMatchedSet_rePullsWhenSynced() async throws {
            let mock = MockContactSync()
            mock.streamYields = [Self.bobContact.e164]
            let database = Database.mock
            let storedChecksum = ContactSyncController.checksum(of: [Self.aliceContact.e164])
            try Self.seedDatabase(database, checksum: storedChecksum, snapshot: [Self.aliceContact])
            let controller = Self.makeController(mock: mock, database: database)

            await controller.refreshMatchedSet()

            #expect(mock.streamCalls == [storedChecksum])
            #expect(mock.fullCalls.isEmpty)
            #expect(mock.deltaCalls.isEmpty)
            #expect(Set(try database.flipcashContacts()) == [Self.bobContact.e164])
        }

        @Test("refreshMatchedSet is a no-op without a prior sync")
        func refreshMatchedSet_noOpWithoutChecksum() async throws {
            let mock = MockContactSync()
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            await controller.refreshMatchedSet()

            #expect(mock.streamCalls.isEmpty)
        }

        @Test("Steady-state — local unchanged + server agrees → no upload, but refreshes the matched set")
        func steadyState_skipsUploadButRefreshesMatchedSet() async throws {
            let mock = MockContactSync()
            mock.checkSyncResult = .success(.ok)
            mock.streamYields = [Self.bobContact.e164]
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let contacts = [Self.aliceContact, Self.bobContact]
            let storedChecksum = ContactSyncController.checksum(of: contacts.map(\.e164))
            try Self.seedDatabase(database, checksum: storedChecksum, snapshot: contacts)

            try await controller.performSync(contacts: contacts)

            #expect(mock.checkSyncCalls == [storedChecksum])
            #expect(mock.deltaCalls.isEmpty)
            #expect(mock.fullCalls.isEmpty)
            #expect(mock.streamCalls == [storedChecksum])
            #expect(Set(try database.flipcashContacts()) == [Self.bobContact.e164])
        }

        @Test("Local-changed — stored snapshot present → delta upload + stream")
        func localChanged_deltaUploadAndStream() async throws {
            let mock = MockContactSync()
            mock.deltaUploadResult = .success(.ok)
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let oldSnapshot = [Self.aliceContact]
            let oldChecksum = ContactSyncController.checksum(of: oldSnapshot.map(\.e164))
            try Self.seedDatabase(database, checksum: oldChecksum, snapshot: oldSnapshot)

            let newContacts = [Self.aliceContact, Self.bobContact]
            try await controller.performSync(contacts: newContacts)

            let deltaCall = try #require(mock.deltaCalls.first)
            #expect(mock.deltaCalls.count == 1)
            #expect(deltaCall.adds == ["+14155550101"])
            #expect(deltaCall.removes.isEmpty)
            #expect(deltaCall.oldChecksum == oldChecksum)
            #expect(deltaCall.newChecksum == ContactSyncController.checksum(of: newContacts.map(\.e164)))
            #expect(mock.fullCalls.isEmpty)
            #expect(mock.streamCalls.count == 1)
            #expect(mock.checkSyncCalls.isEmpty)
        }

        @Test("CHECKSUM_DRIFT on delta → fallback to full upload in same call")
        func checksumDrift_fallsBackToFullUpload() async throws {
            let mock = MockContactSync()
            mock.deltaUploadResult = .success(.checksumDrift)
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let oldSnapshot = [Self.aliceContact]
            let oldChecksum = ContactSyncController.checksum(of: oldSnapshot.map(\.e164))
            try Self.seedDatabase(database, checksum: oldChecksum, snapshot: oldSnapshot)

            let newContacts = [Self.aliceContact, Self.bobContact, Self.carolContact]
            try await controller.performSync(contacts: newContacts)

            #expect(mock.deltaCalls.count == 1)
            let fullCall = try #require(mock.fullCalls.first)
            #expect(mock.fullCalls.count == 1)
            #expect(fullCall.phones == newContacts.map(\.e164))
            #expect(mock.streamCalls.count == 1)

            let storedState = try database.contactSyncState()
            #expect(storedState.checksum == ContactSyncController.checksum(of: newContacts.map(\.e164)))
        }

        @Test("Server drift on idle probe → straight to full upload (skips doomed delta)")
        func serverDriftOnProbe_goesStraightToFullUpload() async throws {
            let mock = MockContactSync()
            mock.checkSyncResult = .success(.outOfSync(serverChecksum: Data(repeating: 0xAB, count: 32)))
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let contacts = [Self.aliceContact, Self.bobContact]
            let storedChecksum = ContactSyncController.checksum(of: contacts.map(\.e164))
            try Self.seedDatabase(database, checksum: storedChecksum, snapshot: contacts)

            try await controller.performSync(contacts: contacts)

            #expect(mock.checkSyncCalls == [storedChecksum])
            #expect(mock.deltaCalls.isEmpty)
            let fullCall = try #require(mock.fullCalls.first)
            #expect(mock.fullCalls.count == 1)
            #expect(fullCall.phones == contacts.map(\.e164))
            #expect(mock.streamCalls.count == 1)
        }

        @Test("Empty snapshot but stored checksum → full upload path (not delta)")
        func emptySnapshot_choosesFullUpload() async throws {
            let mock = MockContactSync()
            mock.fullUploadResult = .success(())
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            try Self.seedDatabase(database, checksum: Data(repeating: 0xFF, count: 32))

            let contacts = [Self.aliceContact]
            try await controller.performSync(contacts: contacts)

            #expect(mock.deltaCalls.isEmpty)
            #expect(mock.fullCalls.count == 1)
        }

        @Test("Upload failure propagates and state stays unchanged")
        func uploadFailure_doesNotPersist() async throws {
            let mock = MockContactSync()
            mock.fullUploadResult = .failure(ErrorContactSync.transportFailure)
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            await #expect(throws: ErrorContactSync.transportFailure) {
                try await controller.performSync(contacts: [Self.aliceContact])
            }

            #expect(try database.contactSyncState() == .empty)
            #expect(try database.localContactsSnapshot().isEmpty)
            #expect(try database.flipcashContacts().isEmpty)
        }

        @Test("Stream failure leaves state unmodified — including pre-existing matched-set rows")
        func streamFailure_doesNotPersistAndLeavesMatchedSetIntact() async throws {
            let mock = MockContactSync()
            mock.streamTerminalError = ErrorContactSync.transportFailure
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let priorChecksum = ContactSyncController.checksum(of: [Self.aliceContact.e164])
            try Self.seedDatabase(database, checksum: priorChecksum, snapshot: [Self.aliceContact])
            try database.replaceFlipcashContacts([Self.bobContact.e164], matchedAt: .now)

            await #expect(throws: ErrorContactSync.transportFailure) {
                try await controller.performSync(contacts: [Self.bobContact, Self.carolContact])
            }

            #expect(mock.deltaCalls.count == 1)
            #expect(mock.fullCalls.isEmpty)
            #expect(mock.streamCalls.count == 1)
            let storedState = try database.contactSyncState()
            #expect(storedState.checksum == priorChecksum)
            #expect(Set(try database.localContactsSnapshot().map(\.e164)) == [Self.aliceContact.e164])
            #expect(Set(try database.flipcashContacts()) == [Self.bobContact.e164])
        }

        @Test("CheckSync `.denied` from server propagates")
        func checkSyncDenied_propagates() async throws {
            let mock = MockContactSync()
            mock.checkSyncResult = .failure(ErrorContactSync.denied)
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let contacts = [Self.aliceContact]
            let storedChecksum = ContactSyncController.checksum(of: contacts.map(\.e164))
            try Self.seedDatabase(database, checksum: storedChecksum, snapshot: contacts)

            await #expect(throws: ErrorContactSync.denied) {
                try await controller.performSync(contacts: contacts)
            }
            #expect(mock.deltaCalls.isEmpty)
            #expect(mock.fullCalls.isEmpty)
        }

        // MARK: First-scan "already on Flipcash" signal

        @Test("First scan signals how many contacts the server matched")
        func firstScan_withMatches_signalsCount() async throws {
            let mock = MockContactSync()
            mock.streamYields = [Self.bobContact.e164, Self.carolContact.e164]
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            try await controller.performSync(contacts: [Self.aliceContact, Self.bobContact, Self.carolContact])

            #expect(controller.onFlipcashMatchCount == 2)
        }

        @Test("First scan with no matches signals nothing")
        func firstScan_noMatches_signalsNothing() async throws {
            let mock = MockContactSync()
            mock.streamYields = []
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            try await controller.performSync(contacts: [Self.aliceContact])

            #expect(controller.onFlipcashMatchCount == nil)
        }

        @Test("A later sync never re-signals")
        func laterSync_doesNotReSignal() async throws {
            let mock = MockContactSync()
            mock.streamYields = [Self.bobContact.e164]
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            let contacts = [Self.aliceContact, Self.bobContact]
            try await controller.performSync(contacts: contacts)
            #expect(controller.onFlipcashMatchCount == 1)

            // The forward consumes the signal.
            controller.onFlipcashMatchCount = nil

            // A second sync of the same set probes the server and refreshes the
            // matched set, but the stored checksum now exists — so it must stay nil.
            mock.checkSyncResult = .success(.ok)
            try await controller.performSync(contacts: contacts)

            #expect(controller.onFlipcashMatchCount == nil)
        }
    }

    // MARK: - Clear on revoke

    @Suite("ClearOnRevoke", .serialized)
    @MainActor
    struct ClearOnRevokeTests {

        private static func makeController(
            mock: MockContactSync,
            database: Database,
            status: CNAuthorizationStatus
        ) -> ContactSyncController {
            ContactSyncController(
                client:                      mock,
                database:                    database,
                owner:                       .mock,
                authorizationStatusProvider: { status }
            )
        }

        private static func seedUploadedSet(
            _ database: Database,
            contacts: [Database.LocalContact],
            matched: [String] = []
        ) throws {
            try database.setContactSyncState(.init(
                checksum: ContactSyncController.checksum(of: contacts.map(\.e164))
            ))
            try database.replaceLocalContactsSnapshot(contacts)
            if !matched.isEmpty {
                try database.replaceFlipcashContacts(matched, matchedAt: Date(timeIntervalSince1970: 1_716_000_000))
            }
        }

        private static let aliceContact = Database.LocalContact(e164: "+14155550100", contactId: "alice")
        private static let bobContact   = Database.LocalContact(e164: "+14155550101", contactId: "bob")

        @Test(
            "Revoked access wipes the server set and drains the local tables",
            arguments: [CNAuthorizationStatus.denied, .restricted]
        )
        func revoke_wipesAndDrains(_ status: CNAuthorizationStatus) async throws {
            let mock = MockContactSync()
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database, status: status)

            try Self.seedUploadedSet(database, contacts: [Self.aliceContact, Self.bobContact], matched: [Self.bobContact.e164])

            await controller.clearServerContactSetIfRevoked()

            let fullCall = try #require(mock.fullCalls.first)
            #expect(mock.fullCalls.count == 1)
            #expect(fullCall.phones.isEmpty)
            #expect(fullCall.checksum == ContactSyncController.checksum(of: []))
            #expect(mock.deltaCalls.isEmpty)
            #expect(mock.streamCalls.isEmpty)

            #expect(try database.contactSyncState() == .empty)
            #expect(try database.localContactsSnapshot().isEmpty)
            #expect(try database.flipcashContacts().isEmpty)
        }

        @Test("Revoked but nothing was ever uploaded → no upload")
        func revoke_nothingUploaded_noOp() async throws {
            let mock = MockContactSync()
            let database = Database.mock  // checksum is nil
            let controller = Self.makeController(mock: mock, database: database, status: .denied)

            await controller.clearServerContactSetIfRevoked()

            #expect(mock.fullCalls.isEmpty)
        }

        @Test(
            "Non-revoked access leaves an uploaded set untouched",
            arguments: [CNAuthorizationStatus.authorized, .notDetermined]
        )
        func nonRevoked_leavesSetIntact(_ status: CNAuthorizationStatus) async throws {
            let mock = MockContactSync()
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database, status: status)

            try Self.seedUploadedSet(database, contacts: [Self.aliceContact])

            await controller.clearServerContactSetIfRevoked()

            #expect(mock.fullCalls.isEmpty)
            #expect(try database.contactSyncState().checksum != nil)
        }

        @Test("Upload failure leaves the set intact, and the next foreground retries")
        func revoke_uploadFailure_retriesNextForeground() async throws {
            let mock = MockContactSync()
            mock.fullUploadResult = .failure(ErrorContactSync.transportFailure)
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database, status: .denied)

            try Self.seedUploadedSet(database, contacts: [Self.aliceContact])

            await controller.clearServerContactSetIfRevoked()

            // Attempted, but the failure leaves the checksum + snapshot for a retry.
            #expect(mock.fullCalls.count == 1)
            #expect(try database.contactSyncState().checksum != nil)
            #expect(try database.localContactsSnapshot().isEmpty == false)

            // Next foreground: the upload now succeeds → the wipe completes.
            mock.fullUploadResult = .success(())
            await controller.clearServerContactSetIfRevoked()

            #expect(mock.fullCalls.count == 2)
            #expect(try database.contactSyncState() == .empty)
            #expect(try database.localContactsSnapshot().isEmpty)
        }
    }

    // MARK: - Clear on account deletion

    @Suite("AccountDeletionClear", .serialized)
    @MainActor
    struct AccountDeletionClearTests {

        private static func makeController(mock: MockContactSync, database: Database) -> ContactSyncController {
            ContactSyncController(client: mock, database: database, owner: .mock)
        }

        private static let aliceContact = Database.LocalContact(e164: "+14155550100", contactId: "alice")

        @Test("Account deletion with an uploaded set fires an empty full upload and drains the local tables")
        func accountDeletion_withUploadedSet_firesEmptyUploadAndDrains() async throws {
            let mock = MockContactSync()
            let database = Database.mock
            let controller = Self.makeController(mock: mock, database: database)

            try database.setContactSyncState(.init(
                checksum: ContactSyncController.checksum(of: [Self.aliceContact.e164])
            ))
            try database.replaceLocalContactsSnapshot([Self.aliceContact])
            try database.replaceFlipcashContacts([Self.aliceContact.e164], matchedAt: Date(timeIntervalSince1970: 1_716_000_000))

            await controller.clearServerContactSetForAccountDeletion()

            let fullCall = try #require(mock.fullCalls.first)
            #expect(mock.fullCalls.count == 1)
            #expect(fullCall.phones.isEmpty)
            #expect(fullCall.checksum == ContactSyncController.checksum(of: []))
            #expect(try database.contactSyncState() == .empty)
            #expect(try database.localContactsSnapshot().isEmpty)
            #expect(try database.flipcashContacts().isEmpty)
        }

        @Test("Account deletion with nothing previously uploaded does not call the server")
        func accountDeletion_nothingUploaded_noOp() async throws {
            let mock = MockContactSync()
            let database = Database.mock  // checksum is nil
            let controller = Self.makeController(mock: mock, database: database)

            await controller.clearServerContactSetForAccountDeletion()

            #expect(mock.fullCalls.isEmpty)
        }
    }

}
