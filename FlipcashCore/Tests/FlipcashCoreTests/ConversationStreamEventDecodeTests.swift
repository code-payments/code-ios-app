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

    @Test("TitleChanged decodes to a titleChanged event")
    func titleChanged() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.metadataUpdates = [.with {
                    $0.titleChanged = .with { $0.newTitle = "New title" }
                }]
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        guard case .titleChanged(let conversationID, let title) = decoded.first else {
            Issue.record("expected .titleChanged"); return
        }
        #expect(conversationID == ConversationID(data: conversationBytes))
        #expect(title == "New title")
    }

    @Test("PictureChanged decodes to a pictureChanged event")
    func pictureChanged() {
        let blobBytes = Data(repeating: 0x01, count: 16)
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.metadataUpdates = [.with {
                    $0.pictureChanged = .with {
                        $0.newPicture = .with {
                            $0.renditions = [.with {
                                $0.role = .original
                                $0.blobID = .with { $0.value = blobBytes }
                            }]
                        }
                    }
                }]
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        guard case .pictureChanged(let conversationID, let picture) = decoded.first else {
            Issue.record("expected .pictureChanged"); return
        }
        #expect(conversationID == ConversationID(data: conversationBytes))
        #expect(picture.blobID == BlobID(data: blobBytes))
    }

    @Test("PictureChanged with no picture set decodes to nothing")
    func pictureChangedWithoutPicture() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.metadataUpdates = [.with {
                    $0.pictureChanged = .init()
                }]
            }
        }

        #expect(ConversationStreamEvent.decode(event).isEmpty)
    }

    @Test("An event batch and a metadata update decode to both events in order")
    func combined() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.events = .with { $0.events = [.with { $0.sequence = 5; $0.count = 1; $0.mutations = [sentMutation(5, "ping")] }] }
                $0.metadataUpdates = [.with {
                    $0.lastActivityChanged = .with { $0.newLastActivity = .init(date: Date(timeIntervalSince1970: 1)) }
                }]
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        #expect(decoded.count == 2)
        if case .chatEvents = decoded.first {} else { Issue.record("first should be .chatEvents") }
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
                $0.events = .with { $0.events = [.with { $0.sequence = 1; $0.count = 1; $0.mutations = [sentMutation(1, "hi")] }] }
                $0.isTypingNotifications = .with { $0.isTypingNotifications = [typing(u1, .startedTyping)] }
            }
        }
        let decoded = ConversationStreamEvent.decode(event)
        #expect(decoded.count == 2)
        #expect(decoded.contains { if case .chatEvents = $0 { true } else { false } })
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
        #expect(tombstone.isDeleted)
        #expect(tombstone.id.value == 3)
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

    // MARK: - Roster updates (ChatUpdate.rosterUpdates)

    private func rosterSummary(_ memberCount: UInt64, _ version: UInt64) -> Flipcash_Chat_V1_RosterSummary {
        .with { $0.memberCount = memberCount; $0.version = version }
    }

    @Test("a join naming the recipient (metadata set) decodes to .joined with the embedded chat snapshot")
    func rosterJoinedAsRecipient() {
        let memberBytes = Data((0..<16).map { UInt8($0) })
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.rosterUpdates = .with {
                    $0.rosterUpdates = [.with {
                        $0.rosterSummary = rosterSummary(2, 3)
                        $0.memberJoined = .with {
                            $0.member = .with { $0.userID = .with { $0.value = memberBytes } }
                            $0.metadata = .with { $0.chatID = .with { $0.value = conversationBytes } }
                        }
                    }]
                }
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        guard case .rosterChanged(let conversationID, let updates) = decoded.first else {
            Issue.record("expected .rosterChanged"); return
        }
        #expect(conversationID == ConversationID(data: conversationBytes))
        #expect(updates.count == 1)
        #expect(updates[0].rosterSummary == ConversationRosterSummary(memberCount: 2, version: 3))
        guard case .joined(let member, let chat) = updates[0].change else { Issue.record("expected .joined"); return }
        #expect(member.userID == (try? UUID(data: memberBytes)))
        #expect(chat?.id == ConversationID(data: conversationBytes))
    }

    @Test("a join for another member (no metadata) decodes to .joined with a nil chat")
    func rosterJoinedAsOtherMember() {
        let memberBytes = Data((16..<32).map { UInt8($0) })
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.rosterUpdates = .with {
                    $0.rosterUpdates = [.with {
                        $0.rosterSummary = rosterSummary(3, 4)
                        $0.memberJoined = .with {
                            $0.member = .with { $0.userID = .with { $0.value = memberBytes } }
                        }
                    }]
                }
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        guard case .rosterChanged(_, let updates) = decoded.first else { Issue.record("expected .rosterChanged"); return }
        guard case .joined(_, let chat) = updates[0].change else { Issue.record("expected .joined"); return }
        #expect(chat == nil)
    }

    @Test("a leave naming a member decodes to .left with that member's userID")
    func rosterLeft() {
        let memberBytes = Data((0..<16).map { UInt8($0) })
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.rosterUpdates = .with {
                    $0.rosterUpdates = [.with {
                        $0.rosterSummary = rosterSummary(1, 5)
                        $0.memberLeft = .with { $0.userID = .with { $0.value = memberBytes } }
                    }]
                }
            }
        }

        let decoded = ConversationStreamEvent.decode(event)
        guard case .rosterChanged(_, let updates) = decoded.first else { Issue.record("expected .rosterChanged"); return }
        guard case .left(let userID) = updates[0].change else { Issue.record("expected .left"); return }
        #expect(userID == (try? UUID(data: memberBytes)))
    }

    @Test("an update with no roster summary is dropped rather than decoded without a version to compare")
    func rosterUpdateWithoutSummaryDropped() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.rosterUpdates = .with {
                    $0.rosterUpdates = [.with {
                        $0.memberLeft = .with { $0.userID = .with { $0.value = Data((0..<16).map { UInt8($0) }) } }
                    }]
                }
            }
        }
        #expect(!ConversationStreamEvent.decode(event).contains { if case .rosterChanged = $0 { true } else { false } })
    }

    @Test("reaction updates decode, dropping unknown actions")
    func reactionUpdates() throws {
        let actor = UUID()
        let update: (Flipcash_Messaging_V1_ReactionUpdate.Action) -> Flipcash_Messaging_V1_ReactionUpdate = { action in
            .with {
                $0.messageID = .with { $0.value = 42 }
                $0.emoji = .with { $0.value = "🔥" }
                $0.actor = .with { $0.value = actor.data }
                $0.action = action
                $0.count = 3
                $0.version = 11
                $0.reactedTs = .init(date: Date(timeIntervalSince1970: 50))
            }
        }
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.reactionUpdates = .with { $0.reactionUpdates = [update(.added), update(.removed), update(.unknown)] }
            }
        }

        guard case .reactionsChanged(let conversationID, let updates) = ConversationStreamEvent.decode(event).first else {
            Issue.record("expected .reactionsChanged"); return
        }
        #expect(conversationID == ConversationID(data: conversationBytes))
        #expect(updates.map(\.added) == [true, false])
        #expect(updates.first == DecodedReactionUpdate(
            messageID: MessageID(value: 42), emoji: "🔥", actor: actor, added: true, count: 3, version: 11,
            reactedAt: Date(timeIntervalSince1970: 50)
        ))
    }
}
