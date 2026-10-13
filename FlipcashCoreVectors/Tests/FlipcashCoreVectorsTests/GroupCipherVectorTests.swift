import Foundation
import Testing
import SharedCore
@testable import FlipcashCore

/// `group_cipher.json`, synced from Android's `libs/encryption/chat-cipher` test resources until it
/// moves into the orchestrator's `test-vectors/`. The vectors fix the nonce, which production draws
/// at random, so only the open direction is reproducible: each message, blob and key envelope must
/// open to its plaintext, and each reject must not.
@Suite struct GroupCipherVectorTests {

    struct MessageVector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let groupKey: String
        let chatId: String
        let senderId: String
        let content: String
        let nonce: String
        let ciphertext: String

        var testDescription: String { name }
    }

    struct BlobVector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let groupKey: String
        let chatId: String
        let blobId: String
        let senderId: String
        let image: String
        let blob: String

        var testDescription: String { name }
    }

    struct WrapVector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let wrapperSeed: String
        let wrapperPublicKey: String
        let recipientSeed: String
        let recipientPublicKey: String
        let chatId: String
        let groupKey: String
        let nonce: String
        let ciphertext: String

        var testDescription: String { name }
    }

    struct Rejects: Decodable {
        let decryptGroup: [MessageVector]
    }

    struct Fixture: Decodable {
        let messages: [MessageVector]
        let blobs: [BlobVector]
        let wraps: [WrapVector]
        let rejects: Rejects
    }

    static let fixture: Fixture? = try? loadFixture()
    static let messages: [MessageVector] = fixture?.messages ?? []
    static let blobs: [BlobVector] = fixture?.blobs ?? []
    static let wraps: [WrapVector] = fixture?.wraps ?? []
    static let rejects: [MessageVector] = fixture?.rejects.decryptGroup ?? []

    private static func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "group_cipher", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureLoads() throws {
        let fixture = try Self.loadFixture()
        #expect(!fixture.messages.isEmpty)
        #expect(!fixture.blobs.isEmpty)
        #expect(!fixture.wraps.isEmpty)
        #expect(!fixture.rejects.decryptGroup.isEmpty)
    }

    private func open(_ vector: MessageVector) throws -> Data {
        let bytes = SharedBytes.shared
        let content = try DefaultChatCipher.shared.decryptGroup(
            payload: EncryptedPayload(
                nonce: bytes.byteArray(data: Data(hex: vector.nonce)),
                ciphertext: bytes.byteArray(data: Data(hex: vector.ciphertext))
            ),
            groupKey: bytes.byteArray(data: Data(hex: vector.groupKey)),
            chatId: bytes.byteArray(data: Data(hex: vector.chatId)),
            senderId: bytes.byteArray(data: Data(hex: vector.senderId))
        )
        return bytes.data(bytes: content)
    }

    @Test(arguments: messages)
    func messageOpensToItsContent(_ vector: MessageVector) throws {
        #expect(try open(vector) == Data(hex: vector.content))
    }

    @Test(arguments: rejects)
    func rejectedMessageFailsToOpen(_ vector: MessageVector) {
        #expect(throws: (any Error).self) { try open(vector) }
    }

    @Test(arguments: blobs)
    func blobOpensToItsImage(_ vector: BlobVector) throws {
        let bytes = SharedBytes.shared
        let image = try DefaultChatCipher.shared.decryptGroupBlob(
            blob: bytes.byteArray(data: Data(hex: vector.blob)),
            groupKey: bytes.byteArray(data: Data(hex: vector.groupKey)),
            chatId: bytes.byteArray(data: Data(hex: vector.chatId)),
            blobId: bytes.byteArray(data: Data(hex: vector.blobId)),
            senderId: bytes.byteArray(data: Data(hex: vector.senderId))
        )
        #expect(bytes.data(bytes: image) == Data(hex: vector.image))
    }

    /// The app's own sealer, built from the recipient's seed, opens the envelope the wrapper made.
    @Test(arguments: wraps)
    func envelopeOpensForItsRecipient(_ vector: WrapVector) throws {
        let recipient = try KeyPair(seed: Seed32(Data(hex: vector.recipientSeed)))
        let wrapper = try KeyPair(seed: Seed32(Data(hex: vector.wrapperSeed)))
        #expect(recipient.publicKey.data == Data(hex: vector.recipientPublicKey))
        #expect(wrapper.publicKey.data == Data(hex: vector.wrapperPublicKey))

        let envelope = ConversationKeyEnvelope(
            scheme: SharedCoreGroupKeySealer.scheme.rawValue,
            nonce: Data(hex: vector.nonce),
            ciphertext: Data(hex: vector.ciphertext)
        )
        let key = try SharedCoreGroupKeySealer().unwrap(
            envelope,
            owner: recipient,
            wrapper: wrapper.publicKey,
            conversationID: ConversationID(data: Data(hex: vector.chatId))
        )
        #expect(key == Data(hex: vector.groupKey))
    }
}

private extension Data {
    init(hex: String) {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self = data
    }
}
