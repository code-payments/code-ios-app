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
        #expect(messages.map(\.content) == [.text("hi"), .text("yo")])
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

    @Test("READ pointer updates decode to a readPointersChanged event with the read time; DELIVERED is dropped")
    func readPointers() {
        let userBytes = Data((0..<16).map { UInt8($0) })
        let readAt = Date(timeIntervalSince1970: 1_700_000_000)
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.pointerUpdates = .with {
                    $0.pointers = [
                        .with {
                            $0.type = .read
                            $0.userID = .with { $0.value = userBytes }
                            $0.value = .with { $0.value = 7 }
                            $0.ts = .init(date: readAt)
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
        #expect(pointers.map(\.date) == [readAt])
    }

    @Test("Non-conversation events decode to nothing")
    func nonConversationEventIgnored() {
        #expect(ConversationStreamEvent.decode(Flipcash_Event_V1_Event.with { $0.test = .init() }).isEmpty)
        #expect(ConversationStreamEvent.decode(Flipcash_Event_V1_Event()).isEmpty)
    }

    private func typing(_ user: Data, _ state: Flipcash_Messaging_V1_IsTypingNotification.State) -> Flipcash_Messaging_V1_IsTypingNotification {
        .with { $0.userID = .with { $0.value = user }; $0.state = state }
    }

    @Test("started/still typing decodes to active notifications; stopped/timed-out to inactive; unknown is dropped")
    func typingNotifications() throws {
        let u1 = Data((0..<16).map { UInt8($0) })
        let u2 = Data((16..<32).map { UInt8($0) })
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.isTypingNotifications = .with {
                    $0.isTypingNotifications = [
                        typing(u1, .startedTyping),
                        typing(u2, .stoppedTyping),
                        typing(u1, .unknownTypingState),
                    ]
                }
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        guard case .typingChanged(let conversationID, let notifications) = decoded.first else {
            Issue.record("expected .typingChanged"); return
        }
        #expect(conversationID == ConversationID(data: conversationBytes))
        #expect(notifications.count == 2) // unknown dropped
        #expect(notifications.contains(TypingNotification(userID: try UUID(data: u1), isActive: true)))
        #expect(notifications.contains(TypingNotification(userID: try UUID(data: u2), isActive: false)))
    }

    @Test("an empty typing batch produces no typing event")
    func typingEmpty() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with { $0.chat = .with { $0.value = conversationBytes } }
        }
        #expect(!ConversationStreamEvent.decode(event).contains { if case .typingChanged = $0 { true } else { false } })
    }

    @Test("messages and typing in one update decode to both events")
    func messagesAndTyping() {
        let u1 = Data((0..<16).map { UInt8($0) })
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.newMessages = .with { $0.messages = [textMessage(1, "hi")] }
                $0.isTypingNotifications = .with { $0.isTypingNotifications = [typing(u1, .startedTyping)] }
            }
        }
        let decoded = ConversationStreamEvent.decode(event)
        #expect(decoded.count == 2)
        #expect(decoded.contains { if case .newMessages = $0 { true } else { false } })
        #expect(decoded.contains { if case .typingChanged = $0 { true } else { false } })
    }

    // MARK: - Event log (ChatUpdate.events)

    private func sentMutation(_ id: UInt64, _ text: String) -> Flipcash_Messaging_V1_Mutation {
        .with { $0.messageSent = textMessage(id, text) }
    }

    @Test("chatEvents decode: sent + deleted carry sequence/count; a delete materializes a tombstone, not nil")
    func chatEventsDecode() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.events = .with {
                    $0.events = [
                        .with { $0.sequence = 6; $0.count = 1; $0.mutations = [sentMutation(6, "hi")] },
                        .with {
                            $0.sequence = 7; $0.count = 1
                            $0.mutations = [.with { $0.messageDeleted = .with { $0.messageID = .with { $0.value = 3 }; $0.content = [.with { $0.deleted = .init() }] } }]
                        },
                    ]
                }
            }
        }
        let decoded = ConversationStreamEvent.decode(event)
        guard case .chatEvents(let cid, let events) = decoded.first else { Issue.record("expected .chatEvents"); return }
        #expect(cid == ConversationID(data: conversationBytes))
        #expect(events.map(\.sequence) == [6, 7])
        #expect(events.map(\.count) == [1, 1])
        guard case .sent(let sent) = events[0].mutations.first else { Issue.record("expected .sent"); return }
        #expect(sent.content == .text("hi"))
        guard case .deleted(let tombstone) = events[1].mutations.first else { Issue.record("expected .deleted"); return }
        #expect(tombstone.content == .deleted)
        #expect(tombstone.id.value == 3)
    }

    @Test("both events and new_messages present decode to both (additive migration gate)")
    func chatEventsAndNewMessagesAdditive() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.newMessages = .with { $0.messages = [textMessage(9, "dup")] }
                $0.events = .with { $0.events = [.with { $0.sequence = 9; $0.count = 1; $0.mutations = [sentMutation(9, "dup")] }] }
            }
        }
        let decoded = ConversationStreamEvent.decode(event)
        #expect(decoded.contains { if case .chatEvents = $0 { true } else { false } })
        #expect(decoded.contains { if case .newMessages = $0 { true } else { false } })
    }

    @Test("an absent events batch does not suppress new_messages (deprecated path still works)")
    func emptyEventsKeepsNewMessages() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.newMessages = .with { $0.messages = [textMessage(1, "keep")] }
            }
        }
        let decoded = ConversationStreamEvent.decode(event)
        #expect(decoded.contains { if case .newMessages = $0 { true } else { false } })
        #expect(!decoded.contains { if case .chatEvents = $0 { true } else { false } })
    }

    @Test("an event whose only mutation is unrepresentable still carries sequence/count so the cursor advances")
    func unrepresentableMutationStillAdvances() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.events = .with {
                    $0.events = [.with {
                        $0.sequence = 12; $0.count = 1
                        $0.mutations = [.with { $0.messageSent = .with { $0.messageID = .with { $0.value = 12 }; $0.content = [.with { $0.reply = .init() }] } }]
                    }]
                }
            }
        }
        let decoded = ConversationStreamEvent.decode(event)
        guard case .chatEvents(_, let events) = decoded.first else { Issue.record("expected .chatEvents"); return }
        #expect(events.count == 1)
        #expect(events[0].sequence == 12)
        #expect(events[0].mutations.isEmpty) // reply content unrepresentable → dropped, event survives
    }
}
