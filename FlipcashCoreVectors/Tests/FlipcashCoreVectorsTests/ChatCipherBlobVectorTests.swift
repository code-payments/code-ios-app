import Foundation
import Testing
import SharedCore
@testable import FlipcashCore

/// Photo-blob half of `test-vectors/chat_cipher.json`. The canonical copy lives in the orchestrator
/// repo; this one is synced. The vectors fix the nonce, which production draws at random, so only
/// the decrypt direction is reproducible: each blob must open to its image, and each reject must not.
@Suite struct ChatCipherBlobVectorTests {

    struct BlobVector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let chatId: String
        let chatKey: String
        let senderPublicKey: String
        let recipientPublicKey: String
        let blobId: String
        let image: String?
        let blob: String

        var testDescription: String { name }
    }

    struct Member: Decodable, Sendable {
        let edSeed: String
        let edPublicKey: String
    }

    struct ChatKeyVector: Decodable, Sendable {
        let name: String
        let chatId: String
        let memberA: Member
        let memberB: Member
        let chatKey: String
    }

    struct Rejects: Decodable {
        let decryptBlob: [BlobVector]
    }

    struct Fixture: Decodable {
        let chatKey: [ChatKeyVector]
        let blobs: [BlobVector]
        let rejects: Rejects
    }

    static let fixture: Fixture? = try? loadFixture()
    static let blobs: [BlobVector] = fixture?.blobs ?? []
    static let rejects: [BlobVector] = fixture?.rejects.decryptBlob ?? []

    private static func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "chat_cipher", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureLoads() throws {
        let fixture = try Self.loadFixture()
        #expect(!fixture.blobs.isEmpty)
        #expect(!fixture.rejects.decryptBlob.isEmpty)
    }

    private func decrypt(_ vector: BlobVector) throws -> Data {
        let bytes = SharedBytes.shared
        let image = try DefaultChatCipher.shared.decryptBlob(
            blob: bytes.byteArray(data: Data(hex: vector.blob)),
            chatKey: bytes.byteArray(data: Data(hex: vector.chatKey)),
            senderPk: bytes.byteArray(data: Data(hex: vector.senderPublicKey)),
            recipientPk: bytes.byteArray(data: Data(hex: vector.recipientPublicKey)),
            chatId: bytes.byteArray(data: Data(hex: vector.chatId)),
            blobId: bytes.byteArray(data: Data(hex: vector.blobId))
        )
        return bytes.data(bytes: image)
    }

    @Test(arguments: blobs)
    func blobDecryptsToItsImage(_ vector: BlobVector) throws {
        #expect(try decrypt(vector) == Data(hex: vector.image ?? ""))
    }

    @Test(arguments: rejects)
    func rejectedBlobFailsToDecrypt(_ vector: BlobVector) {
        #expect(throws: (any Error).self) { try decrypt(vector) }
    }

    /// `ChatSeal`, built from the members' seeds the way the app builds it, opens the same blobs:
    /// the recipient through the peer's key and the sender's other device through its own.
    @Test(arguments: blobs)
    func chatSealOpensBlobForBothMembers(_ vector: BlobVector) throws {
        let pair = try #require(Self.fixture?.chatKey.first {
            $0.chatId == vector.chatId && $0.memberA.edPublicKey == vector.senderPublicKey
        })
        let alice = try KeyPair(seed: Seed32(Data(hex: pair.memberA.edSeed)))
        let bob = try KeyPair(seed: Seed32(Data(hex: pair.memberB.edSeed)))
        let aliceID = UUID()
        let conversationID = ConversationID(data: Data(hex: vector.chatId))
        let image = Data(hex: vector.image ?? "")
        let sealed = SealedBlob(senderID: aliceID, plaintextSize: image.count)
        let blobID = BlobID(data: Data(hex: vector.blobId))

        let asBob = try ChatSeal(cipher: DefaultChatCipher.shared, owner: bob, peerPublicKey: alice.publicKey, conversationID: conversationID, selfUserID: UUID())
        let asAlice = try ChatSeal(cipher: DefaultChatCipher.shared, owner: alice, peerPublicKey: bob.publicKey, conversationID: conversationID, selfUserID: aliceID)

        #expect(try asBob.decryptBlob(Data(hex: vector.blob), blobID: blobID, sealed: sealed) == image)
        #expect(try asAlice.decryptBlob(Data(hex: vector.blob), blobID: blobID, sealed: sealed) == image)
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
