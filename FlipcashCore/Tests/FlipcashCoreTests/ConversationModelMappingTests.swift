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
