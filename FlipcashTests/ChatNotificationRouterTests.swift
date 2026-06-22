import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Chat notification Send Cash target")
struct ChatNotificationRouterTests {
    @Test("Builds a send target from the conversation's counterpart phone")
    func targetFromCounterpart() {
        let id = ConversationID(data: Data(repeating: 0x01, count: 32))
        let me = UUID(); let them = UUID()
        let convo = Conversation(
            id: id,
            members: [
                ConversationMember(userID: me, displayName: "Me"),
                ConversationMember(userID: them, displayName: "", phoneE164: "+15551234567"),
            ],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0)
        )
        let target = ChatNotificationRouter.sendTarget(forChatID: id, conversation: convo, selfUserID: me)
        #expect(target?.phoneE164 == "+15551234567")
        #expect(target?.dmChatID == id.data)
    }

    @Test("No counterpart phone yields no target")
    func noTarget() {
        let id = ConversationID(data: Data(repeating: 0x02, count: 32))
        let me = UUID()
        let convo = Conversation(id: id, members: [ConversationMember(userID: me, displayName: "Me")],
                                 lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 0))
        #expect(ChatNotificationRouter.sendTarget(forChatID: id, conversation: convo, selfUserID: me) == nil)
    }
}
