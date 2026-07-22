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

    private static let resolvedContact = ResolvedContact(
        contactId: "contact-anna",
        displayName: "Anna",
        phoneE164: "+15555550001",
        nationalPhone: "(555) 555-0001",
        imageData: nil,
        dmChatID: nil
    )

    private static let contact = SendTarget.contact(resolvedContact)

    private static var existingContext: ConversationContext {
        .existing(conversationID)
    }

    // MARK: - Sheet ↔ Stack wiring

    @Test(".sendAmount maps to its own stack")
    func sendAmount_mapsToOwnStack() {
        #expect(AppRouter.SheetPresentation.sendAmount(Self.contact).stack == .sendAmount)
    }

    @Test("Payload-carrying stacks are never navigate(to:) targets")
    func payloadStacks_haveNoSynthesizableSheet() {
        // .buy and .sendAmount carry a payload that can't be rebuilt from the
        // stack alone, so navigate(to:) must never resolve them.
        #expect(AppRouter.Stack.buy.sheet == nil)
        #expect(AppRouter.Stack.sendAmount.sheet == nil)
    }

    // MARK: - Chat deeplink routes through Send

    @Test("A chat deeplink pushes onto the Send stack — picker beneath")
    func chatDeeplink_hostsOnSendStack_pickerBeneath() {
        let router = AppRouter()

        router.navigate(to: .dmConversation(Self.existingContext))

        // The chat is a leaf on .send, so the recipient picker (the .send root)
        // sits beneath it and `back` reveals it.
        #expect(router.presentedSheets == [.send])
        #expect(router.rootSheet == .send)
        #expect(router[.send] == AppRouter.navigationPath(.dmConversation(Self.existingContext)))
    }

    @Test("A second chat deeplink swaps the leaf in place — no new sheet")
    func secondChatDeeplink_swapsLeafInPlace_noNewSheet() {
        // Scenario 2: while viewing chat A, a push for chat B switches the leaf
        // in place. `present(.send)` is idempotent (the stack stays a single
        // sheet) and only the leaf is replaced.
        let router = AppRouter()
        let chatA = ConversationContext.existing(.test(0x01))
        let chatB = ConversationContext.existing(.test(0x02))

        router.navigate(to: .dmConversation(chatA))
        #expect(router.presentedSheets == [.send])

        router.navigate(to: .dmConversation(chatB))

        #expect(router.presentedSheets == [.send])   // still one sheet, not re-presented
        #expect(router[.send] == AppRouter.navigationPath(.dmConversation(chatB)))
    }

    @Test("Re-arriving on the same chat is a no-op")
    func sameChatReArrival_isNoOp() {
        let router = AppRouter()
        router.navigate(to: .dmConversation(Self.existingContext))
        let before = router.presentedSheets

        router.navigate(to: .dmConversation(Self.existingContext))  // identical deeplink/push

        #expect(router.presentedSheets == before)
        #expect(router[.send] == AppRouter.navigationPath(.dmConversation(Self.existingContext)))
    }

    // MARK: - Send Cash over a pushed chat (picker flow)

    @Test("presentNested(.sendAmount) over .send stacks the amount sheet")
    func sendAmount_overSend_stacks() {
        let router = AppRouter()
        router.present(.send)                                  // recipient picker
        router.push(.dmConversation(.contact(Self.resolvedContact)))  // chat pushed on the picker

        router.presentNested(.sendAmount(Self.contact))

        #expect(router.presentedSheets == [.send, .sendAmount(Self.contact)])
        #expect(router.rootSheet == .send)
        #expect(router.presentedSheet == .sendAmount(Self.contact))
    }

    @Test("dismissSheet reveals the pushed chat under the amount sheet")
    func sendAmount_overSend_dismissRevealsChat() {
        let router = AppRouter()
        router.present(.send)
        router.push(.dmConversation(.contact(Self.resolvedContact)))
        router.presentNested(.sendAmount(Self.contact))

        router.dismissSheet()

        #expect(router.presentedSheets == [.send])
        // The chat is still on the .send stack underneath.
        #expect(router[.send] == AppRouter.navigationPath(.dmConversation(.contact(Self.resolvedContact))))
    }

    // MARK: - Send Cash over a deeplinked chat

    @Test("dismissing the amount sheet reveals the deeplinked chat, then closing Send lands on the scanner")
    func sendAmount_overDeeplinkedChat_dismissChain() {
        let router = AppRouter()
        router.navigate(to: .dmConversation(Self.existingContext))
        router.presentNested(.sendAmount(Self.contact))

        router.dismissSheet()  // amount sheet → reveals the chat on the send stack
        #expect(router.presentedSheets == [.send])
        #expect(router[.send] == AppRouter.navigationPath(.dmConversation(Self.existingContext)))

        router.dismissSheet()  // send sheet → scanner (the picker was the floor)
        #expect(router.presentedSheets.isEmpty)
    }

    // MARK: - Deposit redirect leaves the send sheets

    @Test("navigate(to:) from the amount sheet swaps to the Wallet's currency info")
    func depositRedirect_swapsToBalance() {
        let router = AppRouter()
        router.navigate(to: .dmConversation(Self.existingContext))
        router.presentNested(.sendAmount(Self.contact))

        router.navigate(to: .currencyInfoForDeposit(.usdc))

        #expect(router.presentedSheets == [.balance])
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfoForDeposit(.usdc)))
    }

    // MARK: - In-chat currency info pushed on the send stack (cash card tap)

    @Test("Swapping to a different chat clears the previous chat's pushed currency info")
    func chatSwap_clearsPushedLeaf() {
        // A cash card tapped in chat A pushes currency info onto the shared .send stack; a
        // deeplink/push for chat B must not inherit chat A's leaf.
        let router = AppRouter()
        let chatA = ConversationContext.existing(.test(0x01))
        let chatB = ConversationContext.existing(.test(0x02))
        router.navigate(to: .dmConversation(chatA))
        router.push(.currencyInfo(.usdc))
        #expect(router[.send] == AppRouter.navigationPath(.dmConversation(chatA), .currencyInfo(.usdc)))

        router.navigate(to: .dmConversation(chatB))

        #expect(router.presentedSheets == [.send])
        #expect(router[.send] == AppRouter.navigationPath(.dmConversation(chatB)))
    }

    @Test("Re-arriving on the same chat with currency info pushed lands back on the chat")
    func sameChatReArrival_popsPushedLeaf() {
        let router = AppRouter()
        router.navigate(to: .dmConversation(Self.existingContext))
        router.push(.currencyInfo(.usdc))

        router.navigate(to: .dmConversation(Self.existingContext))  // same-chat deeplink/push re-arrival

        #expect(router.presentedSheets == [.send])
        #expect(router[.send] == AppRouter.navigationPath(.dmConversation(Self.existingContext)))
    }

    @Test("A cross-stack swap still preserves the swapped-out stack's path (swap-back)")
    func crossStackSwap_preservesPath() {
        // The leaf clearing must be scoped to same-stack swaps — a .balance → .settings
        // swap must still keep .balance's path so swapping back restores it.
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))

        router.present(.settings)

        #expect(router.presentedSheets == [.settings])
        #expect(router[.balance] == AppRouter.navigationPath(.currencyInfo(.usdc)))
    }

    @Test("popToRoot() from a chat-launched withdraw lands on the Send picker")
    func popToRoot_fromChatLaunchedWithdraw_landsOnSendPicker() {
        // The withdraw flow's completion uses the stack-agnostic popToRoot(); reached from a chat it
        // resets the .send stack to its root — the recipient picker — consistent with a
        // picker-launched chat. The user isn't stranded on the finished withdraw screen.
        let router = AppRouter()
        router.navigate(to: .dmConversation(Self.existingContext))
        router.push(.currencyInfo(.usdc))
        router.push(.withdrawCurrency(.usdc))

        router.popToRoot()

        #expect(router.presentedSheets == [.send])
        #expect(router[.send].isEmpty)
    }

    @Test("popToRoot() from the Wallet stack still resets .balance, unchanged from the hardcoded path")
    func popToRoot_walletStackUnchanged() {
        let router = AppRouter()
        router.present(.balance)
        router.push(.currencyInfo(.usdc))
        router.push(.withdrawCurrency(.usdc))

        router.popToRoot()

        #expect(router.presentedSheets == [.balance])
        #expect(router[.balance].isEmpty)
    }

    @Test("Swapping away to another root then back to the chat lands on the chat, not the stale leaf")
    func chatSwapAwayAndBack_clearsLeaf() {
        // Re-arrive after a cross-stack detour: the leaf left dangling on the swapped-away
        // .send stack must clear when the chat is re-entered.
        let router = AppRouter()
        router.navigate(to: .dmConversation(Self.existingContext))
        router.push(.currencyInfo(.usdc))
        router.present(.balance)                                     // swap away to a different root

        router.navigate(to: .dmConversation(Self.existingContext))   // deeplink/push back to the chat

        #expect(router.presentedSheets == [.send])
        #expect(router[.send] == AppRouter.navigationPath(.dmConversation(Self.existingContext)))
    }

    @Test("Re-arriving on the chat with a nested sheet above clears the pushed leaf and dismisses the nested sheet")
    func chatReArrival_withNestedAbove_clearsLeaf() {
        let router = AppRouter()
        router.navigate(to: .dmConversation(Self.existingContext))
        router.push(.currencyInfo(.usdc))
        router.presentNested(.sendAmount(Self.contact))             // nested sheet stacks above the chat

        router.navigate(to: .dmConversation(Self.existingContext))   // same-chat deeplink/push re-arrival

        #expect(router.presentedSheets == [.send])
        #expect(router[.send] == AppRouter.navigationPath(.dmConversation(Self.existingContext)))
    }
}
