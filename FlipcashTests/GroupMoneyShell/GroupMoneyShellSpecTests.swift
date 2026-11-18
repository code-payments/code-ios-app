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
import UIKit
import FlipcashCore
import FlipcashStore
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

    @Test("3.3 flag on: the native bar has no search tab")
    func groupMoney_hasNoSearchTab() {
        #expect(HomeTabLayout.groupMoney.hasSearchTab == false)
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

    @Test("3.7 flag on: Groups has no search button on either bar; flag off keeps today's, on the legacy pill only")
    func searchButton_followsLayout() {
        #expect(HomeTabLayout.groupMoney.listShowsSearchButton(onSystemBar: true) == false)
        #expect(HomeTabLayout.groupMoney.listShowsSearchButton(onSystemBar: false) == false)
        #expect(HomeTabLayout.standard.listShowsSearchButton(onSystemBar: true) == false)
        #expect(HomeTabLayout.standard.listShowsSearchButton(onSystemBar: false) == true)
    }

    @Test("3.8 flag on: the system bar holds Groups and Money alone, centred at their width")
    func groupMoney_systemBarIsCentredWithoutSearch() async throws {
        guard #available(iOS 26, *) else { return }
        let (window, bar) = try await hostedTabBar(showsGroupMoney: true)
        defer { window.isHidden = true }
        #expect(bar.items?.map(\.title) == ["Groups", "Money"])
        let frames = TabBarItemLocator.itemFrames(in: bar)
        let items = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        #expect(abs(items.midX - bar.bounds.midX) <= 1, "items \(items) in bar \(bar.bounds)")
        #expect(items.width < bar.bounds.width * 0.75, "items \(items) in bar \(bar.bounds)")
    }

    @Test("3.9 flag off: the system bar keeps today's four tabs and its search tab")
    func standard_systemBarKeepsSearch() async throws {
        guard #available(iOS 26, *) else { return }
        let (window, bar) = try await hostedTabBar(showsGroupMoney: false)
        defer { window.isHidden = true }
        #expect(bar.items?.count == 5)
        #expect(bar.items?.last?.title == "Search")
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

    @Test("5.4 flag on: no card stack, no tiles")
    func money_dropsOldSections() {
        let sections = WalletLayout.money.sections
        #expect(!sections.contains(.tokenCards))
        #expect(!sections.contains(.tiles))
    }

    @Test("5.5 flag on: title, balance, appreciation, currency count, the two buttons, then Recent Activity")
    func money_sectionOrder() {
        #expect(WalletLayout.money.sections == [.title, .balance, .appreciation, .currencyCount, .actions, .recentActivity])
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
    // MARK: - Groups list

    @Test("8.1 flag on: the list's bar has no \"…\" and reads Groups in the leading slot")
    func groupsList_titleBarHasNoOverflow() async throws {
        let (window, bar) = try await hostedChatListBar(GateFlags(showsGroupMoney: true)) {
            Self.barElement(labelled: "Groups", in: $0) != nil
        }
        defer { window.isHidden = true }
        #expect(Self.barElement(labelled: "More", in: bar) == nil)
        #expect(bar.topItem?.title == "Groups")
        // The centred title gives way to the leading one.
        #expect(Self.titleLabels(in: bar).isEmpty, "centred titles: \(Self.titleLabels(in: bar))")
        let title = try #require(Self.barElement(labelled: "Groups", in: bar)).accessibilityFrame
        #expect(title.maxX < bar.bounds.midX, "title \(title) in bar \(bar.bounds)")
        // Set in the large title token, not the bar's own title size.
        #expect(title.height >= UIFont.appTitleLarge.lineHeight - 1, "title \(title)")
        #expect(Self.barElement(labelled: "New group", in: bar) != nil)
    }

    @Test("8.2 flag off: the list keeps its \"…\" and its centred Chat title")
    func chatList_titleBarKeepsOverflow() async throws {
        let (window, bar) = try await hostedChatListBar(GateFlags(showsGroupMoney: false)) {
            Self.barElement(labelled: "More", in: $0) != nil
        }
        defer { window.isHidden = true }
        #expect(bar.topItem?.title == "Chat")
        let labels = Self.titleLabels(in: bar)
        #expect(labels.map(\.text) == ["Chat"])
        if let label = labels.first {
            let frame = label.convert(label.bounds, to: bar)
            #expect(abs(frame.midX - bar.bounds.midX) <= 1, "title \(frame) in bar \(bar.bounds)")
        }
        #expect(Self.barElement(labelled: "Groups", in: bar) == nil)
    }

    @Test("8.3 flag on: a row's long press ends with Select, which starts select mode with that row picked")
    func groupsList_rowMenuSelectPicksRow() async throws {
        let (controller, id) = try await Self.seededChatList()
        let selection = ChatSelection()
        let window = try Self.hostWindow(
            NavigationStack { TipConversationsScreen(showsSearchButton: false) }
                .environment(selection)
                .environment(controller)
                .environment(GateFlags(showsGroupMoney: true) as BetaFlags)
                .injectingEnvironment(from: try SessionContainer.makeTest(holdings: []))
                .injectingEnvironment(from: Container.mock)
        )
        defer { window.isHidden = true }
        let menu = try await Self.rowMenu(in: window)
        #expect(Self.actions(in: menu).map(\.title) == ["Mark as Unread", "Mute", "Archive", "Select"])

        try Self.perform("Select", in: menu)
        try await waitUntil(timeout: .seconds(30)) { selection.isActive }
        #expect(selection.selected == [id])
        // The bar is select mode's, as from the "…" menu: the count, and Done to leave.
        try await waitUntil(timeout: .seconds(30)) {
            window.layoutIfNeeded()
            guard let bar = Self.navigationBar(in: window) else { return false }
            return bar.topItem?.title == "1 Selected" && Self.barElement(labelled: "Done", in: bar) != nil
                // The shell removes the bar's centred title outside select mode; the count brings it back.
                && Self.titleLabels(in: bar).map(\.text) == ["1 Selected"]
        }
    }

    @Test("8.4 flag off: a row's long press has no Select")
    func chatList_rowMenuHasNoSelect() async throws {
        let (controller, _) = try await Self.seededChatList()
        let window = try Self.hostWindow(
            NavigationStack { TipConversationsScreen(showsSearchButton: false) }
                .environment(ChatSelection())
                .environment(controller)
                .environment(GateFlags(showsGroupMoney: false) as BetaFlags)
                .injectingEnvironment(from: try SessionContainer.makeTest(holdings: []))
                .injectingEnvironment(from: Container.mock)
        )
        defer { window.isHidden = true }
        let menu = try await Self.rowMenu(in: window)
        #expect(Self.actions(in: menu).map(\.title) == ["Mark as Unread", "Mute", "Archive"])
    }

    /// With `leftAligned` the small bar stands in for the system bar, so it has to leave with it:
    /// not only drawn transparent, but out of the accessibility tree, where activating its items
    /// still switched tabs.
    @Test(
        "8.5 flag on: Select from a row swaps the tab bar for the select capsules",
        arguments: [false, true]
    )
    func groupsList_rowSelectSwapsTabBar(leftAligned: Bool) async throws {
        guard #available(iOS 26, *) else { return }
        let (controller, _) = try await Self.seededChatList()
        let window = try Self.hostWindow(
            HomeTabView()
                .environment(controller)
                .environment(GateFlags(showsGroupMoney: true, leftAligned: leftAligned) as BetaFlags)
                .injectingEnvironment(from: try SessionContainer.makeTest(holdings: []))
                .injectingEnvironment(from: Container.mock)
        )
        defer { window.isHidden = true }
        let menu = try await Self.rowMenu(in: window)
        if leftAligned {
            #expect(Self.drawnTabBar(in: window) != nil)
        } else {
            #expect(Self.systemTabBar(in: window) != nil)
        }
        #expect(Self.element(labelled: "Archive", in: window) == nil)

        try Self.perform("Select", in: menu)
        try await waitUntil(timeout: .seconds(30)) {
            window.layoutIfNeeded()
            return Self.visibleTabBar(in: window) == nil && Self.element(labelled: "Archive", in: window) != nil
        }
    }

    @Test("8.6 one hosted list follows the gate on, off and on again")
    func groupsList_followsGateFlips() async throws {
        let (controller, _) = try await Self.seededChatList()
        let gate = ShellGate(isOn: true)
        let window = try Self.hostWindow(
            HomeTabView()
                .environment(controller)
                .environment(FlippableGateFlags(gate: gate) as BetaFlags)
                .injectingEnvironment(from: try SessionContainer.makeTest(holdings: []))
                .injectingEnvironment(from: Container.mock)
        )
        defer { window.isHidden = true }
        for isOn in [true, false, true] {
            gate.isOn = isOn
            try await waitUntil(timeout: .seconds(30)) {
                window.layoutIfNeeded()
                guard let bar = Self.navigationBar(in: window) else { return false }
                return Self.barElement(labelled: isOn ? "Groups" : "More", in: bar) != nil
                    && Self.barElement(labelled: isOn ? "More" : "Groups", in: bar) == nil
            }
            let menu = try await Self.rowMenu(in: window)
            #expect(Self.actions(in: menu).map(\.title).contains("Select") == isOn, "gate \(isOn)")
        }
    }

    // MARK: - Shell title

    @Test("8.7 flag on: Groups and Money draw their titles on the same spot, in the same font")
    func shellTitles_sameFrameOnBothTabs() async throws {
        let (controller, _) = try await Self.seededChatList()
        let sessionContainer = try SessionContainer.makeTest(holdings: [])
        let window = try Self.hostWindow(
            HomeTabView()
                .environment(controller)
                .environment(GateFlags(showsGroupMoney: true) as BetaFlags)
                .injectingEnvironment(from: sessionContainer)
                .injectingEnvironment(from: Container.mock)
        )
        defer { window.isHidden = true }
        let groups = try await Self.frame(ofHeader: "Groups", in: window)

        sessionContainer.appRouter.showTab(.wallet)
        let money = try await Self.frame(ofHeader: "Money", in: window)

        #expect(abs(money.minX - groups.minX) <= 0.5, "Money \(money), Groups \(groups)")
        #expect(abs(money.midY - groups.midY) <= 0.5, "Money \(money), Groups \(groups)")
        #expect(abs(money.height - groups.height) <= 0.5, "Money \(money), Groups \(groups)")
    }

    @Test("8.8 flag on: the avatar on Money sits where Add sits on Groups, centred on the title's line")
    func shellTrailingControls_sameSpotOnBothTabs() async throws {
        let (controller, _) = try await Self.seededChatList()
        let sessionContainer = try SessionContainer.makeTest(holdings: [])
        let window = try Self.hostWindow(
            HomeTabView()
                .environment(controller)
                .environment(GateFlags(showsGroupMoney: true) as BetaFlags)
                .injectingEnvironment(from: sessionContainer)
                .injectingEnvironment(from: Container.mock)
        )
        defer { window.isHidden = true }
        let add = try await Self.frame(of: "New group", in: window)
        let groupsTitle = try await Self.frame(ofHeader: "Groups", in: window)

        sessionContainer.appRouter.showTab(.wallet)
        let avatar = try await Self.frame(of: "You", in: window)
        let moneyTitle = try await Self.frame(ofHeader: "Money", in: window)

        // The avatar's frame is the circle's 44pt wide but reads taller than it; its top is the
        // circle's top. Add's frame is its glyph, narrower than its slot, so the two are compared
        // at the slot's centre rather than at their trailing edges.
        let avatarCentre = CGPoint(x: avatar.midX, y: avatar.minY + avatar.width / 2)
        #expect(avatar.width == 44, "avatar \(avatar)")
        #expect(abs(avatarCentre.x - add.midX) <= 0.5, "avatar \(avatar), Add \(add)")
        #expect(abs(avatarCentre.y - add.midY) <= 0.5, "avatar \(avatar), Add \(add)")
        #expect(abs(add.midY - groupsTitle.midY) <= 0.5, "Add \(add), title \(groupsTitle)")
        #expect(abs(avatarCentre.y - moneyTitle.midY) <= 0.5, "avatar \(avatar), title \(moneyTitle)")
    }

    /// The title switched to fades in over the one left, so for a moment the bar draws a mix of
    /// the two. The first switch to Money builds it, which is when its bar items draw late. The
    /// copy of the header left is drawn only: whenever the bar offers VoiceOver the new tab's
    /// title or control, it offers neither of the old tab's. Once the fade is done the bar holds
    /// one title and one control, counting views drawn fully transparent, and draws them as a
    /// switch without the fade leaves them.
    @Test(
        "8.34 flag on: a switch through the bar fades the title in over the one left, and settles on one title and one control",
        arguments: [false, true]
    )
    func barSwitch_fadesTitleAndSettlesOnOne(leftAligned: Bool) async throws {
        guard #available(iOS 26, *) else { return }
        let (window, sessionContainer) = try await Self.hostedShell(leftAligned: leftAligned)
        defer { window.isHidden = true }
        // Groups is the wider title, and both draw from the same spot (8.7).
        let titleRect = try await Self.frame(ofHeader: "Groups", in: window).insetBy(dx: -4, dy: -4)
        _ = try await Self.frame(of: "New group", in: window)
        try await Self.settle(window)
        let groups = Self.pixels(in: titleRect, of: window)

        let toMoney = try await Self.switchThroughBar(from: .groups, to: .money, in: window, capturing: titleRect)
        #expect(Self.shellHeaderItems(in: window) == ShellHeaderItems.money)
        let money = Self.pixels(in: titleRect, of: window)
        #expect(Self.mixes(toMoney, between: groups, and: money), "\(Self.describeMix(toMoney, between: groups, and: money))")

        let toGroups = try await Self.switchThroughBar(from: .money, to: .groups, in: window, capturing: titleRect)
        #expect(Self.shellHeaderItems(in: window) == ShellHeaderItems.groups)
        let back = Self.pixels(in: titleRect, of: window)
        #expect(Self.mixes(toGroups, between: money, and: back), "\(Self.describeMix(toGroups, between: money, and: back))")

        let unfaded = try await Self.groupsAfterRouterTrip(sessionContainer, in: window, capturing: titleRect)
        #expect(Self.difference(back, unfaded) < 0.01, "\(Self.difference(back, unfaded))")
    }

    @Test(
        "8.35 flag on: Money and straight back to Groups through the bar ends on Groups' title and Add alone, drawn as without the fade",
        arguments: [false, true]
    )
    func barSwitch_backBeforeTheFadeEndsSettlesOnGroups(leftAligned: Bool) async throws {
        guard #available(iOS 26, *) else { return }
        let (window, sessionContainer) = try await Self.hostedShell(leftAligned: leftAligned)
        defer { window.isHidden = true }
        let title = try await Self.frame(ofHeader: "Groups", in: window)
        let add = try await Self.frame(of: "New group", in: window)
        try await Self.settle(window)
        let header = title.union(add).insetBy(dx: -4, dy: -4)

        try Self.activateBarTab("Money", in: window)
        try await waitUntil(timeout: .seconds(5)) {
            Self.shellHeaderItems(in: window, includingTransparent: false).titles == ["Money"]
        }
        // Back while Money's header is still fading in.
        try Self.activateBarTab("Groups", in: window)
        try await Task.sleep(for: .milliseconds(1300))
        window.layoutIfNeeded()

        #expect(Self.shellHeaderItems(in: window) == ShellHeaderItems.groups)
        let back = Self.pixels(in: header, of: window)
        let unfaded = try await Self.groupsAfterRouterTrip(sessionContainer, in: window, capturing: header)
        #expect(Self.difference(back, unfaded) < 0.01, "\(Self.difference(back, unfaded))")
    }

    /// A switch into a tab with a screen pushed lands on that screen, not on the root whose header
    /// would fade. When the stack pops back, the root draws Groups' header as it is, with no copy
    /// of Money's over it, however soon after the switch that is. Popped without animation at
    /// once, so a frame that mixes the two headers can only come from a fade.
    @Test(
        "8.36 flag on: through the bar into Groups with a screen pushed, a pop at once shows Groups' header without Money's",
        arguments: [false, true]
    )
    func barSwitch_intoPushedStackFadesNothingOnPop(leftAligned: Bool) async throws {
        guard #available(iOS 26, *) else { return }
        let (window, sessionContainer) = try await Self.hostedShell(leftAligned: leftAligned)
        defer { window.isHidden = true }
        let router = sessionContainer.appRouter
        let title = try await Self.frame(ofHeader: "Groups", in: window)
        let add = try await Self.frame(of: "New group", in: window)
        try await Self.settle(window)
        let header = title.union(add).insetBy(dx: -4, dy: -4)

        _ = try await Self.switchThroughBar(from: .groups, to: .money, in: window, capturing: header)
        let money = Self.pixels(in: header, of: window)
        router.setPath([.newChat], on: .tips)
        try await Self.settle(window)

        try Self.activateBarTab("Groups", in: window)
        var popAtOnce = Transaction()
        popAtOnce.disablesAnimations = true
        withTransaction(popAtOnce) { router.setPath([], on: .tips) }
        var captures: [[UInt8]] = []
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: .milliseconds(700))
        while clock.now < end {
            window.layoutIfNeeded()
            captures.append(Self.pixels(in: header, of: window))
            try await Task.sleep(for: .milliseconds(8))
        }
        try await Task.sleep(for: .milliseconds(600))
        window.layoutIfNeeded()

        #expect(Self.shellHeaderItems(in: window) == ShellHeaderItems.groups)
        let groups = Self.pixels(in: header, of: window)
        #expect(!Self.mixes(captures, between: money, and: groups), "\(Self.describeMix(captures, between: money, and: groups))")
    }

    /// A screen pushed on Groups soon after a switch into it, once its header has faded in, covers
    /// the root's header items. When the stack pops back, the root draws Groups' header as it is,
    /// without running the fade from Money's again. Pushed and popped without animation inside the
    /// second the shell keeps the switch, so a frame that mixes the two headers can only come
    /// from a fade.
    @Test(
        "8.37 flag on: a push and pop on Groups just after a switch into it shows Groups' header without Money's",
        arguments: [false, true]
    )
    func barSwitch_thenPushAndPopFadesNothing(leftAligned: Bool) async throws {
        guard #available(iOS 26, *) else { return }
        let (window, sessionContainer) = try await Self.hostedShell(leftAligned: leftAligned)
        defer { window.isHidden = true }
        let router = sessionContainer.appRouter
        let title = try await Self.frame(ofHeader: "Groups", in: window)
        let add = try await Self.frame(of: "New group", in: window)
        try await Self.settle(window)
        let header = title.union(add).insetBy(dx: -4, dy: -4)

        _ = try await Self.switchThroughBar(from: .groups, to: .money, in: window, capturing: header)
        let money = Self.pixels(in: header, of: window)

        let clock = ContinuousClock()
        let switched = clock.now
        try Self.activateBarTab("Groups", in: window)
        while clock.now < switched.advanced(by: .milliseconds(400)) {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(8))
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { router.setPath([.newChat], on: .tips) }
        var covered = false
        while clock.now < switched.advanced(by: .milliseconds(520)) {
            window.layoutIfNeeded()
            if Self.shellHeaderItems(in: window).titles.isEmpty { covered = true }
            try await Task.sleep(for: .milliseconds(8))
        }
        #expect(covered, "the pushed screen never covered Groups' root before the pop")
        withTransaction(instant) { router.setPath([], on: .tips) }
        let popped = clock.now - switched
        var captures: [[UInt8]] = []
        let end = clock.now.advanced(by: .milliseconds(600))
        while clock.now < end {
            window.layoutIfNeeded()
            captures.append(Self.pixels(in: header, of: window))
            try await Task.sleep(for: .milliseconds(8))
        }
        try await Task.sleep(for: .milliseconds(1000))
        window.layoutIfNeeded()

        #expect(Self.shellHeaderItems(in: window) == ShellHeaderItems.groups)
        let groups = Self.pixels(in: header, of: window)
        #expect(!Self.mixes(captures, between: money, and: groups), "popped at \(popped): \(Self.describeMix(captures, between: money, and: groups))")
    }

    @Test("8.9 flag on: Money's title stays put while the screen scrolls under it, as Groups' does")
    func moneyTitle_pinnedWhileScrolling() async throws {
        let sessionContainer = try SessionContainer.makeTest(holdings: [])
        let window = try Self.hostWindow(
            HomeTabView()
                .environment(GateFlags(showsGroupMoney: true) as BetaFlags)
                .injectingEnvironment(from: sessionContainer)
                .injectingEnvironment(from: Container.mock)
        )
        defer { window.isHidden = true }
        sessionContainer.appRouter.showTab(.wallet)
        let title = try await Self.frame(ofHeader: "Money", in: window)
        let addMoney = try await Self.frame(of: "Add Money", in: window)

        let scroll = try #require(
            Self.scrollViews(in: window).max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        )
        scroll.contentOffset.y += 100
        // Once the content has moved, the title's frame is read from the same pass.
        try await waitUntil(timeout: .seconds(30)) {
            window.layoutIfNeeded()
            let frame = Self.elements(in: window).first { $0.accessibilityLabel == "Add Money" }?.accessibilityFrame
            return frame.map { abs($0.minY - (addMoney.minY - 100)) <= 0.5 } ?? false
        }
        let scrolledTitle = try await Self.frame(ofHeader: "Money", in: window)
        #expect(scrolledTitle == title, "scrolled \(scrolledTitle), resting \(title)")
    }

    // MARK: - Recent activity fills Money

    @Test("8.10 flag on: with a few rows, Recent Activity runs to the bottom of Money and the page does not scroll")
    func moneyActivity_fewRowsFillTheScreen() async throws {
        let (window, _) = try await Self.hostedMoney(activities: 2)
        defer { window.isHidden = true }

        #expect(try await Self.activityRowCount(in: window) == 2)
        let reading = try await Self.overflow(in: window) { abs($0) <= 0.5 }
        #expect(abs(reading.overflow) <= 0.5, "\(reading.description)")
    }

    @Test("8.11 flag on: with no activity, Recent Activity still shows, says so, and runs to the bottom of Money")
    func moneyActivity_emptyFillsTheScreen() async throws {
        let (window, _) = try await Self.hostedMoney(activities: 0)
        defer { window.isHidden = true }

        let header = try await Self.frame(of: MoneyHeaderContent.recentActivityTitle, in: window)
        let empty = try await Self.frame(of: "No activity yet", in: window)
        let reading = try await Self.overflow(in: window) { abs($0) <= 0.5 }
        #expect(abs(reading.overflow) <= 0.5, "\(reading.description)")
        // The message sits in the space the section fills, not straight under its header.
        #expect(empty.minY - header.maxY > 100, "header \(header), message \(empty)")
    }

    @Test("8.12 flag on: with more rows than fit, Money lists ten and the page scrolls to them")
    func moneyActivity_manyRowsScroll() async throws {
        let (window, _) = try await Self.hostedMoney(activities: 30)
        defer { window.isHidden = true }

        #expect(try await Self.activityRowCount(in: window) == 10)
        let reading = try await Self.overflow(in: window) { $0 > 0 }
        #expect(reading.overflow > 0, "\(reading.description)")
    }

    @Test("8.13 flag off: today's wallet still previews three rows of recent activity")
    func standardActivity_keepsThreeRows() async throws {
        let (window, _) = try await Self.hostedMoney(activities: 6, showsGroupMoney: false)
        defer { window.isHidden = true }

        #expect(try await Self.activityRowCount(in: window) == 3)
    }

    // MARK: - Currencies as the card stack

    @Test("8.14 flag on: the currencies screen shows each currency held as a card in today's stack")
    func currencies_showCardStack() async throws {
        let (window, container) = try await Self.hostedCurrencies()
        defer { window.isHidden = true }

        #expect(try await Self.waitForElement(identified: "currency-row", in: window) != nil)
        #expect(try await Self.waitForElement(identified: "currency-row-usdf", in: window) != nil)
        #expect(container.appRouter[.balance] == Self.path(.walletCurrencies))
    }

    @Test("8.15 flag on: the currencies screen keeps the system bar through a card's page; the card opens there with back blocked, and closes back to the stack")
    func currencies_cardOpensAndClosesInPlace() async throws {
        let (window, container) = try await Self.hostedCurrencies()
        defer { window.isHidden = true }

        // The system bar, not a drawn one, so going back hands it to Money's in one transition.
        try await Self.waitForSystemBar(title: "Currencies", in: window)

        try await Self.activate(identified: "currency-row", in: window)
        let close = try await Self.waitForElement(identified: "currency-info-back", in: window)
        // Opened over the currencies screen, not pushed past it.
        #expect(container.appRouter[.balance] == Self.path(.walletCurrencies))
        #expect(try Self.topNavigationItem(in: window).hidesBackButton)
        try await Self.settle(window)
        if #available(iOS 26, *) {
            // The bar stays up and holds the page's buttons, so it never has to come back in.
            #expect(Self.topNavigationController(in: window)?.isNavigationBarHidden == false)
        } else {
            // Below iOS 26 the bar is opaque and would cover the page, which draws its own chrome there.
            try await Self.waitForSystemBar(title: nil, in: window)
        }

        _ = try #require(close).accessibilityActivate()
        try await Self.waitForNoElement(identified: "currency-info-back", in: window)
        #expect(try await Self.waitForElement(identified: "currency-row", in: window) != nil)
        #expect(try Self.topNavigationItem(in: window).hidesBackButton == false)
        try await Self.waitForSystemBar(title: "Currencies", in: window)
        #expect(container.appRouter[.balance] == Self.path(.walletCurrencies))
    }

    @Test(
        "8.16 flag on: a token link while a card is open on the currencies screen opens it on Money, whose tab bar returns on close",
        arguments: [false, true]
    )
    func currencies_deepLinkFromOpenCardLandsOnMoney(leftAligned: Bool) async throws {
        let (window, container) = try await Self.hostedCurrencies(leftAligned: leftAligned)
        defer { window.isHidden = true }
        let router = container.appRouter

        try await Self.activate(identified: "currency-row", in: window)
        _ = try await Self.waitForElement(identified: "currency-info-back", in: window)

        // What `DeepLinkController` does for `flipcash://token/<mint>`.
        router.setPath([], on: .balance)
        router.requestedTab = .wallet
        router.requestedCardMint = .jeffy

        try await waitUntil(timeout: .seconds(30)) {
            window.layoutIfNeeded()
            return router.requestedCardMint == nil && router[.balance].isEmpty
                && Self.element(identified: "currency-info-back", in: window) != nil
                && Self.visibleTabBar(in: window) == nil
        }

        let close = try #require(Self.element(identified: "currency-info-back", in: window))
        _ = close.accessibilityActivate()
        try await waitUntil(timeout: .seconds(30)) {
            window.layoutIfNeeded()
            return Self.element(identified: "currency-info-back", in: window) == nil
                && Self.visibleTabBar(in: window) != nil
        }
        if #available(iOS 26, *) {
            // The bar that comes back is the one the flag picks.
            #expect((Self.systemTabBar(in: window) != nil) == !leftAligned)
            #expect((Self.drawnTabBar(in: window) != nil) == leftAligned)
        }
    }

    @Test("8.17 flag off: today's wallet still opens a card from its stack and closes it back")
    func standardWallet_cardStillOpensAndCloses() async throws {
        let (window, _) = try await Self.hostedMoney(activities: 0, holdings: Self.currencyHoldings, showsGroupMoney: false)
        defer { window.isHidden = true }

        try await Self.activate(identified: "currency-row", in: window)
        let close = try await Self.waitForElement(identified: "currency-info-back", in: window)
        _ = try #require(close).accessibilityActivate()
        try await Self.waitForNoElement(identified: "currency-info-back", in: window)
        #expect(try await Self.waitForElement(identified: "currency-row", in: window) != nil)
    }

    // MARK: - Account switcher on Money's avatar

    @Test("8.18 flag on: holding Money's avatar opens the account switcher, as holding the You tab does")
    func moneyAvatar_holdOpensAccountSwitcher() async throws {
        let (window, container) = try await Self.hostedMoney(activities: 0, canSwitchAccounts: true)
        defer { window.isHidden = true }

        try await Self.performAction(named: "Switch Accounts", onElementIdentified: "money-profile-button", in: window)

        #expect(container.appRouter.presentedSheets == [.switchAccount])
        #expect(container.appRouter.activeTabStack == .balance)
    }

    @Test("8.19 flag on: without account switching, Money's avatar offers no switcher and a hold opens nothing")
    func moneyAvatar_holdOpensNothingWhenSwitchingIsClosed() async throws {
        let (window, container) = try await Self.hostedMoney(activities: 0, canSwitchAccounts: false)
        defer { window.isHidden = true }
        let avatar = try #require(try await Self.waitForElement(identified: "money-profile-button", in: window))

        #expect(!Self.customActionNames(of: avatar).contains("Switch Accounts"), "offered: \(Self.customActionNames(of: avatar))")
        // The avatar's hold calls this whatever the gate says.
        container.appRouter.presentAccountSwitcher(gatedBy: GateFlags(showsGroupMoney: true, canSwitchAccounts: false))
        #expect(container.appRouter.presentedSheet == nil)
    }

    @Test("8.20 flag on: a tap on Money's avatar still opens You, with no sheet over it")
    func moneyAvatar_tapStillOpensYou() async throws {
        let (window, container) = try await Self.hostedMoney(activities: 0, canSwitchAccounts: true)
        defer { window.isHidden = true }

        try await Self.activate(identified: "money-profile-button", in: window)

        try await waitUntil(timeout: .seconds(30)) { container.appRouter.activeTabStack == .you }
        #expect(container.appRouter.presentedSheet == nil)
    }

    // MARK: - Appreciation on Money

    @Test("8.21 flag on: Money shows the appreciation pill under the balance, above the currencies row and Add Money")
    func moneyAppreciation_sitsUnderTheBalance() async throws {
        let (window, _) = try await Self.hostedMoney(activities: 0, holdings: Self.currencyHoldings)
        defer { window.isHidden = true }

        let balance = try await Self.frame(identified: "balance-header", in: window)
        let pill = try await Self.appreciationPill(in: window)
        let currencies = try await Self.frame(identified: "money-currencies-button", in: window)
        let addMoney = try await Self.frame(of: MoneyHeaderContent.addMoneyTitle, in: window)

        #expect(balance.maxY <= pill.frame.minY, "balance \(balance), pill \(pill.frame)")
        #expect(pill.frame.maxY <= currencies.minY, "pill \(pill.frame), currencies \(currencies)")
        #expect(currencies.maxY <= addMoney.minY, "currencies \(currencies), Add Money \(addMoney)")
        // Centred under the balance, as on today's wallet. The amount's frame leaves out the 4pt
        // its outline pads it by on the leading side, so the measured centre sits 2pt right.
        #expect(abs(pill.frame.midX - balance.midX) <= 3, "balance \(balance), pill \(pill.frame)")
    }

    @Test("8.22 flag on: Money's pill reads what today's wallet's pill reads for the same balances")
    func moneyAppreciation_readsAsTodaysWallet() async throws {
        let (money, _) = try await Self.hostedMoney(activities: 0, holdings: Self.currencyHoldings)
        let moneyPill = try await Self.appreciationPill(in: money)
        money.isHidden = true

        let (standard, _) = try await Self.hostedMoney(activities: 0, holdings: Self.currencyHoldings, showsGroupMoney: false)
        defer { standard.isHidden = true }
        let standardPill = try await Self.appreciationPill(in: standard)

        #expect(moneyPill.text == standardPill.text)
        // Held at no cost, the holdings read as a gain rather than an empty pill.
        #expect(moneyPill.text.hasPrefix("+"), "\(moneyPill.text)")
        #expect(moneyPill.text.hasSuffix(" from appreciation"), "\(moneyPill.text)")
    }

    @Test("8.23 flag on: a balance worth less than was paid reads as a depreciation on Money")
    func moneyAppreciation_showsDepreciation() async throws {
        let (window, _) = try await Self.hostedMoney(
            activities: 0,
            holdings: [SessionContainer.Holding(mint: .usdf, quarks: 100_000_000, costBasis: 150)]
        )
        defer { window.isHidden = true }

        let pill = try await Self.appreciationPill(in: window)
        #expect(pill.text == "-\(FiatAmount(value: 50, currency: .usd).formatted()) from depreciation")
    }

    @Test("8.29 flag on: the currencies row sits 10pt under the pill's outline, and the pill stays 4pt under the balance")
    func moneyAppreciation_currenciesRowSitsCloseUnderThePill() async throws {
        let (window, _) = try await Self.hostedMoney(activities: 0, holdings: Self.currencyHoldings)
        defer { window.isHidden = true }

        let balance = try await Self.frame(identified: "balance-header", in: window)
        let outline = try await Self.appreciationPillOutline(in: window)
        let currencies = try await Self.frame(identified: "money-currencies-button", in: window)

        #expect(abs(outline.minY - balance.maxY - 4) <= 0.5, "balance \(balance), outline \(outline)")
        #expect(abs(currencies.minY - outline.maxY - 10) <= 0.5, "outline \(outline), currencies \(currencies)")
    }

    @Test("8.30 flag off: today's wallet keeps its pill 4pt under the balance and 74pt over the card stack")
    func standardAppreciation_keepsItsSpacing() async throws {
        // One launchpad currency: a dollars card is taller than its slot in the stack and reaches
        // above it, so the top card is only the stack's top when it is not dollars.
        let launchpad = try #require(Self.currencyHoldings.last)
        let (window, _) = try await Self.hostedMoney(activities: 0, holdings: [launchpad], showsGroupMoney: false)
        defer { window.isHidden = true }

        let balance = try await Self.frame(identified: "balance-header", in: window)
        let outline = try await Self.appreciationPillOutline(in: window)
        let card = try await Self.frame(identified: "currency-row", in: window)

        #expect(abs(outline.minY - balance.maxY - 4) <= 0.5, "balance \(balance), outline \(outline)")
        #expect(abs(card.minY - outline.maxY - 74) <= 0.5, "outline \(outline), card \(card)")
    }

    // MARK: - Currencies bar through a card's page

    @Test("8.24 flag on: the currencies bar leads with back with no card open and with the page's close while one is, on the same spot")
    func currencies_closeTakesBacksSpot() async throws {
        guard #available(iOS 26, *) else { return }
        let (window, _) = try await Self.hostedCurrencies()
        defer { window.isHidden = true }
        try await Self.waitForSystemBar(title: "Currencies", in: window)
        // The push from Money has finished, so the bar is at rest.
        try await Self.settle(window)

        let back = try await Self.leadingBarControl(in: window)
        #expect(Self.identifier(of: back) != "currency-info-back", "\(Self.describeBar(in: window))")
        let spot = back.accessibilityFrame

        try await Self.activate(identified: "currency-row", in: window)
        _ = try await Self.waitForElement(identified: "currency-info-back", in: window)
        try await Self.settle(window)
        let close = try await Self.leadingBarControl(in: window)
        #expect(Self.identifier(of: close) == "currency-info-back", "\(Self.describeBar(in: window))")
        #expect(close.accessibilityLabel == "Close")
        // Centred on the same point. The close reports its glyph's frame and back its whole
        // button, but the bar draws the same circle around each.
        #expect(Self.isCentred(close.accessibilityFrame, on: spot), "close \(close.accessibilityFrame), back \(spot)")

        _ = close.accessibilityActivate()
        try await Self.waitForNoElement(identified: "currency-info-back", in: window)
        try await Self.settle(window)
        let backAgain = try await Self.leadingBarControl(in: window)
        #expect(Self.identifier(of: backAgain) != "currency-info-back", "\(Self.describeBar(in: window))")
        #expect(Self.isClose(backAgain.accessibilityFrame, to: spot), "back \(backAgain.accessibilityFrame), was \(spot)")
    }

    @Test("8.25 flag on: the currencies title sits centred on back's line in the bar's title font with no card open, and goes while one is")
    func currencies_titleGoesWhileCardOpen() async throws {
        guard #available(iOS 26, *) else { return }
        let (window, _) = try await Self.hostedCurrencies()
        defer { window.isHidden = true }
        try await Self.waitForSystemBar(title: "Currencies", in: window)
        // The push from Money has finished, so the bar is at rest.
        try await Self.settle(window)

        let bar = try #require(Self.topNavigationController(in: window)?.navigationBar)
        let barFrame = bar.convert(bar.bounds, to: nil)
        let back = try await Self.leadingBarControl(in: window).accessibilityFrame
        let title = try await Self.barHeaderFrame("Currencies", in: window)
        #expect(abs(title.midX - barFrame.midX) <= 1, "title \(title) in bar \(barFrame)")
        #expect(abs(title.midY - back.midY) <= 1, "title \(title), back \(back)")
        #expect(title.height >= UIFont.appTitle.lineHeight - 1, "title \(title)")

        try await Self.activate(identified: "currency-row", in: window)
        let close = try await Self.waitForElement(identified: "currency-info-back", in: window)
        try await Self.settle(window)
        #expect(Self.barHeader("Currencies", in: window) == nil, "\(Self.describeBar(in: window))")

        _ = try #require(close).accessibilityActivate()
        try await Self.waitForNoElement(identified: "currency-info-back", in: window)
        let titleAgain = try await Self.barHeaderFrame("Currencies", in: window)
        #expect(Self.isClose(titleAgain, to: title), "title \(titleAgain), was \(title)")
    }

    @Test("8.26 flag on: the currencies bar keeps its place and size whether a card is open or not")
    func currencies_barHoldsStill() async throws {
        guard #available(iOS 26, *) else { return }
        let (window, _) = try await Self.hostedCurrencies()
        defer { window.isHidden = true }
        try await Self.waitForSystemBar(title: "Currencies", in: window)
        // The push from Money has finished, so the bar is at rest.
        try await Self.settle(window)

        let stack = try #require(Self.topNavigationController(in: window))
        let bar = stack.navigationBar
        let resting = bar.convert(bar.bounds, to: nil)

        try await Self.activate(identified: "currency-row", in: window)
        let close = try await Self.waitForElement(identified: "currency-info-back", in: window)
        try await Self.settle(window)
        #expect(!stack.isNavigationBarHidden && !bar.isHidden && bar.alpha > 0.99, "bar hidden with a card open")
        #expect(bar.convert(bar.bounds, to: nil) == resting, "bar \(bar.convert(bar.bounds, to: nil)), was \(resting)")

        _ = try #require(close).accessibilityActivate()
        try await Self.waitForNoElement(identified: "currency-info-back", in: window)
        try await Self.settle(window)
        #expect(!stack.isNavigationBarHidden && !bar.isHidden && bar.alpha > 0.99, "bar hidden after close")
        #expect(bar.convert(bar.bounds, to: nil) == resting, "bar \(bar.convert(bar.bounds, to: nil)), was \(resting)")
    }

    @Test("8.27 flag on: an open card's share sits in the currencies bar, on the close's line, and is not drawn again under it")
    func currencies_shareSitsInBar() async throws {
        guard #available(iOS 26, *) else { return }
        let (window, _) = try await Self.hostedCurrencies()
        defer { window.isHidden = true }
        try await Self.waitForSystemBar(title: "Currencies", in: window)
        // The push from Money has finished, so the bar is at rest.
        try await Self.settle(window)

        try await Self.activate(identified: "currency-row", in: window)
        _ = try await Self.waitForElement(identified: "currency-info-back", in: window)
        try await Self.settle(window)

        let bar = try #require(Self.topNavigationController(in: window)?.navigationBar)
        let barFrame = bar.convert(bar.bounds, to: nil)
        // The bar takes the touches where it sits, so a share drawn by the page under it is dead.
        let share = try #require(Self.barElement(labelled: "Share", in: bar), "\(Self.describeBar(in: window))")
        let close = try await Self.leadingBarControl(in: window)
        #expect(share.accessibilityFrame.minX > barFrame.midX, "share \(share.accessibilityFrame) in bar \(barFrame)")
        #expect(abs(share.accessibilityFrame.midY - close.accessibilityFrame.midY) <= 1)
        // By object, since the element walk can reach one element by more than one path.
        let shares = Self.elements(in: window).filter { $0.accessibilityLabel == "Share" }
        let distinct = Set(shares.map(ObjectIdentifier.init))
        #expect(distinct.count == 1, "\(shares.map { "\(type(of: $0)) \($0.accessibilityFrame)" })")
    }

    @Test("8.28 flag off: today's wallet's card page still draws its own close and share, with no bar over them")
    func standardWallet_pageKeepsItsOwnChrome() async throws {
        let (window, _) = try await Self.hostedMoney(activities: 0, holdings: Self.currencyHoldings, showsGroupMoney: false)
        defer { window.isHidden = true }

        try await Self.activate(identified: "currency-row", in: window)
        let close = try #require(try await Self.waitForElement(identified: "currency-info-back", in: window))
        try await Self.settle(window)
        let bars = Self.visibleNavigationBars(in: window)
        let barElements = bars.flatMap { Self.elements(in: $0) }
        #expect(!barElements.contains { $0 === close }, "close in a bar")
        let share = try #require(Self.element(labelled: "Share", in: window))
        #expect(!barElements.contains { $0 === share }, "share in a bar")
        #expect(bars.allSatisfy { !$0.convert($0.bounds, to: nil).intersects(close.accessibilityFrame) }, "a bar covers the close")
    }

    // MARK: - Currencies in Settings

    @Test("8.31 flag on: Settings lists Create Your Own Currency, then Currency Leaderboard, between Privacy and Advanced")
    func settings_listsCurrenciesBetweenPrivacyAndAdvanced() async throws {
        let (window, container) = try await Self.hostedMoney(activities: 0)
        defer { window.isHidden = true }
        let router = container.appRouter

        try await Self.activate(identified: "money-profile-button", in: window)
        try await waitUntil(timeout: .seconds(30)) { router.activeTabStack == .you }
        // What the You screen's gear does.
        router.push(.settings)

        // Trusted Websites closes Privacy; Notifications sits inside Advanced.
        let order = [
            "settings-trusted-websites-row",
            "settings-create-currency-row",
            "settings-currency-leaderboard-row",
            "settings-notifications-row",
        ]
        var tops: [CGFloat] = []
        for identifier in order {
            let row = try #require(try await Self.waitForElement(identified: identifier, in: window))
            tops.append(row.accessibilityFrame.minY)
        }
        #expect(tops == tops.sorted(), "\(Array(zip(order, tops)))")
    }

    @Test("8.32 flag off: Settings has no Currencies section")
    func standardSettings_hasNoCurrenciesSection() async throws {
        let (window, container) = try await Self.hostedMoney(activities: 0, showsGroupMoney: false)
        defer { window.isHidden = true }
        let router = container.appRouter

        router.showTab(.tipCard)
        try await waitUntil(timeout: .seconds(30)) { router.activeTabStack == .you }
        router.push(.settings)

        _ = try await Self.waitForElement(identified: "settings-notifications-row", in: window)
        #expect(Self.element(identified: "settings-create-currency-row", in: window) == nil)
        #expect(Self.element(identified: "settings-currency-leaderboard-row", in: window) == nil)
    }
}

// MARK: - Hosted tab bar -

/// Answers the shell's gate, the account-switching gate and every flag from what the test passes
/// in, so a flag stored on the test host (other suites write them to `UserDefaults.standard`) does
/// not reach a spec through this stand-in. A flag it is not given reads off; a spec that needs one
/// on passes it. Code that reads `BetaFlags.shared` still gets the stored value.
///
/// `super.init()` still reads the store, so the inherited members this class does not override
/// answer from it: `accessGranted` and what is built on it (`canViewAccountInfo`,
/// `hasVisibleOptions`), `bindingFor(option:)` and `staffStanding(live:userID:)`.
@MainActor
private final class GateFlags: BetaFlags {
    let showsGroupMoney: Bool
    let switchesAccounts: Bool
    let leftAligned: Bool

    init(showsGroupMoney: Bool, canSwitchAccounts: Bool = false, leftAligned: Bool = false) {
        self.showsGroupMoney = showsGroupMoney
        self.switchesAccounts = canSwitchAccounts
        self.leftAligned = leftAligned
        super.init()
    }

    override func showsGroupMoneyUI(isStaff: Bool) -> Bool {
        showsGroupMoney
    }

    override func hasEnabled(_ option: Option) -> Bool {
        option == .leftAlignedTabBar && leftAligned
    }

    override var canSwitchAccounts: Bool {
        switchesAccounts
    }
}

extension GroupMoneyShellSpecTests {

    /// Every flag stored on, as a test host can have them, then each of this file's stand-ins
    /// given none of them.
    @Test(
        "8.33 the specs' flag stand-ins answer off for every flag they are not given, whatever the test host has stored",
        arguments: ShellFlagStandIn.allCases
    )
    func standIns_ignoreStoredFlags(_ standIn: ShellFlagStandIn) throws {
        try BetaFlags.withEveryOptionStored {
            let flags = standIn.makeGivenNoFlags()
            for option in BetaFlags.Option.allCases {
                #expect(!flags.hasEnabled(option), "\(option)")
            }
        }
    }
}

/// This file's ``BetaFlags`` stand-ins, for the guard that none of them answers from the store.
enum ShellFlagStandIn: CaseIterable {
    case gateFlags
    case flippableGateFlags

    @MainActor
    fileprivate func makeGivenNoFlags() -> BetaFlags {
        switch self {
        case .gateFlags: GateFlags(showsGroupMoney: false)
        case .flippableGateFlags: FlippableGateFlags(gate: ShellGate(isOn: false))
        }
    }
}

extension GroupMoneyShellSpecTests {

    /// `HomeTabView` in an iPhone-sized window, and the system tab bar it draws
    /// once every item in that bar is laid out. The caller hides the window.
    @available(iOS 26, *)
    fileprivate func hostedTabBar(showsGroupMoney: Bool) async throws -> (UIWindow, UITabBar) {
        UIAccessibility.enableForHostedTests()
        let sessionContainer = try SessionContainer.makeTest(holdings: [])
        let view = HomeTabView()
            .environment(GateFlags(showsGroupMoney: showsGroupMoney) as BetaFlags)
            .injectingEnvironment(from: sessionContainer)
            .injectingEnvironment(from: Container.mock)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()

        var found: UITabBar?
        do {
            try await waitUntil(timeout: .seconds(30)) {
                window.layoutIfNeeded()
                guard let bar = Self.tabBar(in: window),
                      let itemCount = bar.items?.count, itemCount >= 2,
                      TabBarItemLocator.itemFrames(in: bar).count == itemCount
                else { return false }
                found = bar
                return true
            }
        } catch {
            let bar = Self.tabBar(in: window)
            Issue.record("bar items: \(bar?.items?.map { $0.title ?? "-" } ?? []), frames: \(bar.map(TabBarItemLocator.itemFrames(in:)) ?? []), \(UIAccessibility.hostedTestsState)")
            window.isHidden = true
            throw error
        }
        return (window, try #require(found))
    }

    private static func tabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar, !bar.isHidden { return bar }
        for subview in view.subviews {
            if let bar = tabBar(in: subview) { return bar }
        }
        return nil
    }
}

// MARK: - Hosted chat list -

/// The shell's gate, flipped by a test while one view stays hosted.
@MainActor
@Observable
private final class ShellGate {
    var isOn: Bool
    init(isOn: Bool) { self.isOn = isOn }
}

/// ``GateFlags`` whose answer follows a ``ShellGate``. Reading it inside a view's body tracks the
/// gate, so a flip redraws the hosted view as a stored flag change would. Every flag reads off,
/// whatever the test host has stored.
@MainActor
private final class FlippableGateFlags: BetaFlags {
    let gate: ShellGate

    init(gate: ShellGate) {
        self.gate = gate
        super.init()
    }

    override func showsGroupMoneyUI(isStaff: Bool) -> Bool {
        gate.isOn
    }

    override func hasEnabled(_ option: Option) -> Bool {
        false
    }
}

extension GroupMoneyShellSpecTests {

    /// `HomeTabView` on its launch tab, Groups or Chat, and that list's navigation bar once
    /// `isReady` holds for it. The caller hides the window.
    fileprivate func hostedChatListBar(
        _ flags: BetaFlags,
        until isReady: @escaping (UINavigationBar) -> Bool
    ) async throws -> (UIWindow, UINavigationBar) {
        let window = try Self.hostWindow(
            HomeTabView()
                .environment(flags)
                .injectingEnvironment(from: try SessionContainer.makeTest(holdings: []))
                .injectingEnvironment(from: Container.mock)
        )
        var found: UINavigationBar?
        do {
            try await waitUntil(timeout: .seconds(30)) {
                window.layoutIfNeeded()
                guard let bar = Self.navigationBar(in: window), isReady(bar) else { return false }
                found = bar
                return true
            }
        } catch {
            let bar = Self.navigationBar(in: window)
            Issue.record("bar title: \(bar?.topItem?.title ?? "-"), labels: \(bar.map { Self.elements(in: $0).compactMap(\.accessibilityLabel) } ?? []), \(UIAccessibility.hostedTestsState)")
            window.isHidden = true
            throw error
        }
        return (window, try #require(found))
    }

    /// The wallet tab with `count` activities in its history, newest first. The caller hides the
    /// window.
    fileprivate static func hostedMoney(
        activities count: Int,
        holdings: [SessionContainer.Holding] = [],
        showsGroupMoney: Bool = true,
        canSwitchAccounts: Bool = false,
        leftAligned: Bool = false
    ) async throws -> (UIWindow, SessionContainer) {
        let sessionContainer = try SessionContainer.makeTest(holdings: holdings)
        if !holdings.isEmpty {
            sessionContainer.ratesController.configureTestRates(balanceCurrency: .usd, rates: [Rate(fx: 1.0, currency: .usd)])
        }
        try sessionContainer.database.insertActivities(activities: (0..<count).map { index in
            Activity(
                id: .testMint(index: index),
                state: .completed,
                kind: .received,
                title: "Activity \(index)",
                exchangedFiat: .mockOne,
                date: Date(timeIntervalSinceNow: -Double(index) * 60),
                metadata: nil
            )
        })
        let window = try hostWindow(
            HomeTabView()
                .environment(GateFlags(showsGroupMoney: showsGroupMoney, canSwitchAccounts: canSwitchAccounts, leftAligned: leftAligned) as BetaFlags)
                .injectingEnvironment(from: sessionContainer)
                .injectingEnvironment(from: Container.mock)
        )
        sessionContainer.appRouter.showTab(.wallet)
        return (window, sessionContainer)
    }

    /// Dollars and one launchpad currency: two cards in the stack.
    fileprivate static var currencyHoldings: [SessionContainer.Holding] {
        [
            SessionContainer.Holding(mint: .usdf, quarks: 100_000_000),
            SessionContainer.Holding(
                mint: MintMetadata.makeLaunchpad(address: .jeffy, supplyFromBonding: 10_000 * 10_000_000_000),
                quarks: 1_000_000_000_000
            ),
        ]
    }

    /// Money with ``currencyHoldings``, with the currencies screen pushed from "N currencies".
    /// The caller hides the window.
    fileprivate static func hostedCurrencies(leftAligned: Bool = false) async throws -> (UIWindow, SessionContainer) {
        let (window, container) = try await hostedMoney(activities: 0, holdings: currencyHoldings, leftAligned: leftAligned)
        _ = try await waitForElement(identified: "money-currencies-button", in: window)
        MoneyAction.currencies.perform(on: container.appRouter)
        return (window, container)
    }

    /// The first element carrying `identifier`, when one is on screen.
    fileprivate static func element(identified identifier: String, in view: UIView) -> NSObject? {
        elements(in: view).first { self.identifier(of: $0) == identifier }
    }

    /// The first element carrying `identifier`, once one is on screen.
    fileprivate static func waitForElement(identified identifier: String, in window: UIWindow) async throws -> NSObject? {
        var found: NSObject?
        do {
            try await waitUntil(timeout: .seconds(30)) {
                window.layoutIfNeeded()
                found = element(identified: identifier, in: window)
                return found != nil
            }
        } catch {
            Issue.record("no \(identifier); on screen: \(elements(in: window).compactMap { self.identifier(of: $0) }), \(UIAccessibility.hostedTestsState)")
            throw error
        }
        return found
    }

    /// Returns once nothing on screen carries `identifier`.
    fileprivate static func waitForNoElement(identified identifier: String, in window: UIWindow) async throws {
        try await waitUntil(timeout: .seconds(30)) {
            window.layoutIfNeeded()
            return element(identified: identifier, in: window) == nil
        }
    }

    /// Activates the first element carrying `identifier`, as VoiceOver's double tap does.
    fileprivate static func activate(identified identifier: String, in window: UIWindow) async throws {
        let target = try #require(try await waitForElement(identified: identifier, in: window))
        #expect(target.accessibilityActivate(), "\(identifier) did not activate")
    }

    /// The names of the custom actions VoiceOver offers on `element`.
    fileprivate static func customActionNames(of element: NSObject) -> [String] {
        (element.accessibilityCustomActions ?? []).map(\.name)
    }

    /// Runs the custom action named `name` on the first element carrying `identifier`, as
    /// VoiceOver's actions rotor does.
    fileprivate static func performAction(
        named name: String,
        onElementIdentified identifier: String,
        in window: UIWindow
    ) async throws {
        let target = try #require(try await waitForElement(identified: identifier, in: window))
        let action = try #require(
            target.accessibilityCustomActions?.first { $0.name == name },
            "no \(name) action on \(identifier); offered: \(customActionNames(of: target))"
        )
        if let handler = action.actionHandler {
            #expect(handler(action), "\(name) did not run")
        } else {
            let receiver = try #require(action.target as? NSObject, "\(name) has neither a handler nor a target")
            _ = receiver.perform(action.selector, with: action)
        }
    }

    /// The navigation stack showing in `window` with a screen pushed onto it, if any.
    /// Returns `nil` rather than failing, so it can be polled.
    fileprivate static func topNavigationController(in window: UIWindow) -> UINavigationController? {
        func controllers(under controller: UIViewController) -> [UIViewController] {
            [controller] + controller.children.flatMap(controllers(under:))
                + (controller.presentedViewController.map(controllers(under:)) ?? [])
        }
        guard let root = window.rootViewController else { return nil }
        return controllers(under: root)
            .compactMap { $0 as? UINavigationController }
            .last { $0.view.window != nil && !$0.view.isHidden && $0.viewControllers.count > 1 }
    }

    /// The navigation item of the screen on top of the stack showing in `window`.
    fileprivate static func topNavigationItem(in window: UIWindow) throws -> UINavigationItem {
        try #require(topNavigationController(in: window)?.topViewController?.navigationItem)
    }

    /// Waits until the top stack's system bar shows `title`, or is hidden when `title` is `nil`.
    fileprivate static func waitForSystemBar(title: String?, in window: UIWindow) async throws {
        try await waitUntil(timeout: .seconds(30)) {
            guard let stack = topNavigationController(in: window) else { return false }
            guard let title else { return stack.isNavigationBarHidden }
            return !stack.isNavigationBarHidden && stack.topViewController?.navigationItem.title == title
        }
    }

    /// Lets a card's opening or closing run out, so what is read after it is where things rest.
    fileprivate static func settle(_ window: UIWindow) async throws {
        try await Task.sleep(for: .milliseconds(900))
        window.layoutIfNeeded()
    }

    /// The control at the leading end of the top stack's bar, once the bar shows one.
    fileprivate static func leadingBarControl(in window: UIWindow) async throws -> NSObject {
        var found: NSObject?
        do {
            try await waitUntil(timeout: .seconds(5)) {
                window.layoutIfNeeded()
                guard let stack = topNavigationController(in: window), !stack.isNavigationBarHidden else { return false }
                found = elements(in: stack.navigationBar)
                    .filter { $0.accessibilityTraits.contains(.button) }
                    .min { $0.accessibilityFrame.minX < $1.accessibilityFrame.minX }
                return found != nil
            }
        } catch {
            Issue.record("no leading control; \(describeBar(in: window))")
            throw error
        }
        return try #require(found)
    }

    /// The header labelled `label` in the top stack's bar, if it shows one.
    fileprivate static func barHeader(_ label: String, in window: UIWindow) -> NSObject? {
        guard let stack = topNavigationController(in: window), !stack.isNavigationBarHidden else { return nil }
        return elements(in: stack.navigationBar).first {
            $0.accessibilityLabel == label && $0.accessibilityTraits.contains(.header)
        }
    }

    /// The frame of the header labelled `label` in the top stack's bar, once it shows.
    fileprivate static func barHeaderFrame(_ label: String, in window: UIWindow) async throws -> CGRect {
        var frame: CGRect?
        do {
            try await waitUntil(timeout: .seconds(5)) {
                window.layoutIfNeeded()
                frame = barHeader(label, in: window)?.accessibilityFrame
                return frame != nil
            }
        } catch {
            Issue.record("no \(label) header; \(describeBar(in: window))")
            throw error
        }
        return try #require(frame)
    }

    /// What the top stack's bar shows, for failure messages.
    fileprivate static func describeBar(in window: UIWindow) -> String {
        guard let stack = topNavigationController(in: window) else { return "no stack" }
        if stack.isNavigationBarHidden { return "bar hidden" }
        let items = elements(in: stack.navigationBar).map {
            "\($0.accessibilityLabel ?? "?")[\(identifier(of: $0) ?? "-")] \($0.accessibilityFrame)"
        }
        return "bar: \(items), \(UIAccessibility.hostedTestsState)"
    }

    /// Whether two frames are the same to within a point.
    fileprivate static func isClose(_ frame: CGRect, to other: CGRect) -> Bool {
        abs(frame.minX - other.minX) <= 1 && abs(frame.minY - other.minY) <= 1
            && abs(frame.width - other.width) <= 1 && abs(frame.height - other.height) <= 1
    }

    /// Whether two frames share a centre to within a point.
    fileprivate static func isCentred(_ frame: CGRect, on other: CGRect) -> Bool {
        abs(frame.midX - other.midX) <= 1 && abs(frame.midY - other.midY) <= 1
    }

    /// Every navigation bar showing in `view`.
    fileprivate static func visibleNavigationBars(in view: UIView) -> [UINavigationBar] {
        guard !view.isHidden, view.alpha > 0.01 else { return [] }
        let own = (view as? UINavigationBar).map { [$0] } ?? []
        return own + view.subviews.flatMap(visibleNavigationBars(in:))
    }

    /// How many recent-activity rows the wallet draws, once that count has held for two passes.
    /// Counted by frame, since the element walk can reach one row by more than one path.
    fileprivate static func activityRowCount(in window: UIWindow) async throws -> Int {
        var last: Int?
        var settled: Int?
        try await waitUntil(timeout: .seconds(30)) {
            window.layoutIfNeeded()
            let rows = elements(in: window).filter { identifier(of: $0) == "recent-activity-row" }
            let count = Set(rows.map { "\($0.accessibilityFrame)" }).count
            defer { last = count }
            guard count > 0 || element(labelled: "Add Money", in: window) != nil
                    || element(labelled: "Recent", in: window) != nil,
                  count == last else { return false }
            settled = count
            return true
        }
        return try #require(settled)
    }

    /// The tab's own scroll view: the largest visible one.
    fileprivate static func mainScrollView(in window: UIWindow) throws -> UIScrollView {
        window.layoutIfNeeded()
        return try #require(
            scrollViews(in: window).max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        )
    }

    /// How far `scroll`'s content runs past what it shows between its insets: zero when the
    /// content exactly fills it, negative when it stops short.
    fileprivate static func overflow(of scroll: UIScrollView) -> CGFloat {
        let visible = scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom
        return scroll.contentSize.height - visible
    }

    /// The tab's scroll view overflow once `holds` accepts it, or its last reading after
    /// `timeout`, with a description for a failure message. Polled, since the content's minimum
    /// height follows the scroll view's own measured height a pass after the first layout.
    fileprivate static func overflow(
        in window: UIWindow,
        timeout: Duration = .seconds(10),
        until holds: (CGFloat) -> Bool
    ) async throws -> (overflow: CGFloat, description: String) {
        let deadline = ContinuousClock().now + timeout
        while true {
            let scroll = try mainScrollView(in: window)
            let reading = (overflow(of: scroll), describe(scroll))
            if holds(reading.0) || ContinuousClock().now >= deadline { return reading }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// `scroll`'s content size, bounds and adjusted insets, for a failure message.
    fileprivate static func describe(_ scroll: UIScrollView) -> String {
        "content \(scroll.contentSize), bounds \(scroll.bounds), insets \(String(describing: scroll.adjustedContentInset))"
    }

    /// The accessibility identifier `element` carries, when it has one.
    fileprivate static func identifier(of element: NSObject) -> String? {
        if let identified = element as? UIAccessibilityIdentification {
            return identified.accessibilityIdentifier
        }
        guard element.responds(to: NSSelectorFromString("accessibilityIdentifier")) else { return nil }
        return element.value(forKey: "accessibilityIdentifier") as? String
    }

    /// `view` in an iPhone-sized key window.
    fileprivate static func hostWindow(_ view: some View) throws -> UIWindow {
        UIAccessibility.enableForHostedTests()
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        return window
    }

    /// A chat list holding one read DM with a message, so its row has the long-press menu.
    fileprivate static func seededChatList() async throws -> (ConversationController, ConversationID) {
        let me = UUID()
        let them = UUID()
        let mock = MockConversations()
        let conversation = Conversation(
            id: .test(1),
            members: [
                ConversationMember(userID: me, displayName: "", readPointer: MessageID(value: 5)),
                ConversationMember(userID: them, displayName: "Them"),
            ],
            lastMessage: ConversationMessage(
                id: MessageID(value: 5),
                senderID: them,
                content: .text("hi"),
                date: Date(timeIntervalSince1970: 5),
                unreadSeq: 5
            ),
            lastActivity: Date(timeIntervalSince1970: 999),
            type: .tipDm
        )
        mock.feed = [conversation]
        let controller = ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: try Database.makeTemp().database,
            owner: .generate()!, selfUserID: me
        )
        await controller.loadFeed()
        return (controller, conversation.id)
    }

    /// The menu the first row with a long-press menu would show, asked of the list's collection
    /// view the way UIKit asks it on a long press.
    fileprivate static func rowMenu(in window: UIWindow) async throws -> UIMenu {
        var found: UIMenu?
        try await waitUntil(timeout: .seconds(30)) {
            window.layoutIfNeeded()
            found = collectionViews(in: window).lazy.compactMap(firstRowMenu(in:)).first
            return found != nil
        }
        return try #require(found)
    }

    private static func firstRowMenu(in collection: UICollectionView) -> UIMenu? {
        for section in 0..<collection.numberOfSections {
            for item in 0..<collection.numberOfItems(inSection: section) {
                let indexPath = IndexPath(item: item, section: section)
                guard let configuration = collection.delegate?.collectionView?(
                    collection,
                    contextMenuConfigurationForItemsAt: [indexPath],
                    point: .zero
                ), let provider = configuration.value(forKey: "actionProvider") else { continue }
                typealias Provider = @convention(block) ([UIMenuElement]) -> UIMenu?
                return unsafeBitCast(provider as AnyObject, to: Provider.self)([])
            }
        }
        return nil
    }

    /// The menu's actions in order, sections flattened.
    fileprivate static func actions(in menu: UIMenu) -> [UIAction] {
        menu.children.flatMap { element -> [UIAction] in
            if let submenu = element as? UIMenu { return actions(in: submenu) }
            return (element as? UIAction).map { [$0] } ?? []
        }
    }

    /// Runs the action titled `title`, as choosing it from the menu does.
    fileprivate static func perform(_ title: String, in menu: UIMenu) throws {
        let action = try #require(actions(in: menu).first { $0.title == title })
        typealias Handler = @convention(block) (UIAction) -> Void
        let handler = try #require(action.value(forKey: "handler"))
        unsafeBitCast(handler as AnyObject, to: Handler.self)(action)
    }

    fileprivate static func navigationBar(in view: UIView) -> UINavigationBar? {
        if let bar = view as? UINavigationBar, !bar.isHidden, bar.window != nil { return bar }
        for subview in view.subviews {
            if let bar = navigationBar(in: subview) { return bar }
        }
        return nil
    }

    /// Whichever tab bar is on screen: the system bar, or the shell's small bar drawn in its place
    /// with Left-Aligned Tab Bar on.
    fileprivate static func visibleTabBar(in view: UIView) -> NSObject? {
        systemTabBar(in: view) ?? drawnTabBar(in: view)
    }

    fileprivate static func systemTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar, !bar.isHidden, bar.alpha > 0.01, bar.window != nil { return bar }
        for subview in view.subviews {
            if let bar = systemTabBar(in: subview) { return bar }
        }
        return nil
    }

    /// The shell's small bar: the accessibility container it marks as a tab bar, while it holds
    /// items. Hidden views and the system bar are skipped, and the small bar drops out of the
    /// accessibility tree when it slides out or fades for select mode.
    fileprivate static func drawnTabBar(in view: UIView) -> NSObject? {
        func walk(_ object: NSObject, depth: Int) -> NSObject? {
            guard depth < 40, !(object is UITabBar) else { return nil }
            if let view = object as? UIView, view.isHidden || view.alpha <= 0.01 { return nil }
            let children = (object.accessibilityElements ?? []).compactMap { $0 as? NSObject }
            if object.accessibilityTraits.contains(.tabBar), !children.isEmpty { return object }
            for child in children {
                if let bar = walk(child, depth: depth + 1) { return bar }
            }
            if let view = object as? UIView {
                for subview in view.subviews {
                    if let bar = walk(subview, depth: depth + 1) { return bar }
                }
            }
            return nil
        }
        return walk(view, depth: 0)
    }

    /// Visible scroll views under `view` that are not a list's collection view.
    fileprivate static func scrollViews(in view: UIView) -> [UIScrollView] {
        guard !view.isHidden, view.alpha > 0.01 else { return [] }
        let own = (view as? UIScrollView).flatMap { $0 is UICollectionView ? nil : [$0] } ?? []
        return own + view.subviews.flatMap(scrollViews(in:))
    }

    private static func collectionViews(in view: UIView) -> [UICollectionView] {
        let own = (view as? UICollectionView).map { [$0] } ?? []
        return own + view.subviews.flatMap(collectionViews(in:))
    }

    /// Bar titles drawn by UIKit: the centred title, when the bar shows one.
    fileprivate static func titleLabels(in bar: UINavigationBar) -> [UILabel] {
        func labels(in view: UIView) -> [UILabel] {
            guard !view.isHidden, view.alpha > 0.01 else { return [] }
            let own = (view as? UILabel).flatMap { $0.text?.isEmpty == false ? [$0] : nil } ?? []
            return own + view.subviews.flatMap(labels(in:))
        }
        return labels(in: bar)
    }

    fileprivate static func barElement(labelled label: String, in bar: UINavigationBar) -> NSObject? {
        elements(in: bar).first { $0.accessibilityLabel == label }
    }

    fileprivate static func element(labelled label: String, in view: UIView) -> NSObject? {
        elements(in: view).first { $0.accessibilityLabel == label }
    }

    /// The on-screen frame of the header labelled `label`: a screen's title, not the tab of the
    /// same name.
    fileprivate static func frame(ofHeader label: String, in window: UIWindow) async throws -> CGRect {
        try await frame(in: window) { $0.accessibilityLabel == label && $0.accessibilityTraits.contains(.header) }
    }

    /// The on-screen frame of the element labelled `label`.
    fileprivate static func frame(of label: String, in window: UIWindow) async throws -> CGRect {
        try await frame(in: window) { $0.accessibilityLabel == label }
    }

    /// The on-screen frame of the element carrying `identifier`.
    fileprivate static func frame(identified identifier: String, in window: UIWindow) async throws -> CGRect {
        try await frame(in: window) { self.identifier(of: $0) == identifier }
    }

    /// The wallet's appreciation pill: its amount and label read as one line, and the frame
    /// the two take together. The pill is two texts, the amount leading the label on its line.
    fileprivate static func appreciationPill(in window: UIWindow) async throws -> (text: String, frame: CGRect) {
        let labels: Set<String> = ["from appreciation", "from depreciation"]
        let word = try await frame(in: window) { labels.contains($0.accessibilityLabel ?? "") }
        let wordLabel = try #require(elements(in: window).first { $0.accessibilityFrame == word }?.accessibilityLabel)
        let amount = try #require(
            elements(in: window)
                .filter { abs($0.accessibilityFrame.midY - word.midY) <= 1 && $0.accessibilityFrame.maxX <= word.minX }
                .max { $0.accessibilityFrame.maxX < $1.accessibilityFrame.maxX },
            "no amount beside \(wordLabel); on screen: \(elements(in: window).compactMap(\.accessibilityLabel))"
        )
        return ("\(amount.accessibilityLabel ?? "") \(wordLabel)", word.union(amount.accessibilityFrame))
    }

    /// The pill's outline as drawn: the texts' frame grown by the 3pt the outline pads the amount
    /// by above and below, which the amount's own frame leaves out.
    fileprivate static func appreciationPillOutline(in window: UIWindow) async throws -> CGRect {
        try await appreciationPill(in: window).frame.insetBy(dx: 0, dy: -3)
    }

    /// The on-screen frame of the first element `matches` picks, once it has held the same
    /// frame for two layout passes in a row.
    private static func frame(in window: UIWindow, matching matches: @escaping (NSObject) -> Bool) async throws -> CGRect {
        var last: CGRect?
        var settled: CGRect?
        try await waitUntil(timeout: .seconds(30)) {
            window.layoutIfNeeded()
            guard let frame = elements(in: window).first(where: matches)?.accessibilityFrame,
                  !frame.isEmpty else { return false }
            defer { last = frame }
            guard frame == last else { return false }
            settled = frame
            return true
        }
        return try #require(settled)
    }

    /// The full shell, Groups first, with the bar `leftAligned` picks.
    fileprivate static func hostedShell(leftAligned: Bool) async throws -> (UIWindow, SessionContainer) {
        let (controller, _) = try await seededChatList()
        let sessionContainer = try SessionContainer.makeTest(holdings: [])
        let window = try hostWindow(
            HomeTabView()
                .environment(controller)
                .environment(GateFlags(showsGroupMoney: true, leftAligned: leftAligned) as BetaFlags)
                .injectingEnvironment(from: sessionContainer)
                .injectingEnvironment(from: Container.mock)
        )
        return (window, sessionContainer)
    }

    /// What the window draws in `rect` once Groups is back from Money through the router, which
    /// switches without the headers' fade: Groups' header with nothing of a fade left on it.
    ///
    /// Compared with Groups after a switch through the bar rather than with Groups at launch: on
    /// the system bar a tab brought back draws a slightly darker backdrop behind its title than it
    /// did the first time, with or without the fade.
    fileprivate static func groupsAfterRouterTrip(
        _ sessionContainer: SessionContainer,
        in window: UIWindow,
        capturing rect: CGRect
    ) async throws -> [UInt8] {
        sessionContainer.appRouter.showTab(.wallet)
        try await waitUntil(timeout: .seconds(5)) {
            shellHeaderItems(in: window, includingTransparent: false).titles == ["Money"]
        }
        sessionContainer.appRouter.showTab(.chat)
        try await waitUntil(timeout: .seconds(5)) {
            shellHeaderItems(in: window, includingTransparent: false).titles == ["Groups"]
        }
        try await settle(window)
        return pixels(in: rect, of: window)
    }

    /// Picks the tab labelled `label` on whichever tab bar is on screen: a switch through the bar
    /// rather than through the router. The small bar's item is activated as VoiceOver's double tap
    /// does. The system bar's buttons take no accessibility activation in a test host, so its tab
    /// is picked the way UIKit picks it on a tap: the delegate is asked, the tab selected, and the
    /// delegate told.
    fileprivate static func activateBarTab(_ label: String, in window: UIWindow) throws {
        window.layoutIfNeeded()
        let bar = try #require(visibleTabBar(in: window), "no tab bar")
        if let tabBar = bar as? UITabBar {
            let controller = try #require(tabBar.delegate as? UITabBarController, "the system bar has no tab bar controller")
            let tab = try #require(
                controller.tabs.first { $0.title == label },
                "no \(label) on the system bar; on it: \(controller.tabs.map(\.title))"
            )
            let previous = try #require(controller.selectedTab, "the system bar has no tab selected")
            let delegate = controller.delegate
            guard delegate?.tabBarController?(controller, shouldSelectTab: tab) ?? true else {
                Issue.record("the system bar refused \(label)")
                return
            }
            controller.selectedTab = tab
            delegate?.tabBarController?(controller, didSelectTab: tab, previousTab: previous)
            return
        }
        let items = elements(under: bar)
        let item = try #require(
            items.first { $0.accessibilityLabel == label },
            "no \(label) on the bar; on it: \(items.compactMap(\.accessibilityLabel))"
        )
        #expect(item.accessibilityActivate(), "\(label) did not activate")
    }

    /// Switches from one shell tab to the other through the bar and returns once its header fade
    /// has run out, with what the window drew in `rect` on the way.
    ///
    /// Throughout, whenever the bar offers VoiceOver `to`'s title or control, it must offer
    /// neither of `from`'s.
    fileprivate static func switchThroughBar(
        from: ShellHeaderItems,
        to: ShellHeaderItems,
        in window: UIWindow,
        capturing rect: CGRect
    ) async throws -> [[UInt8]] {
        try activateBarTab(to.titles[0], in: window)
        var captures: [[UInt8]] = []
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: .milliseconds(700))
        while clock.now < end {
            let offered = shellHeaderItems(in: window, includingTransparent: false)
            let arrived = !Set(offered.titles + offered.controls).isDisjoint(with: to.titles + to.controls)
            let stayed = Set(offered.titles + offered.controls).intersection(from.titles + from.controls)
            if arrived && !stayed.isEmpty {
                Issue.record("the bar offers \(stayed.sorted()) beside \(to.titles[0])'s header: \(offered)")
            }
            captures.append(pixels(in: rect, of: window))
            try await Task.sleep(for: .milliseconds(8))
        }
        // The shell clears its switch a second after it starts.
        try await Task.sleep(for: .milliseconds(600))
        window.layoutIfNeeded()
        return captures
    }

    /// The shell's titles and trailing controls the bar on screen offers VoiceOver, by label.
    struct ShellHeaderItems: Equatable, CustomStringConvertible {
        let titles: [String]
        let controls: [String]

        static let groups = ShellHeaderItems(titles: ["Groups"], controls: ["New group"])
        static let money = ShellHeaderItems(titles: ["Money"], controls: ["You"])

        var description: String { "titles \(titles), controls \(controls)" }
    }

    /// What the bar on screen offers of the shell's titles and trailing controls. With
    /// `includingTransparent`, views drawn fully transparent count too, so a header left in
    /// place but hidden still shows up.
    fileprivate static func shellHeaderItems(in window: UIWindow, includingTransparent: Bool = true) -> ShellHeaderItems {
        window.layoutIfNeeded()
        guard let bar = navigationBar(in: window) else { return ShellHeaderItems(titles: [], controls: []) }
        // The walk reaches an element both as an accessibility child and through its view, so
        // each is counted once. By identity, so a second element on the same spot still counts.
        var seen = Set<ObjectIdentifier>()
        let found = elements(under: bar, includingTransparent: includingTransparent)
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
        let titles = found
            .filter { $0.accessibilityTraits.contains(.header) }
            .compactMap(\.accessibilityLabel)
            .filter { ["Groups", "Money"].contains($0) }
        let controls = found.compactMap(\.accessibilityLabel).filter { ["New group", "You"].contains($0) }
        return ShellHeaderItems(titles: titles, controls: controls)
    }

    /// What the window draws in `rect`, one pixel to a point, as red, green, blue and alpha bytes.
    fileprivate static func pixels(in rect: CGRect, of window: UIWindow) -> [UInt8] {
        let width = Int(rect.width.rounded(.up))
        let height = Int(rect.height.rounded(.up))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.translateBy(x: -rect.minX, y: CGFloat(height) + rect.minY)
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            UIGraphicsPopContext()
        }
        return bytes
    }

    /// How far apart two captures of the same rect are: the mean difference per channel, 0 to 1.
    fileprivate static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var total = 0
        for index in a.indices { total += abs(Int(a[index]) - Int(b[index])) }
        return Double(total) / Double(a.count) / 255
    }

    /// Where each capture sits between `start` and `end`: its distance from each, as a share of
    /// theirs. A mix of the two at `t` reads (t, 1 - t). A frame with neither drawn reads about
    /// (1, 1), which is why the sum is checked too.
    fileprivate static func mixPositions(_ captures: [[UInt8]], between start: [UInt8], and end: [UInt8]) -> [(Double, Double)] {
        let span = difference(start, end)
        guard span > 0 else { return [] }
        return captures.map { (difference($0, start) / span, difference($0, end) / span) }
    }

    /// Whether some capture is a mix of `start` and `end`, at least 15% of the way from each.
    fileprivate static func mixes(_ captures: [[UInt8]], between start: [UInt8], and end: [UInt8]) -> Bool {
        guard difference(start, end) > 0.005 else { return false }
        return mixPositions(captures, between: start, and: end).contains { $0 > 0.15 && $1 > 0.15 && $0 + $1 < 1.3 }
    }

    fileprivate static func describeMix(_ captures: [[UInt8]], between start: [UInt8], and end: [UInt8]) -> String {
        let positions = mixPositions(captures, between: start, and: end)
            .map { String(format: "(%.2f, %.2f)", $0, $1) }
        return "rest frames \(String(format: "%.4f", difference(start, end))) apart; captures: \(positions)"
    }

    /// Every accessibility element under `view`, including SwiftUI's hosted nodes.
    fileprivate static func elements(in view: UIView) -> [NSObject] {
        elements(under: view)
    }

    /// Every accessibility element under `object`. Views drawn fully transparent are skipped
    /// unless `includingTransparent`.
    fileprivate static func elements(under object: NSObject, includingTransparent: Bool = false) -> [NSObject] {
        func walk(_ object: NSObject, depth: Int) -> [NSObject] {
            guard depth < 40 else { return [] }
            if let view = object as? UIView, view.isHidden || (!includingTransparent && view.alpha <= 0.01) { return [] }
            var found: [NSObject] = []
            if object.isAccessibilityElement { found.append(object) }
            for case let element as NSObject in object.accessibilityElements ?? [] {
                found += walk(element, depth: depth + 1)
            }
            if let view = object as? UIView {
                for subview in view.subviews { found += walk(subview, depth: depth + 1) }
            }
            return found
        }
        return walk(object, depth: 0)
    }
}
