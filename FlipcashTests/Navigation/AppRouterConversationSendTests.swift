//
//  AppRouterConversationSendTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("AppRouter Conversation & Send Cash sheets")
struct AppRouterConversationSendTests {

    private static let conversationID = ConversationID.test(0x01)

    private static let contact = ResolvedContact(
        contactId: "contact-anna",
        displayName: "Anna",
        phoneE164: "+15555550001",
        nationalPhone: "(555) 555-0001",
        imageData: nil,
        dmChatID: nil
    )

    private static var existingContext: ConversationContext {
        .existing(conversationID)
    }

    // MARK: - Sheet ↔ Stack wiring

    @Test(".conversation and .sendAmount map to their own stacks")
    func sheets_mapToOwnStacks() {
        #expect(AppRouter.SheetPresentation.conversation(Self.existingContext).stack == .conversation)
        #expect(AppRouter.SheetPresentation.sendAmount(Self.contact).stack == .sendAmount)
    }

    @Test(".conversation and .sendAmount stacks are never navigate(to:) targets")
    func stacks_haveNoSynthesizableSheet() {
        // Like .buy, these carry a payload that can't be rebuilt from the stack
        // alone, so navigate(to:) must never resolve them.
        #expect(AppRouter.Stack.conversation.sheet == nil)
        #expect(AppRouter.Stack.sendAmount.sheet == nil)
    }

    // MARK: - Chat as the deeplink root

    @Test("present(.conversation) makes the chat the root — no picker beneath")
    func presentConversation_isRoot() {
        let router = AppRouter()

        router.present(.conversation(Self.existingContext))

        #expect(router.presentedSheets == [.conversation(Self.existingContext)])
        #expect(router.rootSheet == .conversation(Self.existingContext))
        #expect(router.presentedSheet == .conversation(Self.existingContext))
    }

    @Test("a second chat deeplink swaps the root to the new conversation")
    func presentConversation_differentChat_swapsRoot() {
        // `.conversation` is the first root-level sheet with a payload, so
        // same-case-different-payload at the root (a second chat notification)
        // is a path the nested-`.buy` swap tests don't cover.
        let router = AppRouter()
        let chatA = ConversationContext.existing(.test(0x01))
        let chatB = ConversationContext.existing(.test(0x02))
        router.present(.conversation(chatA))

        router.present(.conversation(chatB))

        #expect(router.presentedSheets == [.conversation(chatB)])
        #expect(router.rootSheet == .conversation(chatB))
    }

    // MARK: - Send Cash over a pushed chat (picker flow)

    @Test("presentNested(.sendAmount) over .send stacks the amount sheet")
    func sendAmount_overSend_stacks() {
        let router = AppRouter()
        router.present(.send)                       // recipient picker
        router.push(.dmConversation(.contact(Self.contact)))  // chat pushed on the picker

        router.presentNested(.sendAmount(Self.contact))

        #expect(router.presentedSheets == [.send, .sendAmount(Self.contact)])
        #expect(router.rootSheet == .send)
        #expect(router.presentedSheet == .sendAmount(Self.contact))
    }

    @Test("dismissSheet reveals the pushed chat under the amount sheet")
    func sendAmount_overSend_dismissRevealsChat() {
        let router = AppRouter()
        router.present(.send)
        router.push(.dmConversation(.contact(Self.contact)))
        router.presentNested(.sendAmount(Self.contact))

        router.dismissSheet()

        #expect(router.presentedSheets == [.send])
        // The chat is still on the .send stack underneath.
        #expect(router[.send] == AppRouter.navigationPath(.dmConversation(.contact(Self.contact))))
    }

    // MARK: - Send Cash over a deeplinked chat (root flow)

    @Test("presentNested(.sendAmount) over .conversation stacks the amount sheet")
    func sendAmount_overConversation_stacks() {
        let router = AppRouter()
        router.present(.conversation(Self.existingContext))

        router.presentNested(.sendAmount(Self.contact))

        #expect(router.presentedSheets == [.conversation(Self.existingContext), .sendAmount(Self.contact)])
        #expect(router.rootSheet == .conversation(Self.existingContext))
    }

    @Test("dismissing the amount sheet reveals the chat root, then closing it lands on the scanner")
    func sendAmount_overConversation_dismissChain() {
        let router = AppRouter()
        router.present(.conversation(Self.existingContext))
        router.presentNested(.sendAmount(Self.contact))

        router.dismissSheet()  // amount sheet → reveals chat root
        #expect(router.presentedSheets == [.conversation(Self.existingContext)])

        router.dismissSheet()  // chat root → scanner (chat was the floor)
        #expect(router.presentedSheets.isEmpty)
    }

    // MARK: - Deposit redirect leaves the send sheets

    @Test("navigate(to:) from the amount sheet swaps to the Wallet's currency info")
    func depositRedirect_swapsToBalance() {
        let router = AppRouter()
        router.present(.conversation(Self.existingContext))
        router.presentNested(.sendAmount(Self.contact))

        router.navigate(to: .currencyInfoForDeposit(.usdc))

        #expect(router.presentedSheets == [.balance])
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfoForDeposit(.usdc)))
    }
}
