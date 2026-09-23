//
//  HomeTab.swift
//  Flipcash
//

import SwiftUI

/// The tabs of the v2 tab-bar UI, in display order (left → right). Chat sits
/// second, beside the scanner that feeds it. Declaration order is the bar's
/// order, not the launch tab; see ``initial`` and ``postOnboarding``. Matches Android's
/// `NavBarButton.tabs`.
///
/// Icons are the Figma tab-bar glyphs (`Nav*` template imagesets, from the same
/// vectors as Android's `ic_nav_*`), tinted white at the call site.
enum HomeTab: Int, CaseIterable, Identifiable, Hashable {
    case scan
    case chat
    case wallet
    case tipCard

    var id: Int { rawValue }

    /// The tab selected on cold launch and after signing in to an existing
    /// account.
    static let initial: HomeTab = .chat

    /// The tab selected when onboarding finishes creating a new account.
    static let postOnboarding: HomeTab = .wallet

    /// The asset-catalog name of the tab's template glyph. Selected tabs use a
    /// filled glyph and the rest an outline, per the tab bar spec.
    ///
    /// The scanner reads tip cards, so it carries the tip card itself rather
    /// than a viewfinder, and You takes the people-circle the scanner's slot
    /// left free — the glyph it shows when there is no profile photo to draw in
    /// its place (node 10000:111297).
    ///
    /// That fallback's filled weight comes from Material Icons' `account_circle`
    /// rather than from the design file, which draws the You tab only as an
    /// outline. It is the same glyph solid, and Android's people circle takes its
    /// selected weight from the same place, so the two bars fill alike.
    func iconName(isSelected: Bool) -> String {
        switch self {
        case .scan:    return isSelected ? "NavTipCardSelected" : "NavTipCard"
        case .chat:    return isSelected ? "NavChatSelected"    : "NavChat"
        case .wallet:  return isSelected ? "NavWalletSelected"  : "NavWallet"
        case .tipCard: return isSelected ? "NavPeopleSelected"  : "NavPeople"
        }
    }

    /// VoiceOver label for the tab's button.
    var accessibilityLabel: String {
        switch self {
        case .scan:    return "Scan"
        case .chat:    return "Chat"
        case .wallet:  return "Wallet"
        case .tipCard: return "You"
        }
    }
}
