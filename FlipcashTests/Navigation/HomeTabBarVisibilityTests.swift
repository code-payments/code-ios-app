//
//  HomeTabBarVisibilityTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@MainActor
@Suite("Home tab bar visibility")
struct HomeTabBarVisibilityTests {

    @Test("an expanded wallet card hides the bar only on the Wallet tab", arguments: HomeTab.allCases)
    func walletCard_hidesOnlyOnWallet(tab: HomeTab) {
        let hidden = tab.hidesTabBar(
            isWalletCardExpanded: true,
            isShowingBill: false,
            isShowingProfileCard: false,
            hasPushedScreen: false
        )
        #expect(hidden == (tab == .wallet))
    }

    @Test("a bill or a pushed screen hides the bar on every tab", arguments: HomeTab.allCases)
    func billOrPush_hidesEverywhere(tab: HomeTab) {
        #expect(tab.hidesTabBar(isWalletCardExpanded: false, isShowingBill: true, isShowingProfileCard: false, hasPushedScreen: false))
        #expect(tab.hidesTabBar(isWalletCardExpanded: false, isShowingBill: false, isShowingProfileCard: false, hasPushedScreen: true))
    }

    @Test("the profile card hides the bar only on the You tab", arguments: HomeTab.allCases)
    func profileCard_hidesOnlyOnYou(tab: HomeTab) {
        let hidden = tab.hidesTabBar(
            isWalletCardExpanded: false,
            isShowingBill: false,
            isShowingProfileCard: true,
            hasPushedScreen: false
        )
        #expect(hidden == (tab == .tipCard))
    }

    @Test("nothing open shows the bar", arguments: HomeTab.allCases)
    func idle_shows(tab: HomeTab) {
        #expect(!tab.hidesTabBar(isWalletCardExpanded: false, isShowingBill: false, isShowingProfileCard: false, hasPushedScreen: false))
    }
}
