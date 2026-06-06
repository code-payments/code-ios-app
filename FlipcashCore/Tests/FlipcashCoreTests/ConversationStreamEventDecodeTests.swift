//
//  ConversationStreamEventDecodeTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("ConversationStreamEvent decode")
struct ConversationStreamEventDecodeTests {

    private let conversationBytes = Data(repeating: 0xAB, count: 32)

    private func textMessage(_ id: UInt64, _ text: String) -> Flipcash_Messaging_V1_Message {
        .with {
            $0.messageID = .with { $0.value = id }
            $0.content = [.with { $0.text = .with { $0.text = text } }]
        }
    }

    @Test("New messages decode to a newMessages event")
    func newMessages() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.newMessages = .with { $0.messages = [textMessage(1, "hi"), textMessage(2, "yo")] }
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        #expect(decoded.count == 1)
        guard case .newMessages(let conversationID, let messages) = decoded.first else {
            Issue.record("expected .newMessages"); return
        }
        #expect(conversationID == ConversationID(data: conversationBytes))
        #expect(messages.map(\.text) == ["hi", "yo"])
    }

    @Test("FullRefresh metadata decodes to a metadataRefresh event")
    func metadataRefresh() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.metadataUpdates = [.with {
                    $0.fullRefresh = .with {
                        $0.metadata = .with {
                            $0.chatID = .with { $0.value = conversationBytes }
                            $0.lastActivity = .init(date: Date(timeIntervalSince1970: 500))
                        }
                    }
                }]
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        guard case .metadataRefresh(let conversation) = decoded.first else {
            Issue.record("expected .metadataRefresh"); return
        }
        #expect(conversation.id == ConversationID(data: conversationBytes))
    }

    @Test("LastActivityChanged decodes to a lastActivityChanged event")
    func lastActivityChanged() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.metadataUpdates = [.with {
                    $0.lastActivityChanged = .with { $0.newLastActivity = .init(date: Date(timeIntervalSince1970: 900)) }
                }]
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        guard case .lastActivityChanged(let conversationID, let date) = decoded.first else {
            Issue.record("expected .lastActivityChanged"); return
        }
        #expect(conversationID == ConversationID(data: conversationBytes))
        #expect(date == Date(timeIntervalSince1970: 900))
    }

    @Test("New messages and a metadata update decode to both events in order")
    func combined() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.newMessages = .with { $0.messages = [textMessage(5, "ping")] }
                $0.metadataUpdates = [.with {
                    $0.lastActivityChanged = .with { $0.newLastActivity = .init(date: Date(timeIntervalSince1970: 1)) }
                }]
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        #expect(decoded.count == 2)
        if case .newMessages = decoded.first {} else { Issue.record("first should be .newMessages") }
        if case .lastActivityChanged = decoded.last {} else { Issue.record("last should be .lastActivityChanged") }
    }

    @Test("READ pointer updates decode to a readPointersChanged event; DELIVERED is dropped")
    func readPointers() {
        let userBytes = Data((0..<16).map { UInt8($0) })
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.pointerUpdates = .with {
                    $0.pointers = [
                        .with {
                            $0.type = .read
                            $0.userID = .with { $0.value = userBytes }
                            $0.value = .with { $0.value = 7 }
                        },
                        .with {
                            $0.type = .delivered
                            $0.userID = .with { $0.value = userBytes }
                            $0.value = .with { $0.value = 9 }
                        },
                    ]
                }
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        guard case .readPointersChanged(let conversationID, let pointers) = decoded.first else {
            Issue.record("expected .readPointersChanged"); return
        }
        #expect(conversationID == ConversationID(data: conversationBytes))
        #expect(pointers.map(\.value) == [MessageID(value: 7)])
    }

    @Test("Non-conversation events decode to nothing")
    func nonConversationEventIgnored() {
        #expect(ConversationStreamEvent.decode(Flipcash_Event_V1_Event.with { $0.test = .init() }).isEmpty)
        #expect(ConversationStreamEvent.decode(Flipcash_Event_V1_Event()).isEmpty)
    }
}
