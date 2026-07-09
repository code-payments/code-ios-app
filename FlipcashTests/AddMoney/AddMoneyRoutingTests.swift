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
        router.presentAddMoney(.giveCash)
        #expect(router.presentedSheets == [.addMoney(.giveCash)])
    }

    @Test("Over a single root sheet, Add Money stacks nested")
    func overRootSheet_stacksNested() {
        let router = AppRouter()
        router.present(.send)
        router.presentAddMoney(.giveCash)
        #expect(router.presentedSheets == [.send, .addMoney(.giveCash)])
    }

    @Test("From inside the buy sheet, Add Money stacks on top — nothing dismisses on entry")
    func fromBuySheet_stacksOnTop() {
        let router = AppRouter()
        router.present(.discover)
        router.presentNested(.buy(.usdc))
        router.presentAddMoney(.buyCurrency)
        #expect(router.presentedSheets == [.discover, .buy(.usdc), .addMoney(.buyCurrency)])
    }

    @Test("The options over the buy sheet report the buy entry")
    func isAddMoneyOverBuy_buyEntry() {
        let router = AppRouter()
        router.present(.discover)
        router.presentNested(.buy(.usdc))
        router.presentAddMoney(.buyCurrency)
        #expect(router.isAddMoneyOverBuy)
    }

    @Test(
        "The options report a non-buy entry everywhere else",
        arguments: [AppRouter.SheetPresentation.settings, .balance, .send]
    )
    func isAddMoneyOverBuy_nonBuyEntry(root: AppRouter.SheetPresentation) {
        let router = AppRouter()
        router.present(root)
        router.presentAddMoney(.general)
        #expect(!router.isAddMoneyOverBuy)
    }

    @Test("The options at root report a non-buy entry")
    func isAddMoneyOverBuy_rootEntry() {
        let router = AppRouter()
        router.presentAddMoney(.giveCash)
        #expect(!router.isAddMoneyOverBuy)
    }

    @Test("Re-presenting Add Money with a different context swaps in place")
    func presentNested_differentContext_swaps() {
        let router = AppRouter()
        router.present(.discover)
        router.presentNested(.addMoney(.buyCurrency))
        router.presentNested(.addMoney(.general))
        #expect(router.presentedSheets == [.discover, .addMoney(.general)])
    }

    @Test("The addMoney stack has no root sheet — it is nested-only")
    func addMoneyStack_sheet_isNil() {
        #expect(AppRouter.Stack.addMoney.sheet == nil)
    }

    @Test("Method selection over buy pops the options and pushes the flow inside the buy sheet")
    func selectionOverBuy_popsOptionsAndPushesFlow() {
        let router = AppRouter()
        router.present(.discover)
        router.presentNested(.buy(.usdc))
        router.presentAddMoney(.buyCurrency)

        // Mirrors AddMoneyStartScreen.select(_:) for the buy entry.
        router.dismissSheet()
        router.pushAny(AddMoneyFlowStep.method(.otherWallet))

        #expect(router.presentedSheets == [.discover, .buy(.usdc)])
        #expect(router[.buy].count == 1, "The deposit flow step must land on the buy sheet's stack")
    }
}
