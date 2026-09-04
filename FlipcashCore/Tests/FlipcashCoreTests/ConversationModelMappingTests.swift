//
//  ConversationModelMappingTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("Conversation model proto mapping")
struct ConversationModelMappingTests {

    @Test("Text message maps id, sender, content, timestamp, and unread sequence")
    func textMessageParses() throws {
        let senderUUID = UUID()
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 7 }
            $0.senderID = .with { $0.value = senderUUID.data }
            $0.content = [.with { $0.text = .with { $0.text = "hello" } }]
            $0.ts = .init(date: Date(timeIntervalSince1970: 1_700_000_000))
            $0.unreadSeq = 3
        }

        let message = try #require(ConversationMessage(proto))
        #expect(message.id == MessageID(value: 7))
        #expect(message.senderID == senderUUID)
        #expect(message.content == .text("hello"))
        #expect(message.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(message.unreadSeq == 3)
    }

    @Test("Cash message maps the payment amount")
    func cashMessageParses() throws {
        let mintBytes = Data(repeating: 0x02, count: 32)
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 11 }
            $0.content = [.with {
                $0.cash = .with {
                    $0.intentID = .with { $0.value = Data(repeating: 0x03, count: 32) }
                    $0.amount = .with {
                        $0.currency = "usd"
                        $0.nativeAmount = 5.0
                        $0.quarks = 5_000_000
                        $0.mint = .with { $0.value = mintBytes }
                    }
                }
            }]
        }

        let message = try #require(ConversationMessage(proto))
        guard case .cash(let amount) = message.content else {
            Issue.record("Expected cash content")
            return
        }
        #expect(amount.nativeAmount.value == 5.0)
        #expect(amount.nativeAmount.currency == .usd)
        #expect(amount.onChainAmount.quarks == 5_000_000)
        #expect(amount.mint == (try PublicKey(mintBytes)))
        // A cash message with no explicit action defaults to `.sent`.
        #expect(message.cashAction == .sent)
    }

    @Test("Cash message maps the tipped action")
    func cashMessageMapsTippedAction() throws {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 13 }
            $0.content = [.with {
                $0.cash = .with {
                    $0.verb = .tipped
                    $0.amount = .with {
                        $0.currency = "usd"
                        $0.nativeAmount = 2.0
                        $0.quarks = 2_000_000
                        $0.mint = .with { $0.value = Data(repeating: 0x02, count: 32) }
                    }
                }
            }]
        }

        let message = try #require(ConversationMessage(proto))
        #expect(message.cashAction == .tipped)
    }

    @Test("Cash message with a malformed amount returns nil")
    func cashMessageMalformedAmountReturnsNil() {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 12 }
            // Missing mint bytes — ExchangedFiat(proto:) must reject it.
            $0.content = [.with {
                $0.cash = .with {
                    $0.amount = .with {
                        $0.currency = "usd"
                        $0.nativeAmount = 5.0
                        $0.quarks = 5_000_000
                    }
                }
            }]
        }
        #expect(ConversationMessage(proto) == nil)
    }

    @Test("Message with no content returns nil")
    func nonTextReturnsNil() {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 1 }
        }
        #expect(ConversationMessage(proto) == nil)
    }

    @Test("DM metadata maps conversation id, last message, and last activity")
    func dmMetadataMaps() {
        let conversationBytes = Data(repeating: 0xAB, count: 32)
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = conversationBytes }
            $0.type = .contactDm
            $0.lastActivity = .init(date: Date(timeIntervalSince1970: 1_700_000_500))
            $0.lastMessage = .with {
                $0.messageID = .with { $0.value = 9 }
                $0.content = [.with { $0.text = .with { $0.text = "last" } }]
            }
        }

        let conversation = Conversation(proto)
        #expect(conversation.id == ConversationID(data: conversationBytes))
        #expect(conversation.lastMessage?.content == .text("last"))
        #expect(conversation.lastActivity == Date(timeIntervalSince1970: 1_700_000_500))
        #expect(conversation.type == .contactDm)
    }

    @Test("Metadata maps the tip-DM chat type")
    func dmMetadataMapsTipDmType() {
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = Data(repeating: 0xAB, count: 32) }
            $0.type = .tipDm
        }

        #expect(Conversation(proto).type == .tipDm)
    }

    @Test("Metadata with an unknown chat type maps to contact DM")
    func dmMetadataUnknownTypeDefaultsToContactDm() {
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = Data(repeating: 0xAB, count: 32) }
            $0.type = .unknown
        }

        #expect(Conversation(proto).type == .contactDm)
    }

    @Test("Metadata maps the group chat type and title")
    func dmMetadataMapsGroupTypeAndTitle() {
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = Data(repeating: 0xAB, count: 16) }
            $0.type = .group
            $0.title = "Team Flipcash"
        }

        let conversation = Conversation(proto)
        #expect(conversation.type == .group)
        #expect(conversation.title == "Team Flipcash")
    }

    @Test("An empty title normalizes to nil (DMs never carry one)")
    func dmMetadataEmptyTitleNormalizesToNil() {
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = Data(repeating: 0xAB, count: 32) }
            $0.type = .contactDm
        }

        #expect(Conversation(proto).title == nil)
    }

    @Test("ConversationType round-trips through its proto value")
    func conversationTypeRoundTripsThroughProto() {
        for type in [ConversationType.contactDm, .tipDm, .group] {
            #expect(ConversationType(type.proto) == type)
        }
    }

    @Test("Member maps the profile picture's rendition blob ids")
    func memberMapsProfilePicture() {
        let originalBlob = Data(repeating: 0x0A, count: 16)
        let thumbnailBlob = Data(repeating: 0x0B, count: 16)
        let proto = Flipcash_Chat_V1_Member.with {
            $0.userID = .with { $0.value = UUID().data }
            $0.userProfile = .with {
                $0.profilePicture = .with {
                    $0.renditions = [
                        .with {
                            $0.role = .original
                            $0.blobID = .with { $0.value = originalBlob }
                        },
                        .with {
                            $0.role = .thumbnail
                            $0.blobID = .with { $0.value = thumbnailBlob }
                        },
                    ]
                }
            }
        }

        let member = ConversationMember(proto)
        #expect(member.profilePicture?.blobID == BlobID(data: originalBlob))
        #expect(member.profilePicture?.thumbnailBlobID == BlobID(data: thumbnailBlob))
    }

    /// The handle rides along on the member's embedded profile, so a chat
    /// renders it without a separate fetch — the same second mapping site
    /// Android carries it through.
    @Test("Member maps the handle off its embedded profile")
    func memberMapsUsername() {
        let proto = Flipcash_Chat_V1_Member.with {
            $0.userID = .with { $0.value = UUID().data }
            $0.userProfile = .with {
                $0.displayName = "Ted"
                $0.username = .with { $0.value = "ted_1" }
            }
        }

        #expect(ConversationMember(proto).username?.value == "ted_1")
    }

    @Test("Member has no handle when the profile omits one")
    func memberWithoutUsername() {
        let proto = Flipcash_Chat_V1_Member.with {
            $0.userID = .with { $0.value = UUID().data }
            $0.userProfile = .with { $0.displayName = "Ted" }
        }

        #expect(ConversationMember(proto).username == nil)
    }

    @Test("Member has no profile picture when the profile omits one")
    func memberWithoutProfilePicture() {
        let proto = Flipcash_Chat_V1_Member.with {
            $0.userID = .with { $0.value = UUID().data }
        }

        #expect(ConversationMember(proto).profilePicture == nil)
    }

    @Test("Counterpart excludes the signed-in user")
    func counterpartExcludesSelf() {
        let me = UUID()
        let other = UUID()
        let conversation = Conversation(
            id: ConversationID(data: Data(repeating: 0x01, count: 32)),
            members: [
                ConversationMember(userID: me, displayName: "Me"),
                ConversationMember(userID: other, displayName: "Alice"),
            ],
            lastMessage: nil,
            lastActivity: .now
        )

        #expect(conversation.counterpart(excluding: me)?.userID == other)
    }

    @Test("Member maps the READ pointer's value and read time")
    func memberMapsReadPointerTimestamp() {
        let userUUID = UUID()
        let readAt = Date(timeIntervalSince1970: 1_700_000_000)
        let proto = Flipcash_Chat_V1_Member.with {
            $0.userID = .with { $0.value = userUUID.data }
            $0.pointers = [.with {
                $0.type = .read
                $0.value = .with { $0.value = 8 }
                $0.ts = .init(date: readAt)
            }]
        }

        let member = ConversationMember(proto)
        #expect(member.readPointer == MessageID(value: 8))
        #expect(member.readPointerTimestamp == readAt)
    }

    @Test("Member maps the shared phone number and formats it for display")
    func memberMapsPhoneNumber() {
        let proto = Flipcash_Chat_V1_Member.with {
            $0.userID = .with { $0.value = UUID().data }
            $0.userProfile = .with {
                $0.phoneNumber = .with { $0.value = "+14155550100" }
            }
        }

        let member = ConversationMember(proto)
        #expect(member.phoneE164 == "+14155550100")
        #expect(member.formattedPhoneNumber == "(415) 555-0100")
    }

    @Test("Member has no phone number when the profile omits one")
    func memberWithoutPhoneNumber() {
        let proto = Flipcash_Chat_V1_Member.with {
            $0.userID = .with { $0.value = UUID().data }
        }

        let member = ConversationMember(proto)
        #expect(member.phoneE164 == nil)
        #expect(member.formattedPhoneNumber == nil)
    }

    @Test("counterpartReadReceipt returns the other member's pointer and read time")
    func counterpartReadReceiptReturnsOtherMember() {
        let me = UUID()
        let other = UUID()
        let readAt = Date(timeIntervalSince1970: 1_700_000_000)
        let conversation = Conversation(
            id: ConversationID(data: Data(repeating: 0x01, count: 32)),
            members: [
                ConversationMember(userID: me, displayName: "Me", readPointer: MessageID(value: 4)),
                ConversationMember(userID: other, displayName: "Alice", readPointer: MessageID(value: 6), readPointerTimestamp: readAt),
            ],
            lastMessage: nil,
            lastActivity: .now
        )

        #expect(conversation.counterpartReadReceipt(excluding: me) == ReadReceiptState(pointer: MessageID(value: 6), date: readAt))
    }

    @Test("counterpartReadReceipt is nil before the counterpart has read anything")
    func counterpartReadReceiptNilWithoutPointer() {
        let me = UUID()
        let other = UUID()
        let conversation = Conversation(
            id: ConversationID(data: Data(repeating: 0x01, count: 32)),
            members: [
                ConversationMember(userID: me, displayName: "Me", readPointer: MessageID(value: 4)),
                ConversationMember(userID: other, displayName: "Alice"),
            ],
            lastMessage: nil,
            lastActivity: .now
        )

        #expect(conversation.counterpartReadReceipt(excluding: me) == nil)
    }

    @Test("MessageID paging token is the value as 8 big-endian bytes (server PageTokenFromID contract)")
    func messageIDPagingTokenEncoding() {
        // Mirrors the server's `binary.BigEndian.PutUint64` in
        // messaging.PageTokenFromID — 0x0102030405060708 → bytes 01…08.
        #expect(MessageID(value: 0x0102_0304_0506_0708).pagingToken == Data([1, 2, 3, 4, 5, 6, 7, 8]))
        #expect(MessageID(value: 1).pagingToken == Data([0, 0, 0, 0, 0, 0, 0, 1]))
    }
}

@Suite("ConversationMessage deletion and edit metadata")
struct ConversationMessageMetadataTests {

    private let deleter = UUID()

    @Test("A tombstone carries who deleted it and when")
    func tombstoneCarriesDeletionDetail() throws {
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 9 }
            $0.eventSequence = 3
            $0.content = [.with {
                $0.deleted = .with {
                    $0.deletedTs = .init(date: deletedAt)
                    $0.deletedBy = .with { $0.value = deleter.data }
                }
            }]
        }

        let message = try #require(ConversationMessage(proto))
        guard case .deleted(let deletion) = message.content else {
            Issue.record("expected a deleted message")
            return
        }
        #expect(deletion.deletedBy == deleter)
        #expect(deletion.deletedAt == deletedAt)
    }

    @Test("An edited message keeps the server's edit timestamp")
    func editedMessageKeepsTimestamp() throws {
        let editedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 10 }
            $0.eventSequence = 4
            $0.lastEditedTs = .init(date: editedAt)
            $0.content = [.with { $0.text = .with { $0.text = "fixed" } }]
        }

        let message = try #require(ConversationMessage(proto))
        #expect(message.lastEditedTs == editedAt)
        #expect(message.content == .text("fixed"))
    }

    @Test("A never-edited message has no edit timestamp")
    func unEditedMessageHasNoTimestamp() throws {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 11 }
            $0.eventSequence = 1
            $0.content = [.with { $0.text = .with { $0.text = "hi" } }]
        }

        let message = try #require(ConversationMessage(proto))
        #expect(message.lastEditedTs == nil)
    }

    @Test("replacingContent preserves identity and ordering")
    func replacingContentPreservesIdentity() {
        let original = ConversationMessage(
            id: MessageID(value: 12), senderID: deleter, content: .text("before"),
            date: Date(timeIntervalSince1970: 100), unreadSeq: 4, eventSequence: 7
        )
        let edited = original.replacingContent(.text("after"), lastEditedTs: Date(timeIntervalSince1970: 200))

        #expect(edited.content == .text("after"))
        #expect(edited.id == original.id)
        #expect(edited.eventSequence == 7)
        #expect(edited.unreadSeq == 4)
        #expect(edited.date == original.date)
        #expect(edited.lastEditedTs == Date(timeIntervalSince1970: 200))
    }
}

@Suite("Reply proto mapping")
struct ConversationMessageReplyMappingTests {

    private func replyProto(repliedTo: UInt64, text: String) -> Flipcash_Messaging_V1_Message {
        .with {
            $0.messageID = .with { $0.value = 42 }
            $0.content = [
                .with { content in
                    content.reply = .with { reply in
                        reply.repliedMessageID = .with { $0.value = repliedTo }
                        reply.content = [.with { inner in inner.text = .with { $0.text = text } }]
                    }
                }
            ]
        }
    }

    @Test("A reply proto maps to a text message carrying the replied-to id")
    func replyProto_unwrapsToText() throws {
        let message = try #require(ConversationMessage(replyProto(repliedTo: 7, text: "on my way")))
        #expect(message.content == .text("on my way"))
        #expect(message.repliedTo == MessageID(value: 7))
    }

    @Test("A plain text proto carries no replied-to id")
    func textProto_hasNoRepliedTo() throws {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 43 }
            $0.content = [.with { $0.text = .with { $0.text = "hi" } }]
        }
        let message = try #require(ConversationMessage(proto))
        #expect(message.repliedTo == nil)
    }

    @Test("A reply whose inner content is empty is dropped rather than rendered blank")
    func replyProto_withoutInnerContent_isDropped() {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 44 }
            $0.content = [
                .with { content in
                    content.reply = .with { reply in
                        reply.repliedMessageID = .with { $0.value = 7 }
                    }
                }
            ]
        }
        #expect(ConversationMessage(proto) == nil)
    }

    @Test("replacingContent preserves the replied-to id")
    func replacingContent_preservesRepliedTo() {
        let message = ConversationMessage(
            id: MessageID(value: 1),
            senderID: nil,
            content: .text("first"),
            date: Date(timeIntervalSince1970: 0),
            unreadSeq: 0,
            repliedTo: MessageID(value: 9)
        )
        let edited = message.replacingContent(.text("second"), lastEditedTs: Date(timeIntervalSince1970: 1))
        #expect(edited.repliedTo == MessageID(value: 9))
    }
}
