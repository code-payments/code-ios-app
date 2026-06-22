//
//  ChatSpotlightItemTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Chat Spotlight item mapping")
struct ChatSpotlightItemTests {

    private func conversation(byte: UInt8, lastMessage: ConversationMessage?) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: byte, count: 32)),
            members: [],
            lastMessage: lastMessage,
            lastActivity: Date(timeIntervalSince1970: 0)
        )
    }

    private func textMessage(_ text: String) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: 1),
            senderID: nil,
            content: .text(text),
            date: Date(timeIntervalSince1970: 0),
            unreadSeq: 0
        )
    }

    private func cashMessage(_ amount: ExchangedFiat) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: 2),
            senderID: nil,
            content: .cash(amount),
            date: Date(timeIntervalSince1970: 0),
            unreadSeq: 0
        )
    }

    private func usd(_ value: Decimal) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 0, mint: .usdf),
            nativeAmount: FiatAmount(value: value, currency: .usd),
            currencyRate: Rate(fx: 1, currency: .usd)
        )
    }

    @Test("Identifier is the conversation's base64url id, so a tap routes through the chat deep link")
    func identifierMatchesDeepLinkToken() {
        let chat = conversation(byte: 0x07, lastMessage: nil)
        let item = ChatSpotlightItem(conversation: chat, displayName: "Anna", counterpartPhoneE164: nil, thumbnailData: nil)

        #expect(item.uniqueIdentifier == chat.id.base64URLEncoded)
        #expect(ConversationID(base64URLEncoded: item.uniqueIdentifier) == chat.id)
    }

    @Test("Title is the resolved display name passed in, not a member field")
    func titleUsesResolvedName() {
        let item = ChatSpotlightItem(
            conversation: conversation(byte: 0x01, lastMessage: nil),
            displayName: "Mom",
            counterpartPhoneE164: nil,
            thumbnailData: nil
        )
        #expect(item.title == "Mom")
    }

    @Test("Text last message becomes the content description verbatim")
    func textPreview() {
        let item = ChatSpotlightItem(
            conversation: conversation(byte: 0x01, lastMessage: textMessage("see you soon")),
            displayName: "Anna",
            counterpartPhoneE164: nil,
            thumbnailData: nil
        )
        #expect(item.contentDescription == "see you soon")
    }

    @Test("Cash last message renders as a formatted 'Cash · <amount>' description")
    func cashPreview() {
        let amount = usd(0.50)
        let item = ChatSpotlightItem(
            conversation: conversation(byte: 0x05, lastMessage: cashMessage(amount)),
            displayName: "Anna",
            counterpartPhoneE164: nil,
            thumbnailData: nil
        )
        #expect(item.contentDescription == "Cash · \(amount.nativeAmount.formatted())")
    }

    @Test("A conversation with no messages has no content description")
    func emptyPreview() {
        let item = ChatSpotlightItem(
            conversation: conversation(byte: 0x01, lastMessage: nil),
            displayName: "Anna",
            counterpartPhoneE164: nil,
            thumbnailData: nil
        )
        #expect(item.contentDescription == nil)
    }

    @Test("A phone-only chat is searchable by its digits via keywords")
    func keywordsIncludePhoneDigitForms() {
        // Distinct display name so each expected keyword is attributable to a
        // specific branch (name vs E.164 vs national, digits or not).
        let item = ChatSpotlightItem(
            conversation: conversation(byte: 0x03, lastMessage: nil),
            displayName: "Anna",
            counterpartPhoneE164: "+15869802333",
            thumbnailData: nil
        )
        #expect(item.keywords.contains("Anna"))             // display name
        #expect(item.keywords.contains("+15869802333"))     // E.164
        #expect(item.keywords.contains("15869802333"))      // E.164 digits-only
        #expect(item.keywords.contains("(586) 980-2333"))   // national
        #expect(item.keywords.contains("5869802333"))       // national digits → "586" prefix matches
    }

    @Test("Keywords are de-duplicated when a display name equals a phone form")
    func keywordsDeduplicated() {
        // Display name equal to the national form would otherwise appear twice.
        let item = ChatSpotlightItem(
            conversation: conversation(byte: 0x06, lastMessage: nil),
            displayName: "(586) 980-2333",
            counterpartPhoneE164: "+15869802333",
            thumbnailData: nil
        )
        #expect(Set(item.keywords).count == item.keywords.count)
    }

    @Test("An unparseable phone number degrades to name + raw form without crashing")
    func keywordsTolerateInvalidPhone() {
        let item = ChatSpotlightItem(
            conversation: conversation(byte: 0x08, lastMessage: nil),
            displayName: "Anna",
            counterpartPhoneE164: "not-a-number",
            thumbnailData: nil
        )
        // The national-form branch no-ops on an unparseable number, and the
        // empty digits-only form is dropped — leaving just the name and raw value.
        #expect(item.keywords == ["Anna", "not-a-number"])
    }

    @Test("Keywords carry the display name even with no phone number")
    func keywordsIncludeDisplayName() {
        let item = ChatSpotlightItem(
            conversation: conversation(byte: 0x04, lastMessage: nil),
            displayName: "Anna",
            counterpartPhoneE164: nil,
            thumbnailData: nil
        )
        #expect(item.keywords == ["Anna"])
    }

    @Test("The searchable item carries the chat domain and the mapped attributes")
    func searchableItemAttributes() {
        let chat = conversation(byte: 0x02, lastMessage: textMessage("hi"))
        let avatar = Data([0x89, 0x50, 0x4E, 0x47])
        let item = ChatSpotlightItem(conversation: chat, displayName: "Anna", counterpartPhoneE164: nil, thumbnailData: avatar)
        let searchable = item.searchableItem

        #expect(searchable.uniqueIdentifier == chat.id.base64URLEncoded)
        #expect(searchable.domainIdentifier == ChatSpotlightItem.domainIdentifier)
        #expect(searchable.attributeSet.title == "Anna")
        #expect(searchable.attributeSet.contentDescription == "hi")
        #expect(searchable.attributeSet.keywords == ["Anna"])
        #expect(searchable.attributeSet.thumbnailData == avatar)
    }
}
