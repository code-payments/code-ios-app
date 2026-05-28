import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("ContactNameResolver")
struct ContactNameResolverTests {

    @Test("Returns the name when a single matching contact has a name")
    func singleMatchWithName() {
        let resolver = ContactNameResolver(
            snapshotReader: StubReader(map: ["+15551234567": ["alice-id"]]),
            nameProvider: StubNameProvider(map: ["alice-id": "Alice"])
        )

        let phone = Self.phone("+15551234567")
        #expect(resolver.resolve(phone: phone) == "Alice")
    }

    @Test("Skips contacts with nil names and returns the first non-empty match")
    func skipsNilNames() {
        let resolver = ContactNameResolver(
            snapshotReader: StubReader(map: ["+15551234567": ["nameless-id", "alice-id"]]),
            nameProvider: StubNameProvider(map: ["nameless-id": nil, "alice-id": "Alice"])
        )

        let phone = Self.phone("+15551234567")
        #expect(resolver.resolve(phone: phone) == "Alice")
    }

    @Test("Returns nil when the snapshot has no contacts for the phone")
    func noContacts() {
        let resolver = ContactNameResolver(
            snapshotReader: StubReader(map: [:]),
            nameProvider: StubNameProvider(map: [:])
        )

        let phone = Self.phone("+15551234567")
        #expect(resolver.resolve(phone: phone) == nil)
    }

    @Test("Returns nil when all matching contacts have nil names")
    func allNamesNil() {
        let resolver = ContactNameResolver(
            snapshotReader: StubReader(map: ["+15551234567": ["id-a", "id-b"]]),
            nameProvider: StubNameProvider(map: ["id-a": nil, "id-b": nil])
        )

        let phone = Self.phone("+15551234567")
        #expect(resolver.resolve(phone: phone) == nil)
    }

    @Test("Returns nil when the snapshot reader throws")
    func readerThrows() {
        let resolver = ContactNameResolver(
            snapshotReader: ThrowingReader(),
            nameProvider: StubNameProvider(map: [:])
        )

        let phone = Self.phone("+15551234567")
        #expect(resolver.resolve(phone: phone) == nil)
    }

    // MARK: - Test helpers -

    private static func phone(_ value: String) -> Flipcash_Phone_V1_PhoneNumber {
        var phone = Flipcash_Phone_V1_PhoneNumber()
        phone.value = value
        return phone
    }

    private struct StubReader: ContactSnapshotReading {
        let map: [String: [String]]
        func contactIds(forE164 e164: String) -> [String] {
            map[e164] ?? []
        }
    }

    private struct ThrowingReader: ContactSnapshotReading {
        struct Failure: Error {}
        func contactIds(forE164 e164: String) throws -> [String] {
            throw Failure()
        }
    }

    private struct StubNameProvider: ContactNameProviding {
        let map: [String: String?]
        func displayName(forContactId id: String) -> String? {
            map[id] ?? nil
        }
    }
}
