//
//  HomeTabLayout.swift
//  Flipcash
//

import SwiftUI

/// Which tab bar the home shell draws: today's four tabs, or the Group Money
/// redesign's two (Groups, node 13729:413; Money, node 13729:744), behind
/// ``BetaFlags/Option/groupMoneyUI``.
///
/// The redesign takes Scan and You off the bar, not out of the app. The router
/// still asks for them — a scanned tip card, a `/tab/you` link, the Money
/// avatar — so both layouts host every ``HomeTab`` and differ only in which of
/// them the bar shows. That keeps `AppRouter.Stack.isTabHosted` and
/// `HomeTab.pushStack` true for both, with nothing registered at runtime.
enum HomeTabLayout: Equatable {
    case standard
    case groupMoney

    init(showsGroupMoney: Bool) {
        self = showsGroupMoney ? .groupMoney : .standard
    }

    /// The tabs the bar shows, left to right.
    var barTabs: [HomeTab] {
        switch self {
        case .standard:   HomeTab.allCases
        case .groupMoney: [.chat, .wallet]
        }
    }

    /// Whether the iOS 26 bar keeps its search tab. Search stays where it is in
    /// both layouts; the legacy bar never had one (its search is a toolbar button).
    var hasSearchTab: Bool { true }

    /// The tab selected on launch. Groups is today's Chat tab, so both layouts
    /// launch on the same tab.
    var initialTab: HomeTab { HomeTab.initial }

    /// The tab a search result opens on: the stack its chats and currencies live on.
    var searchResultTab: HomeTab { .chat }

    /// Whether the shell can bring `tab` forward when the router asks for it.
    /// Every tab, in both layouts: a tab off the bar is still hosted.
    func isReachable(_ tab: HomeTab) -> Bool {
        true
    }

    /// Whether `tab` has a slot on the bar.
    func isOnBar(_ tab: HomeTab) -> Bool {
        barTabs.contains(tab)
    }

    func title(for tab: HomeTab) -> String {
        switch (self, tab) {
        case (.groupMoney, .chat):
            String(localized: "Groups", comment: "Home tab bar label")
        case (.groupMoney, .wallet):
            String(localized: "Money", comment: "Home tab bar label")
        default:
            tab.title
        }
    }

    /// The asset-catalog name of the tab's template glyph. Groups wears the
    /// two-people glyph from the redesign; Money keeps the wallet.
    func iconName(for tab: HomeTab, isSelected: Bool) -> String {
        switch (self, tab) {
        case (.groupMoney, .chat):
            isSelected ? "NavGroupsSelected" : "NavGroups"
        default:
            tab.iconName(isSelected: isSelected)
        }
    }
}

/// Closes a tab drawn over the home shell because the bar has no slot for it,
/// going back to the bar tab it covers. In the environment only while one is.
struct HomeTabClose {
    let action: () -> Void
}

extension EnvironmentValues {
    @Entry var homeTabClose: HomeTabClose? = nil
}
