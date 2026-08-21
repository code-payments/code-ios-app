//
//  AddMoneyRoutingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("AddMoney routing")
@MainActor
struct AddMoneyRoutingTests {

    @Test("The addMoney sheet maps to the addMoney stack")
    func addMoneySheet_mapsToAddMoneyStack() {
        #expect(AppRouter.SheetPresentation.addMoney(.buyCurrency).stack == .addMoney)
    }

    @Test("With no sheet presented, Add Money presents at root")
    func giveCash_presentsAtRoot() {
        let router = AppRouter()
        router.presentAddMoney(.giveCash, source: .scanner)
        #expect(router.presentedSheets == [.addMoney(.giveCash)])
    }

    @Test("Over a single root sheet, Add Money stacks nested")
    func overRootSheet_stacksNested() {
        let router = AppRouter()
        router.present(.give)
        router.presentAddMoney(.giveCash, source: .scanner)
        #expect(router.presentedSheets == [.give, .addMoney(.giveCash)])
    }

    @Test("From inside the buy sheet, Add Money stacks on top — nothing dismisses on entry")
    func fromBuySheet_stacksOnTop() {
        let router = AppRouter()
        router.present(.give)
        router.presentNested(.buy(.usdc))
        router.presentAddMoney(.buyCurrency, source: .buyShortfall)
        #expect(router.presentedSheets == [.give, .buy(.usdc), .addMoney(.buyCurrency)])
    }

    @Test("The options over the buy sheet report the buy entry")
    func isAddMoneyOverBuy_buyEntry() {
        let router = AppRouter()
        router.present(.give)
        router.presentNested(.buy(.usdc))
        router.presentAddMoney(.buyCurrency, source: .buyShortfall)
        #expect(router.isAddMoneyOverBuy)
    }

    @Test(
        "The options report a non-buy entry everywhere else",
        arguments: [AppRouter.SheetPresentation.settings, .give, .tips]
    )
    func isAddMoneyOverBuy_nonBuyEntry(root: AppRouter.SheetPresentation) {
        let router = AppRouter()
        router.present(root)
        router.presentAddMoney(.general, source: .balance)
        #expect(!router.isAddMoneyOverBuy)
    }

    @Test("The options at root report a non-buy entry")
    func isAddMoneyOverBuy_rootEntry() {
        let router = AppRouter()
        router.presentAddMoney(.giveCash, source: .scanner)
        #expect(!router.isAddMoneyOverBuy)
    }

    @Test("Re-presenting Add Money with a different context swaps in place")
    func presentNested_differentContext_swaps() {
        let router = AppRouter()
        router.present(.give)
        router.presentNested(.addMoney(.buyCurrency))
        router.presentNested(.addMoney(.general))
        #expect(router.presentedSheets == [.give, .addMoney(.general)])
    }

    @Test("The addMoney stack has no root sheet — it is nested-only")
    func addMoneyStack_sheet_isNil() {
        #expect(AppRouter.Stack.addMoney.sheet == nil)
    }

    @Test("Method selection over buy pops the options and pushes the flow inside the buy sheet")
    func selectionOverBuy_popsOptionsAndPushesFlow() {
        let router = AppRouter()
        router.present(.give)
        router.presentNested(.buy(.usdc))
        router.presentAddMoney(.buyCurrency, source: .buyShortfall)

        // Mirrors AddMoneyStartScreen.select(_:) for the buy entry.
        router.dismissSheet()
        router.pushAny(AddMoneyFlowStep.method(.otherWallet))

        #expect(router.presentedSheets == [.give, .buy(.usdc)])
        #expect(router[.buy].count == 1, "The deposit flow step must land on the buy sheet's stack")
    }

    @Test("The deposit flow targets the sheet directly beneath the picker")
    func addMoneyPushStack_overSheet_usesUnderlyingStack() {
        let router = AppRouter()
        router.present(.give)
        router.presentAddMoney(.giveCash, source: .scanner)
        #expect(router.addMoneyPushStack == .give)
    }

    @Test("Over the buy sheet the deposit flow targets the buy stack")
    func addMoneyPushStack_overBuy_usesBuyStack() {
        let router = AppRouter()
        router.present(.give)
        router.presentNested(.buy(.usdc))
        router.presentAddMoney(.buyCurrency, source: .buyShortfall)
        #expect(router.addMoneyPushStack == .buy)
    }

    @Test("At root, the deposit flow targets the active tab's stack")
    func addMoneyPushStack_rootOverTab_usesActiveTabStack() {
        let router = AppRouter()
        router.activeTabStack = .balance
        router.presentAddMoney(.general, source: .balance)
        #expect(router.addMoneyPushStack == .balance)
    }

    @Test("At root with no active tab, the deposit flow has nowhere to push")
    func addMoneyPushStack_rootNoTab_isNil() {
        let router = AppRouter()
        router.presentAddMoney(.giveCash, source: .scanner)
        #expect(router.addMoneyPushStack == nil)
    }
}
