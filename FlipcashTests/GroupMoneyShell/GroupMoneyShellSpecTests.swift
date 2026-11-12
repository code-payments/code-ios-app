//
//  GroupMoneyShellSpecTests.swift
//  FlipcashTests
//
//  Phase 1 of the Group Money redesign: a two-tab shell (Groups, Money)
//  behind the `.groupMoneyUI` beta flag. Frames: Groups (node 13729:413),
//  Money (node 13729:744). Written from the brief and the frames before the
//  implementation, so each test pins an outcome rather than a mechanism.
//

import Foundation
import SwiftUI
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Group Money shell spec")
struct GroupMoneyShellSpecTests {

    // MARK: - Flag

    @Test("1.1 the flag exists under its stored name")
    func flag_exists() {
        #expect(BetaFlags.Option(rawValue: "groupMoneyUI") == .groupMoneyUI)
    }

    @Test("1.2 the flag is off until someone turns it on")
    func flag_defaultsOff() {
        #expect(BetaFlags.Option.groupMoneyUI.isOnByDefault == false)
    }

    @Test("1.3 the flag is a developer flag, not a public beta")
    func flag_isDeveloper() {
        #expect(BetaFlags.Option.groupMoneyUI.availability == .developer)
    }

    @Test("1.4 the flag has a title and a description for its toggle")
    func flag_hasCopy() {
        #expect(!BetaFlags.Option.groupMoneyUI.localizedTitle.isEmpty)
        #expect(!BetaFlags.Option.groupMoneyUI.localizedDescription.isEmpty)
    }

    // MARK: - Who sees it

    @Test("2.1 staff access: staff or a developer-unlocked device, nobody else")
    func staffAccess_truthTable() {
        #expect(BetaFlags.hasStaffAccess(isStaff: false, accessGranted: false) == false)
        #expect(BetaFlags.hasStaffAccess(isStaff: true, accessGranted: false) == true)
        #expect(BetaFlags.hasStaffAccess(isStaff: false, accessGranted: true) == true)
        #expect(BetaFlags.hasStaffAccess(isStaff: true, accessGranted: true) == true)
    }

    @Test("2.2 the toggle is hidden from a user who is neither staff nor unlocked")
    func toggle_hiddenFromEveryoneElse() {
        let options = BetaFlags.developerOptions(isStaff: false, accessGranted: false)
        #expect(!options.contains(.groupMoneyUI))
    }

    @Test("2.3 the toggle is shown to staff on a device that is not unlocked")
    func toggle_shownToStaff() {
        let options = BetaFlags.developerOptions(isStaff: true, accessGranted: false)
        #expect(options.contains(.groupMoneyUI))
    }

    @Test("2.4 the toggle is shown on a developer-unlocked device")
    func toggle_shownWhenUnlocked() {
        let options = BetaFlags.developerOptions(isStaff: false, accessGranted: true)
        #expect(options.contains(.groupMoneyUI))
    }

    @Test("2.5 an unlocked device still lists every developer flag it lists today")
    func toggle_unlockedKeepsTodaysFlags() {
        let options = BetaFlags.developerOptions(isStaff: false, accessGranted: true)
        #expect(options.contains(.vibrateOnScan))
        #expect(options.contains(.enableCoinbase))
    }

    @Test("2.6 the shell is hidden from a user who is neither staff nor unlocked, even with the flag on")
    func shell_hiddenFromEveryoneElse() {
        #expect(BetaFlags.showsGroupMoneyUI(isEnabled: true, isStaff: false, accessGranted: false) == false)
    }

    @Test("2.7 the shell shows for staff with the flag on")
    func shell_shownForStaff() {
        #expect(BetaFlags.showsGroupMoneyUI(isEnabled: true, isStaff: true, accessGranted: false) == true)
    }

    @Test("2.8 the shell shows on an unlocked device with the flag on")
    func shell_shownWhenUnlocked() {
        #expect(BetaFlags.showsGroupMoneyUI(isEnabled: true, isStaff: false, accessGranted: true) == true)
    }

    @Test("2.9 with the flag off nobody gets the shell, staff and unlocked included")
    func shell_offForEveryoneWhenFlagOff() {
        #expect(BetaFlags.showsGroupMoneyUI(isEnabled: false, isStaff: true, accessGranted: true) == false)
        #expect(BetaFlags.showsGroupMoneyUI(isEnabled: false, isStaff: false, accessGranted: false) == false)
    }

    // MARK: - Tab set

    @Test("3.1 the shell's layout follows the gate")
    func layout_followsGate() {
        #expect(HomeTabLayout(showsGroupMoney: true) == .groupMoney)
        #expect(HomeTabLayout(showsGroupMoney: false) == .standard)
    }

    @Test("3.2 flag on: the bar holds exactly Groups then Money")
    func groupMoney_barIsGroupsAndMoney() {
        let layout = HomeTabLayout.groupMoney
        #expect(layout.barTabs == [.chat, .wallet])
        #expect(layout.barTabs.map { layout.title(for: $0) } == ["Groups", "Money"])
    }

    @Test("3.3 flag on: search keeps its own tab on the native bar")
    func groupMoney_keepsSearch() {
        #expect(HomeTabLayout.groupMoney.hasSearchTab)
    }

    @Test("3.4 flag off: today's four tabs, in today's order, with today's names and glyphs")
    func standard_isTodaysBar() {
        let layout = HomeTabLayout.standard
        #expect(layout.barTabs == [.scan, .chat, .wallet, .tipCard])
        #expect(layout.barTabs.map { layout.title(for: $0) } == ["Scan", "Chat", "Wallet", "You"])
        #expect(layout.hasSearchTab)
        for tab in HomeTab.allCases {
            #expect(layout.iconName(for: tab, isSelected: false) == tab.iconName(isSelected: false))
            #expect(layout.iconName(for: tab, isSelected: true) == tab.iconName(isSelected: true))
        }
    }

    @Test("3.5 flag on: Groups wears a groups glyph rather than the chat bubble")
    func groupMoney_groupsGlyph() {
        let layout = HomeTabLayout.groupMoney
        #expect(layout.iconName(for: .chat, isSelected: false) != HomeTab.chat.iconName(isSelected: false))
        #expect(layout.iconName(for: .chat, isSelected: true) != HomeTab.chat.iconName(isSelected: true))
    }

    @Test("3.6 flag on: Scan and You are off the bar")
    func groupMoney_scanAndYouOffBar() {
        let bar = HomeTabLayout.groupMoney.barTabs
        #expect(!bar.contains(.scan))
        #expect(!bar.contains(.tipCard))
    }

    // MARK: - Routing

    @Test("4.1 launch opens Groups")
    func launch_opensGroups() {
        let layout = HomeTabLayout.groupMoney
        #expect(layout.initialTab == .chat)
        #expect(layout.title(for: layout.initialTab) == "Groups")
    }

    @Test("4.2 a wallet deep link opens Money")
    func walletLink_opensMoney() {
        let tab = HomeTab(linkName: "wallet")
        #expect(tab == .wallet)

        let router = AppRouter()
        router.showTab(.wallet)
        #expect(router.requestedTab == .wallet)
        #expect(HomeTabLayout.groupMoney.title(for: .wallet) == "Money")
        #expect(HomeTabLayout.groupMoney.barTabs.contains(.wallet))
    }

    @Test("4.3 a search result lands in Groups")
    func searchResult_landsInGroups() {
        let layout = HomeTabLayout.groupMoney
        #expect(layout.searchResultTab == .chat)
        #expect(layout.title(for: layout.searchResultTab) == "Groups")
        #expect(layout.searchResultTab.pushStack == .tips)
    }

    @Test("4.4 a scan deep link still resolves with Scan off the bar")
    func scanLink_resolves() {
        #expect(HomeTab(linkName: "scan") == .scan)

        let router = AppRouter()
        router.showTab(.scan)
        #expect(router.requestedTab == .scan)
        #expect(HomeTabLayout.groupMoney.isReachable(.scan))
    }

    @Test("4.5 a You deep link still resolves with You off the bar")
    func youLink_resolves() {
        #expect(HomeTab(linkName: "you") == .tipCard)
        #expect(HomeTabLayout.groupMoney.isReachable(.tipCard))
    }

    @Test("4.6 every tab-hosted stack has a reachable tab, in both layouts")
    func tabHostedStacks_haveReachableTab() {
        for layout in [HomeTabLayout.standard, .groupMoney] {
            for stack in AppRouter.Stack.allCases where stack.isTabHosted {
                let tab = HomeTab(hosting: stack)
                #expect(tab != nil, "\(stack) is tab-hosted but no tab hosts it")
                if let tab {
                    #expect(layout.isReachable(tab), "\(stack) routes to \(tab), which \(layout) cannot show")
                }
            }
        }
    }

    @Test("4.7 every reachable tab's stack is tab-hosted, in both layouts")
    func reachableTabs_areTabHosted() {
        for layout in [HomeTabLayout.standard, .groupMoney] {
            for tab in HomeTab.allCases where layout.isReachable(tab) {
                if let stack = tab.pushStack {
                    #expect(stack.isTabHosted, "\(tab) pushes onto \(stack), which the router treats as a sheet")
                }
            }
        }
    }

    @Test("4.8 every tab today's router can request is reachable, in both layouts")
    func everyTab_reachable() {
        for layout in [HomeTabLayout.standard, .groupMoney] {
            for tab in HomeTab.allCases {
                #expect(layout.isReachable(tab), "\(layout) cannot show \(tab)")
            }
        }
    }

    // MARK: - Money layout

    @Test("5.1 the Money screen is titled Money")
    func money_title() {
        #expect(MoneyHeaderContent.title == "Money")
    }

    @Test("5.2 one currency reads in the singular")
    func money_oneCurrency() {
        #expect(MoneyHeaderContent.currencyCountText(1) == "1 currency")
    }

    @Test("5.3 several currencies read in the plural")
    func money_manyCurrencies() {
        #expect(MoneyHeaderContent.currencyCountText(54) == "54 currencies")
        #expect(MoneyHeaderContent.currencyCountText(2) == "2 currencies")
    }

    @Test("5.4 flag on: no card stack, no appreciation pill, no tiles")
    func money_dropsOldSections() {
        let sections = WalletLayout.money.sections
        #expect(!sections.contains(.tokenCards))
        #expect(!sections.contains(.appreciation))
        #expect(!sections.contains(.tiles))
    }

    @Test("5.5 flag on: title, balance, currency count, the two buttons, then Recent Activity")
    func money_sectionOrder() {
        #expect(WalletLayout.money.sections == [.title, .balance, .currencyCount, .actions, .recentActivity])
    }

    @Test("5.6 flag off: today's wallet, section for section")
    func standard_wallet() {
        #expect(WalletLayout.standard.sections == [.balanceHeader, .appreciation, .addMoneyRow, .tokenCards, .recentActivity, .tiles])
    }

    @Test("5.7 the wallet layout follows the gate")
    func walletLayout_followsGate() {
        #expect(WalletLayout(showsGroupMoney: true) == .money)
        #expect(WalletLayout(showsGroupMoney: false) == .standard)
    }

    @Test("5.8 the buttons read Add Money and Withdraw")
    func money_buttonTitles() {
        #expect(MoneyHeaderContent.addMoneyTitle == "Add Money")
        #expect(MoneyHeaderContent.withdrawTitle == "Withdraw")
    }

    // MARK: - Money actions

    @Test("6.1 Add Money opens the sheet the wallet's Add Money opens today")
    func addMoney_matchesToday() {
        let router = AppRouter()
        router.activeTabStack = .balance
        MoneyAction.addMoney.perform(on: router)

        let today = AppRouter()
        today.activeTabStack = .balance
        today.presentAddMoney(.general, source: .balance)

        #expect(router.presentedSheet != nil)
        #expect(router.presentedSheet == today.presentedSheet)
    }

    @Test("6.2 Withdraw pushes the withdraw flow the wallet's Withdraw tile pushes today")
    func withdraw_matchesToday() {
        let router = AppRouter()
        router.activeTabStack = .balance
        MoneyAction.withdraw.perform(on: router)

        #expect(router[.balance] == Self.path(.withdrawCurrency(nil)))
        #expect(router.presentedSheet == nil)
    }

    @Test("6.3 the avatar opens You")
    func avatar_opensYou() {
        let router = AppRouter()
        router.activeTabStack = .balance
        MoneyAction.profile.perform(on: router)

        #expect(router.requestedTab == .tipCard)
    }

    @Test("6.4 the currency count opens the list of currencies held, on the Money tab")
    func currencies_opensList() {
        let router = AppRouter()
        router.activeTabStack = .balance
        MoneyAction.currencies.perform(on: router)

        #expect(router[.balance] == Self.path(.walletCurrencies))
        #expect(router.presentedSheet == nil)
    }

    private static func path(_ destination: AppRouter.Destination) -> NavigationPath {
        var path = NavigationPath()
        path.append(destination)
        return path
    }

    // MARK: - Activity rows

    private func conversation(_ byte: UInt8) -> ConversationID {
        ConversationID(data: Data(repeating: byte, count: 16))
    }

    @Test("7.1 a boost carries its group's conversation")
    func activity_boostConversation() {
        let id = conversation(1)
        let boost = Activity.BoostedReaction(conversationID: id, messageID: MessageID(value: 7), emoji: "🔥")
        #expect(MoneyActivityRowContent.conversationID(boostedReaction: boost, requestedPayment: nil, returnedPayment: nil) == id)
    }

    @Test("7.2 a requested payment carries its group's conversation")
    func activity_requestConversation() {
        let id = conversation(2)
        let request = Activity.RequestedPayment(conversationID: id, paymentRequestID: PaymentRequestID(data: Data([7])))
        #expect(MoneyActivityRowContent.conversationID(boostedReaction: nil, requestedPayment: request, returnedPayment: nil) == id)
    }

    @Test("7.3 a returned payment carries its conversation")
    func activity_returnConversation() {
        let id = conversation(3)
        let returned = Activity.ReturnedPayment(conversationID: id, messageID: MessageID(value: 9))
        #expect(MoneyActivityRowContent.conversationID(boostedReaction: nil, requestedPayment: nil, returnedPayment: returned) == id)
    }

    @Test("7.4 an activity with no conversation metadata has no conversation")
    func activity_noConversation() {
        #expect(MoneyActivityRowContent.conversationID(boostedReaction: nil, requestedPayment: nil, returnedPayment: nil) == nil)
    }

    @Test("7.5 the row is titled with the group's name when there is one")
    func activity_titleIsGroupName() {
        #expect(MoneyActivityRowContent.title(groupName: "Brothers", fallback: "Sent to Joe") == "Brothers")
    }

    @Test("7.6 with no group, the row keeps today's title")
    func activity_titleFallsBack() {
        #expect(MoneyActivityRowContent.title(groupName: nil, fallback: "Sent to Joe") == "Sent to Joe")
        #expect(MoneyActivityRowContent.title(groupName: "", fallback: "Sent to Joe") == "Sent to Joe")
    }

    @Test("7.7 the secondary line is the person's name and the day")
    func activity_subtitleNameAndDay() {
        #expect(MoneyActivityRowContent.subtitle(name: "Joe Payne", day: "Today") == "Joe Payne · Today")
    }

    @Test("7.8 with no name, the secondary line is the day alone")
    func activity_subtitleDayOnly() {
        #expect(MoneyActivityRowContent.subtitle(name: nil, day: "Today") == "Today")
        #expect(MoneyActivityRowContent.subtitle(name: "", day: "Today") == "Today")
    }

    @Test("7.9 the day reads Today for something that happened today")
    func activity_dayToday() {
        #expect(MoneyActivityRowContent.dayText(for: .now) == "Today")
    }

    @Test("7.10 money out reads with a minus, money in with a plus")
    func activity_signedAmount() {
        let out = FiatAmount(value: Decimal(string: "56.38")!, currency: .usd)
        let into = FiatAmount(value: Decimal(string: "12.50")!, currency: .usd)
        #expect(MoneyActivityRowContent.amountText(out, signPrefix: "-") == "-$56.38")
        #expect(MoneyActivityRowContent.amountText(into, signPrefix: "+") == "+$12.50")
    }

    @Test("7.11 an activity with no direction reads unsigned")
    func activity_unsignedAmount() {
        let amount = FiatAmount(value: Decimal(string: "18.36")!, currency: .usd)
        #expect(MoneyActivityRowContent.amountText(amount, signPrefix: nil) == "$18.36")
    }
}
