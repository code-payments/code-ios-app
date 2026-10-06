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
            $0.type = .dm
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

    @Test("Metadata maps the group's creator and use_e2ee")
    func dmMetadataMapsCreatorAndUseE2Ee() {
        let creatorUUID = UUID()
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = Data(repeating: 0xAB, count: 32) }
            $0.type = .group
            $0.creator = .with { $0.value = creatorUUID.data }
            $0.useE2Ee = true
        }

        let conversation = Conversation(proto)
        #expect(conversation.creator == creatorUUID)
        #expect(conversation.useE2Ee)
    }

    @Test("Metadata without a creator or use_e2ee maps to nil/false")
    func dmMetadataWithoutCreatorOrUseE2Ee() {
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = Data(repeating: 0xAB, count: 32) }
            $0.type = .contactDm
        }

        let conversation = Conversation(proto)
        #expect(conversation.creator == nil)
        #expect(conversation.useE2Ee == false)
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

    @Test("Metadata maps roster summary, group picture, and rules")
    func dmMetadataMapsRosterSummaryPictureAndRules() {
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = Data(repeating: 0xAB, count: 32) }
            $0.type = .group
            $0.rosterSummary = .with {
                $0.memberCount = 12
                $0.version = 3
            }
            $0.profilePicture = .with {
                $0.renditions = [.with {
                    $0.role = .original
                    $0.blobID = .with { $0.value = Data(repeating: 0x01, count: 16) }
                }]
            }
            $0.rules = .with {
                $0.listener = [.with { $0.staff = .init() }]
                $0.speaker = [.with {
                    $0.minimumBalance = .with {
                        $0.amount = .with {
                            $0.currency = "usd"
                            $0.nativeAmount = 5.0
                        }
                    }
                }]
            }
        }

        let conversation = Conversation(proto)
        #expect(conversation.rosterSummary == ConversationRosterSummary(memberCount: 12, version: 3))
        #expect(conversation.picture != nil)
        #expect(conversation.coverPicture == nil)
        #expect(conversation.rules?.listener == [.staff])
        #expect(conversation.rules?.speaker == [.minimumBalance(MinimumBalanceRequirement(amount: .usd(5.0)))])
    }

    @Test("Metadata cover_picture maps to coverPicture, apart from the profile picture")
    func coverPictureMaps() {
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = Data(repeating: 0xAB, count: 32) }
            $0.type = .group
            $0.coverPicture = .with {
                $0.renditions = [.with {
                    $0.role = .original
                    $0.blobID = .with { $0.value = Data(repeating: 0x07, count: 16) }
                }]
            }
        }

        let conversation = Conversation(proto)
        #expect(conversation.coverPicture?.blobID == BlobID(data: Data(repeating: 0x07, count: 16)))
        #expect(conversation.picture == nil)
    }

    @Test("Metadata without roster summary or rules maps to defaults")
    func dmMetadataWithoutRosterSummaryOrRulesMapsToDefaults() {
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = Data(repeating: 0xAB, count: 32) }
            $0.type = .contactDm
        }

        let conversation = Conversation(proto)
        #expect(conversation.rosterSummary == ConversationRosterSummary(memberCount: 0, version: 0))
        #expect(conversation.picture == nil)
        #expect(conversation.rules == nil)
    }

    @Test("A rules requirement in an unrecognized currency is dropped")
    func dmMetadataRulesWithUnrecognizedCurrencyIsDropped() {
        let proto = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = Data(repeating: 0xAB, count: 32) }
            $0.type = .group
            $0.rules = .with {
                $0.listener = [.with {
                    $0.minimumBalance = .with {
                        $0.amount = .with { $0.currency = "zzz" }
                    }
                }]
            }
        }

        #expect(Conversation(proto).rules?.listener == [])
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

    @Test("Member maps joinedAt and version, the GetRoster merge key")
    func memberMapsJoinedAtAndVersion() {
        let joinedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let proto = Flipcash_Chat_V1_Member.with {
            $0.userID = .with { $0.value = UUID().data }
            $0.joinedAt = .init(date: joinedAt)
            $0.version = 5
        }

        let member = ConversationMember(proto)
        #expect(member.joinedAt == joinedAt)
        #expect(member.version == 5)
    }

    @Test("Member without joinedAt/version maps to nil/zero (a DM participant, or a member joined at creation)")
    func memberWithoutJoinedAtOrVersion() {
        let proto = Flipcash_Chat_V1_Member.with {
            $0.userID = .with { $0.value = UUID().data }
        }

        let member = ConversationMember(proto)
        #expect(member.joinedAt == nil)
        #expect(member.version == 0)
    }

    @Test("ViewerState maps permissions.canEdit")
    func viewerStateMapsCanEdit() {
        let proto = Flipcash_Chat_V1_ViewerState.with {
            $0.version = 2
            $0.permissions = .with { $0.canEdit = true }
        }

        #expect(ConversationViewerState(proto).canEdit)
    }

    @Test("ViewerState without permissions defaults canEdit to false (never derivable client-side)")
    func viewerStateWithoutPermissionsDefaultsCanEditFalse() {
        let proto = Flipcash_Chat_V1_ViewerState.with {
            $0.version = 2
        }

        #expect(ConversationViewerState(proto).canEdit == false)
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

    @Test("Encrypted content maps to .encrypted, keeping scheme, nonce, and ciphertext")
    func encryptedMessageParses() throws {
        let nonce = Data(repeating: 0xCD, count: 24)
        let ciphertext = Data([0x0A, 0x0B, 0x0C])
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 14 }
            $0.content = [.with {
                $0.encrypted = .with {
                    $0.scheme = .x25519Xchacha20Poly1305
                    $0.nonce = nonce
                    $0.ciphertext = ciphertext
                }
            }]
        }

        let message = try #require(ConversationMessage(proto))
        guard case .encrypted(let scheme, let gotNonce, let gotCiphertext) = message.content else {
            Issue.record("Expected encrypted content")
            return
        }
        #expect(scheme == Flipcash_Messaging_V1_EncryptedContent.Scheme.x25519Xchacha20Poly1305.rawValue)
        #expect(gotNonce == nonce)
        #expect(gotCiphertext == ciphertext)
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

@Suite("ConversationMessage.Content -> proto encoding")
struct ConversationMessageContentEncodingTests {

    @Test("Text content encodes to a proto text body")
    func textEncodes() throws {
        let proto = try ConversationMessage.Content.text("hi").asProto()
        guard case .text(let body) = proto.type else {
            Issue.record("Expected text content")
            return
        }
        #expect(body.text == "hi")
    }

    @Test("Encrypted content round-trips scheme, nonce, and ciphertext byte for byte -- not decrypted, just re-encoded")
    func encryptedContentRoundTrips() throws {
        let nonce = Data(repeating: 0xEF, count: 24)
        let ciphertext = Data([0x01, 0x02, 0x03])
        let content = ConversationMessage.Content.encrypted(
            scheme: Flipcash_Messaging_V1_EncryptedContent.Scheme.x25519Xchacha20Poly1305.rawValue,
            nonce: nonce,
            ciphertext: ciphertext
        )

        let proto = try content.asProto()
        guard case .encrypted(let encrypted) = proto.type else {
            Issue.record("Expected encrypted content")
            return
        }
        #expect(encrypted.scheme == .x25519Xchacha20Poly1305)
        #expect(encrypted.nonce == nonce)
        #expect(encrypted.ciphertext == ciphertext)

        // And decoding that proto back gives the identical domain value -- a full round trip.
        let roundTripped = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 1 }
            $0.content = [proto]
        }
        #expect(try #require(ConversationMessage(roundTripped)).content == content)
    }

    @Test("An unrecognized encrypted scheme raw value encodes as .UNRECOGNIZED rather than crashing")
    func unrecognizedSchemeFallsBackToUnknown() throws {
        let content = ConversationMessage.Content.encrypted(scheme: 99, nonce: Data(), ciphertext: Data())
        let proto = try content.asProto()
        guard case .encrypted(let encrypted) = proto.type else {
            Issue.record("Expected encrypted content")
            return
        }
        #expect(encrypted.scheme == .UNRECOGNIZED(99))
    }

    @Test("Cash and deleted content throw rather than crash -- there is no wire shape a client resends for either")
    func cashAndDeletedThrow() {
        let cash = ConversationMessage.Content.cash(ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 1, mint: .usdf),
            nativeAmount: FiatAmount(value: 1, currency: .usd),
            currencyRate: Rate(fx: 1, currency: .usd)
        ))
        #expect(throws: ConversationMessageContentEncodingError.self) { try cash.asProto() }

        let deleted = ConversationMessage.Content.deleted(.init(deletedBy: nil, deletedAt: .now))
        #expect(throws: ConversationMessageContentEncodingError.self) { try deleted.asProto() }
    }

    @Test("The never speaker rule round-trips through the proto")
    func neverSpeakerRuleRoundTrips() {
        let proto = ConversationSpeakerRule.never.proto
        #expect(ConversationSpeakerRule(proto) == .never)
    }

    @Test("The creator speaker rule round-trips through the proto")
    func creatorSpeakerRuleRoundTrips() {
        let proto = ConversationSpeakerRule.creator.proto
        #expect(proto.creator == .init())
        #expect(ConversationSpeakerRule(proto) == .creator)
    }

    @Test("An unset speaker rule maps to unsupported instead of being dropped")
    func unsetSpeakerRuleMapsToUnsupported() {
        #expect(ConversationSpeakerRule(Flipcash_Chat_V1_SpeakerRules()) == .unsupported)
        let rules = ConversationRules(Flipcash_Chat_V1_Rules.with {
            $0.speaker = [.init(), .with { $0.creator = .init() }]
        })
        #expect(rules.speaker == [.unsupported, .creator])
    }

    @Test("Unsupported speaker rules survive the store's JSON encoding")
    func unsupportedSpeakerRuleRoundTripsThroughJSON() throws {
        let rules = ConversationRules(speaker: [.unsupported, .creator])
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode(ConversationRules.self, from: data) == rules)
    }

    @Test("A share-profile widget maps to its domain model")
    func shareProfileWidgetMaps() throws {
        let proto = Flipcash_Messaging_V1_WidgetContent.with {
            $0.shareProfile = .with { $0.username = .with { $0.value = "alice" } }
        }
        #expect(proto.shareProfile == ShareProfileWidget(username: try #require(Username("alice"))))
        #expect(Flipcash_Messaging_V1_WidgetContent().shareProfile == nil)
    }

    @Test("A share-profile widget message is kept as a widget")
    func widgetMessageIsKept() throws {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 9 }
            $0.content = [.with {
                $0.widget = .with { $0.shareProfile = .with { $0.username = .with { $0.value = "alice" } } }
            }]
        }
        let message = try #require(ConversationMessage(proto))
        #expect(message.content == .widget(.shareProfile(ShareProfileWidget(username: try #require(Username("alice"))))))
    }

    @Test("A widget of an unknown variant is kept as unrecognized, not dropped")
    func unknownWidgetIsUnrecognized() throws {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 9 }
            $0.content = [.with { $0.widget = .init() }]
        }
        let message = try #require(ConversationMessage(proto))
        #expect(message.content == .widget(.unrecognized))
    }

    @Test("A widget can't be sent through the content encoder")
    func widgetIsNotEncodable() throws {
        let widget = ConversationMessage.Content.widget(.shareProfile(ShareProfileWidget(username: try #require(Username("alice")))))
        #expect(throws: ConversationMessageContentEncodingError.self) { try widget.asProto() }
    }
}

@Suite("Media proto mapping")
struct ConversationMessageMediaMappingTests {

    private let blobID = BlobID(data: Data([1, 2, 3]))
    private let blurhash = "L6PZfSi_.AyE_3t7t7R**0o#DgR4"

    private func media(withDownloadURL: Bool = true) -> Flipcash_Blob_V1_Media {
        .with {
            $0.renditions = [
                .with {
                    $0.role = .thumbnail
                    $0.blobID = .with { $0.value = Data([9]) }
                    $0.blob.image.width = 50
                    $0.blob.image.height = 100
                },
                .with {
                    $0.role = .original
                    $0.blobID = .with { $0.value = blobID.data }
                    $0.blob.image.width = 100
                    $0.blob.image.height = 200
                    $0.blob.image.blurhash = blurhash
                    if withDownloadURL {
                        $0.blob.downloadURL = .with { $0.url = "https://example.com/blob" }
                    }
                },
            ]
        }
    }

    private func mediaProto(caption: String?, redacted: Bool = false) -> Flipcash_Messaging_V1_Message {
        .with {
            $0.messageID = .with { $0.value = 50 }
            $0.redacted = redacted
            $0.content = [.with {
                $0.media = .with {
                    $0.items = [media(withDownloadURL: !redacted)]
                    if let caption {
                        $0.caption = .with { $0.text = caption }
                    }
                }
            }]
        }
    }

    @Test("A media message maps its ORIGINAL rendition and caption")
    func mediaMapsOriginalAndCaption() throws {
        let message = try #require(ConversationMessage(mediaProto(caption: "from today")))

        let expected = MediaAttachment(blobID: blobID, width: 100, height: 200, blurhash: blurhash)
        #expect(message.content == .media([expected], caption: "from today"))
        #expect(message.repliedTo == nil)
        #expect(message.redacted == false)
    }

    @Test("A media message without a caption, or with an empty one, has a nil caption")
    func mediaWithoutCaption() throws {
        for caption in [nil, ""] as [String?] {
            let message = try #require(ConversationMessage(mediaProto(caption: caption)))
            guard case .media(_, let mapped) = message.content else {
                Issue.record("expected .media content")
                return
            }
            #expect(mapped == nil)
        }
    }

    @Test("A redacted media message stays .media with its blurhash, flagged redacted — never a tombstone")
    func redactedMediaStaysMedia() throws {
        let message = try #require(ConversationMessage(mediaProto(caption: "hidden", redacted: true)))

        guard case .media(let attachments, _) = message.content else {
            Issue.record("expected .media content, got \(message.content)")
            return
        }
        #expect(attachments.first?.blurhash == blurhash)
        #expect(attachments.first?.width == 100)
        #expect(message.redacted)
        #expect(!message.isDeleted)
    }

    @Test("A media item with no ORIGINAL rendition is dropped")
    func mediaWithoutOriginalIsDropped() {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 51 }
            $0.content = [.with {
                $0.media = .with {
                    $0.items = [.with { $0.renditions = [.with { $0.role = .thumbnail }] }]
                }
            }]
        }
        #expect(ConversationMessage(proto) == nil)
    }

    @Test("A reply carrying media unwraps to .media with the replied-to id")
    func replyWithMediaUnwraps() throws {
        let inner = media()
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = .with { $0.value = 52 }
            $0.content = [.with { content in
                content.reply = .with { reply in
                    reply.repliedMessageID = .with { $0.value = 7 }
                    reply.content = [.with { $0.media = .with { $0.items = [inner] } }]
                }
            }]
        }

        let message = try #require(ConversationMessage(proto))
        let expected = MediaAttachment(blobID: blobID, width: 100, height: 200, blurhash: blurhash)
        #expect(message.content == .media([expected], caption: nil))
        #expect(message.repliedTo == MessageID(value: 7))
    }

    @Test("Media content encodes to a single ORIGINAL rendition with its caption")
    func mediaEncodes() throws {
        let attachment = MediaAttachment(blobID: blobID, width: 100, height: 200, blurhash: blurhash)
        let proto = try ConversationMessage.Content.media([attachment], caption: "from today").asProto()

        guard case .media(let media) = proto.type else {
            Issue.record("Expected media content")
            return
        }
        #expect(media.items.count == 1)
        #expect(media.items.first?.renditions.map(\.role) == [.original])
        #expect(media.items.first?.renditions.first?.blobID.value == blobID.data)
        #expect(media.caption.text == "from today")
    }

    @Test("Media without a caption encodes no caption")
    func mediaEncodesWithoutCaption() throws {
        let attachment = MediaAttachment(blobID: blobID, width: 100, height: 200, blurhash: nil)
        let proto = try ConversationMessage.Content.media([attachment], caption: nil).asProto()

        guard case .media(let media) = proto.type else {
            Issue.record("Expected media content")
            return
        }
        #expect(!media.hasCaption)
    }

    @Test("Media with no blob, or more than one attachment, throws rather than sending a partial message")
    func stagedMediaThrows() {
        let uploaded = MediaAttachment(blobID: blobID, width: 1, height: 1, blurhash: nil)
        let pending = MediaAttachment(blobID: nil, width: 1, height: 1, blurhash: nil)

        #expect(throws: ConversationMessageContentEncodingError.self) {
            try ConversationMessage.Content.media([pending], caption: nil).asProto()
        }
        #expect(throws: ConversationMessageContentEncodingError.self) {
            try ConversationMessage.Content.media([uploaded, uploaded], caption: nil).asProto()
        }
        #expect(throws: ConversationMessageContentEncodingError.self) {
            try ConversationMessage.Content.media([], caption: nil).asProto()
        }
    }
}
