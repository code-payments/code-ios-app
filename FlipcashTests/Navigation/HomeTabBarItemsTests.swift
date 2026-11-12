//
//  HomeTabBarItemsTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

/// Which tabs the system bar's items are paired with when the selected-icon
/// probe gives each item its glyphs. For one pass after the Group Money gate
/// flips, the bar still holds the other layout's items.
@Suite("Home tab bar items") @MainActor
struct HomeTabBarItemsTests {

    @Test("Today's bar pairs its four tabs with or without the search item")
    func standardCounts() {
        #expect(HomeTabLayout.standard.barTabs(forItemCount: 5) == [.scan, .chat, .wallet, .tipCard])
        #expect(HomeTabLayout.standard.barTabs(forItemCount: 4) == [.scan, .chat, .wallet, .tipCard])
    }

    @Test("The Group Money bar pairs Groups and Money with or without the search item")
    func groupMoneyCounts() {
        #expect(HomeTabLayout.groupMoney.barTabs(forItemCount: 3) == [.chat, .wallet])
        #expect(HomeTabLayout.groupMoney.barTabs(forItemCount: 2) == [.chat, .wallet])
    }

    @Test("Turning Group Money on leaves today's five items unpaired until the bar rebuilds")
    func staleStandardBarAfterTurningOn() {
        #expect(HomeTabLayout.groupMoney.barTabs(forItemCount: 5) == nil)
        #expect(HomeTabLayout.groupMoney.barTabs(forItemCount: 4) == nil)
    }

    @Test("Turning Group Money off leaves its three items unpaired until the bar rebuilds")
    func staleGroupMoneyBarAfterTurningOff() {
        #expect(HomeTabLayout.standard.barTabs(forItemCount: 3) == nil)
        #expect(HomeTabLayout.standard.barTabs(forItemCount: 2) == nil)
    }

    @Test("A bar with no items yet is left for the retry")
    func emptyBar() {
        #expect(HomeTabLayout.standard.barTabs(forItemCount: 0) == nil)
        #expect(HomeTabLayout.groupMoney.barTabs(forItemCount: 0) == nil)
    }
}
