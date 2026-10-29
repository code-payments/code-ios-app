//
//  ConversationRulesEditTests.swift
//  FlipcashCoreTests
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("Conversation rules edit")
struct ConversationRulesEditTests {

    private let mint = Data(repeating: 7, count: 32)

    private func minimumBalance(_ value: Double, currency: String = "usd", mints: [Data]? = nil) -> Flipcash_Chat_V1_MinimumBalanceRequirement {
        .with {
            $0.amount = .with {
                $0.currency = currency
                $0.nativeAmount = value
            }
            $0.mints = (mints ?? [mint]).map { bytes in .with { $0.value = bytes } }
        }
    }

    /// A group as the server sends it: a listener minimum and a staff rule, a creator speaker rule,
    /// and optionally a speaker minimum.
    private func serverRules(speaker: Double? = nil, currency: String = "usd") -> Flipcash_Chat_V1_Rules {
        .with {
            $0.listener = [
                .with { $0.minimumBalance = minimumBalance(5, currency: currency) },
                .with { $0.staff = .init() },
            ]
            $0.speaker = [.with { $0.creator = .init() }]
            if let speaker {
                $0.speaker.append(.with { $0.minimumBalance = minimumBalance(speaker, currency: currency) })
            }
        }
    }

    @Test("Rules the edit doesn't touch go back as the server sent them")
    func keepsOtherRules() throws {
        let rules = ConversationRules(serverRules())
        let edit = try #require(ConversationRulesEdit(editing: rules, listener: .usd(8), speaker: nil))

        #expect(edit.proto.listener.count == 2)
        #expect(edit.proto.listener[0].minimumBalance.amount.nativeAmount == 8)
        #expect(edit.proto.listener[1].staff == .init())
        #expect(edit.proto.speaker == [.with { $0.creator = .init() }])
    }

    @Test("A new speaker minimum takes the listener's currency and mints as sent")
    func addsSpeakerInListenerTerms() throws {
        // A malformed mint, which decoding drops, still goes back so the server sees matching mints.
        let malformed = Data([1, 2, 3])
        var proto = serverRules()
        proto.listener[0].minimumBalance.mints.append(.with { $0.value = malformed })
        let rules = ConversationRules(proto)

        let edit = try #require(ConversationRulesEdit(editing: rules, listener: .usd(5), speaker: .usd(10)))

        let speaker = try #require(edit.proto.speaker.last)
        #expect(speaker.minimumBalance.amount.currency == "usd")
        #expect(speaker.minimumBalance.amount.nativeAmount == 10)
        #expect(speaker.minimumBalance.mints.map(\.value) == [mint, malformed])
        #expect(edit.proto.speaker.first == .with { $0.creator = .init() })
    }

    @Test("A speaker minimum is replaced in place, or removed")
    func replacesOrRemovesSpeaker() throws {
        let rules = ConversationRules(serverRules(speaker: 10))

        let changed = try #require(ConversationRulesEdit(editing: rules, listener: .usd(5), speaker: .usd(12)))
        #expect(changed.proto.speaker.count == 2)
        #expect(changed.proto.speaker[1].minimumBalance.amount.nativeAmount == 12)

        let removed = try #require(ConversationRulesEdit(editing: rules, listener: .usd(5), speaker: nil))
        #expect(removed.proto.speaker == [.with { $0.creator = .init() }])
    }

    @Test("An amount outside the listener's currency, or a group with no listener minimum, has no edit")
    func refusesWhatTheServerWould() {
        let jpy = ConversationRules(serverRules(currency: "jpy"))
        #expect(ConversationRulesEdit(editing: jpy, listener: .usd(5), speaker: nil) == nil)
        #expect(ConversationRulesEdit(editing: jpy, listener: FiatAmount(value: 500, currency: .jpy), speaker: .usd(1)) == nil)
        #expect(ConversationRulesEdit(editing: jpy, listener: FiatAmount(value: 500, currency: .jpy), speaker: nil) != nil)

        let staffOnly = ConversationRules(.with { $0.listener = [.with { $0.staff = .init() }] })
        #expect(ConversationRulesEdit(editing: staffOnly, listener: .usd(5), speaker: nil) == nil)
    }

    @Test("Rules built locally have no server form beyond what they state")
    func localRulesEditFromTheirOwnProto() throws {
        let rules = ConversationRules(listener: [.minimumBalance(MinimumBalanceRequirement(amount: .usd(5)))])
        let edit = try #require(ConversationRulesEdit(editing: rules, listener: .usd(6), speaker: nil))
        #expect(edit.rules == ConversationRules(listener: [.minimumBalance(MinimumBalanceRequirement(amount: .usd(6)))]))
    }

    @Test("The server's rules don't change how two rule sets compare")
    func wireLeftOutOfEquality() {
        let decoded = ConversationRules(.with { $0.listener = [.with { $0.minimumBalance = minimumBalance(5, mints: []) }] })
        let local = ConversationRules(listener: [.minimumBalance(MinimumBalanceRequirement(amount: .usd(5)))])
        #expect(decoded == local)
    }

    @Test("A listener rule in an unknown currency is reported as dropped")
    func dropsUnknownCurrency() {
        #expect(ConversationRules(serverRules(currency: "zzz")).dropsListenerRule)
        #expect(!ConversationRules(serverRules()).dropsListenerRule)
        #expect(!ConversationRules().dropsListenerRule)
    }

    @Test("A rules change the client can't fully read keeps the rules it had, rather than opening the chat")
    func storeKeepsRulesOnUnknownCurrency() {
        let id = ConversationID(data: Data(repeating: 1, count: 32))
        let held = ConversationRules(serverRules())
        var store = ConversationStore()
        store.setFeed([Conversation(id: id, members: [], lastMessage: nil, lastActivity: .now, type: .group, rules: held)])

        store.applyRulesChanged(ConversationRules(serverRules(currency: "zzz")), in: id)
        #expect(store.conversations.first?.rules == held)

        let raised = ConversationRules(serverRules(speaker: 9))
        store.applyRulesChanged(raised, in: id)
        #expect(store.conversations.first?.rules == raised)
    }
}
