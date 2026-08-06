import Testing
import Foundation
@testable import FlipcashCore
import FlipcashAPI

@Suite("ChatPaymentMetadata serialization")
struct ChatPaymentMetadataTests {

    private let chatID = ConversationID(data: Data(repeating: 0xAB, count: 32))

    @Test("Contact DM payments carry the chat id and both phones")
    func contactDmSerialization() throws {
        let metadata = ChatPaymentMetadata.contactDm(
            chatID: chatID,
            sourcePhoneE164: "+15551230001",
            destinationPhoneE164: "+15551230002"
        )

        let decoded = try Flipcash_Intent_V1_AppMetadata(serializedBytes: metadata.serializedAppMetadata())

        #expect(decoded.chat.chatID.value == chatID.data)
        guard case .contactDmPayment(let payment) = decoded.chat.type else {
            Issue.record("Expected contactDmPayment, got \(String(describing: decoded.chat.type))")
            return
        }
        #expect(payment.source.value == "+15551230001")
        #expect(payment.destination.value == "+15551230002")
    }

    @Test("Tip DM payments carry the chat id and the tipcard origin")
    func tipDmTipcardSerialization() throws {
        let metadata = ChatPaymentMetadata.tipDm(chatID: chatID, origin: .tipcard)

        let decoded = try Flipcash_Intent_V1_AppMetadata(serializedBytes: metadata.serializedAppMetadata())

        #expect(decoded.chat.chatID.value == chatID.data)
        guard case .tipDmPayment(let payment) = decoded.chat.type else {
            Issue.record("Expected tipDmPayment, got \(String(describing: decoded.chat.type))")
            return
        }
        #expect(payment.location == .tipcard)
    }

    @Test("Tip DM payments carry the chat origin when sent from a chat")
    func tipDmChatSerialization() throws {
        let metadata = ChatPaymentMetadata.tipDm(chatID: chatID, origin: .chat)

        let decoded = try Flipcash_Intent_V1_AppMetadata(serializedBytes: metadata.serializedAppMetadata())

        #expect(decoded.chat.chatID.value == chatID.data)
        guard case .tipDmPayment(let payment) = decoded.chat.type else {
            Issue.record("Expected tipDmPayment, got \(String(describing: decoded.chat.type))")
            return
        }
        #expect(payment.location == .chat)
    }

    @Test("Each variant exposes its chat id uniformly")
    func chatIDAccessor() {
        let contact = ChatPaymentMetadata.contactDm(
            chatID: chatID,
            sourcePhoneE164: "+15551230001",
            destinationPhoneE164: "+15551230002"
        )
        let tip = ChatPaymentMetadata.tipDm(chatID: chatID, origin: .tipcard)

        #expect(contact.chatID == chatID)
        #expect(tip.chatID == chatID)
    }
}
