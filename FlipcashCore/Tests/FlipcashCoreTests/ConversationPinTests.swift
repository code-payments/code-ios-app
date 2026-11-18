//
//  ConversationPinTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("Conversation pins")
struct ConversationPinTests {

    private let conversationBytes = Data(repeating: 0xAB, count: 32)
    private let userBytes = Data(repeating: 0x11, count: 16)

    private func pinProto(_ id: UInt64, text: String = "hi") -> Flipcash_Chat_V1_Pin {
        .with {
            $0.messageID = .with { $0.value = id }
            $0.pinnedBy = .with { $0.value = userBytes }
            $0.pinnedAt = .init(date: Date(timeIntervalSince1970: 700))
            $0.message = .with {
                $0.messageID = .with { $0.value = id }
                $0.ts = .init(date: Date(timeIntervalSince1970: 600))
                $0.content = [.with { $0.text = .with { $0.text = text } }]
            }
        }
    }

    private func summaryProto(count: UInt32, version: UInt64, latest: UInt64? = nil) -> Flipcash_Chat_V1_PinSummary {
        .with {
            $0.count = count
            $0.version = version
            if let latest { $0.latest = pinProto(latest) }
        }
    }

    private func conversationID(_ byte: UInt8 = 1) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 32))
    }

    private func conversation(pinSummary: ConversationPinSummary?) -> Conversation {
        Conversation(id: conversationID(), members: [], lastMessage: nil, lastActivity: Date(timeIntervalSince1970: 0), pinSummary: pinSummary)
    }

    // MARK: - Cache bytes

    @Test("A pin restored from its serialized bytes keeps the pinned message")
    func serializedBytesRoundTrip() throws {
        let pin = ConversationPin(pinProto(7, text: "pinned"))
        let bytes = try #require(pin.serializedBytes)
        let restored = try #require(ConversationPin(serializedBytes: bytes))
        #expect(restored == pin)
        #expect(restored.message?.content == .text("pinned"))
        #expect(restored.serializedBytes == bytes)
    }

    @Test("Bytes that are not a pin do not restore")
    func garbageBytesDoNotRestore() {
        #expect(ConversationPin(serializedBytes: Data([0xFF, 0xFF, 0xFF])) == nil)
    }

    // MARK: - Mapping

    @Test("Pin maps ids, pinner, time and message")
    func pinMaps() {
        let pin = ConversationPin(pinProto(7, text: "pinned"))
        #expect(pin.messageID == MessageID(value: 7))
        #expect(pin.pinnedBy == (try? UUID(data: userBytes)))
        #expect(pin.pinnedAt == Date(timeIntervalSince1970: 700))
        #expect(pin.message?.content == .text("pinned"))
        #expect(!pin.isDeleted)
    }

    @Test("A pin whose message was deleted reports isDeleted")
    func deletedPin() {
        var proto = pinProto(7)
        proto.message.content = [.with { $0.deleted = .init() }]
        let pin = ConversationPin(proto)
        #expect(pin.isDeleted)
    }

    @Test("PinSummary maps latest, count and version; latest is optional")
    func summaryMaps() {
        let summary = ConversationPinSummary(summaryProto(count: 2, version: 9, latest: 7))
        #expect(summary.count == 2)
        #expect(summary.version == 9)
        #expect(summary.latest?.messageID == MessageID(value: 7))
        #expect(ConversationPinSummary(summaryProto(count: 0, version: 1)).latest == nil)
    }

    @Test("Metadata carries pinSummary only when set")
    func metadataMapsPinSummary() {
        let withSummary = Flipcash_Chat_V1_Metadata.with {
            $0.chatID = .with { $0.value = conversationBytes }
            $0.pinSummary = summaryProto(count: 1, version: 4)
        }
        #expect(Conversation(withSummary).pinSummary?.version == 4)
        #expect(Conversation(.with { $0.chatID = .with { $0.value = conversationBytes } }).pinSummary == nil)
    }

    @Test("Viewer state maps canPin and defaults it to false")
    func viewerStateMapsCanPin() {
        let granted = ConversationViewerState(.with { $0.permissions = .with { $0.canPin = true } })
        #expect(granted.canPin)
        #expect(!ConversationViewerState(.init()).canPin)
    }

    // MARK: - Stream decode

    @Test("PinsChanged with a pin decodes to pinsChanged(.pinned)")
    func decodePinned() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.metadataUpdates = [.with {
                    $0.pinsChanged = .with {
                        $0.pinned = pinProto(7)
                        $0.summary = summaryProto(count: 1, version: 3, latest: 7)
                    }
                }]
            }
        }

        guard case .pinsChanged(let id, let change, let summary)? = ConversationStreamEvent.decode(event).first else {
            Issue.record("expected .pinsChanged"); return
        }
        #expect(id == ConversationID(data: conversationBytes))
        guard case .pinned(let pin)? = change else { Issue.record("expected .pinned"); return }
        #expect(pin.messageID == MessageID(value: 7))
        #expect(summary.version == 3)
    }

    @Test("PinsChanged with an unpin decodes to pinsChanged(.unpinned)")
    func decodeUnpinned() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.metadataUpdates = [.with {
                    $0.pinsChanged = .with {
                        $0.unpinned = .with { $0.value = 7 }
                        $0.summary = summaryProto(count: 0, version: 4)
                    }
                }]
            }
        }

        guard case .pinsChanged(_, let change, let summary)? = ConversationStreamEvent.decode(event).first else {
            Issue.record("expected .pinsChanged"); return
        }
        #expect(change == .unpinned(MessageID(value: 7)))
        #expect(summary.count == 0)
    }

    @Test("PinsChanged without its required summary decodes to nothing")
    func decodeWithoutSummary() {
        let event = Flipcash_Event_V1_Event.with {
            $0.chatUpdate = .with {
                $0.chat = .with { $0.value = conversationBytes }
                $0.metadataUpdates = [.with { $0.pinsChanged = .with { $0.unpinned = .with { $0.value = 7 } } }]
            }
        }
        #expect(ConversationStreamEvent.decode(event).isEmpty)
    }

    // MARK: - Store

    @Test("A pin summary applies only when its version is greater")
    func storeAppliesGreaterVersion() {
        var store = ConversationStore()
        store.setFeed([conversation(pinSummary: ConversationPinSummary(latest: nil, count: 1, version: 5))])

        store.applyPinsChanged(ConversationPinSummary(latest: nil, count: 9, version: 4), in: conversationID())
        store.applyPinsChanged(ConversationPinSummary(latest: nil, count: 9, version: 5), in: conversationID())
        #expect(store.conversations[0].pinSummary?.count == 1)

        store.applyPinsChanged(ConversationPinSummary(latest: nil, count: 2, version: 6), in: conversationID())
        #expect(store.conversations[0].pinSummary?.count == 2)
    }

    @Test("A feed copy without a pin summary, or with an older one, keeps the held summary")
    func feedKeepsHeldSummary() {
        var store = ConversationStore()
        store.setFeed([conversation(pinSummary: ConversationPinSummary(latest: nil, count: 3, version: 8))])

        store.setFeed([conversation(pinSummary: nil)])
        #expect(store.conversations[0].pinSummary?.version == 8)

        store.setFeed([conversation(pinSummary: ConversationPinSummary(latest: nil, count: 1, version: 2))])
        #expect(store.conversations[0].pinSummary?.version == 8)

        store.setFeed([conversation(pinSummary: ConversationPinSummary(latest: nil, count: 4, version: 9))])
        #expect(store.conversations[0].pinSummary?.version == 9)
    }

    @Test("Pin results map positionally and unknown raw values fall to nil")
    func resultEnumsMapPositionally() {
        typealias R = Flipcash_Chat_V1_PinMessageResponse.Result
        #expect(ErrorPinMessage(rawValue: R.ok.rawValue) == .ok)
        #expect(ErrorPinMessage(rawValue: R.denied.rawValue) == .denied)
        #expect(ErrorPinMessage(rawValue: R.notFound.rawValue) == .notFound)
        #expect(ErrorPinMessage(rawValue: R.messageNotFound.rawValue) == .messageNotFound)
        #expect(ErrorPinMessage(rawValue: R.tooManyPins.rawValue) == .tooManyPins)
        #expect(ErrorPinMessage(rawValue: R.messageNotAllowed.rawValue) == .messageNotAllowed)
        #expect(ErrorUnpinMessage(rawValue: Flipcash_Chat_V1_UnpinMessageResponse.Result.notFound.rawValue) == .notFound)
        #expect(ErrorGetPinnedMessages(rawValue: Flipcash_Chat_V1_GetPinnedMessagesResponse.Result.denied.rawValue) == .denied)
    }
}
