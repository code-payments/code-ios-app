//
//  HomeTab.swift
//  Flipcash
//

import SwiftUI

/// The tabs of the v2 tab-bar UI, in display order (left → right). The app
/// launches on `.wallet` (wallet-first), mirroring the Android v2 UI.
///
/// Icons are the Figma tab-bar glyphs (`Nav*` template imagesets, from the same
/// vectors as Android's `ic_nav_*`), tinted white at the call site.
enum HomeTab: Int, CaseIterable, Identifiable, Hashable {
    case scan
    case wallet
    case chat
    case tipCard

    var id: Int { rawValue }

    /// The launch tab — wallet-first, per the v2 design.
    static let initial: HomeTab = .wallet

    /// The asset-catalog name of the tab's template glyph. Selected tabs use a
    /// filled glyph and the rest an outline, per the tab bar spec.
    ///
    /// The scanner reads tip cards, so it carries the tip card itself rather
    /// than a viewfinder, and You takes the people-circle the scanner's slot
    /// left free — the glyph it shows when there is no profile photo to draw in
    /// its place (node 10000:111297). You has only the one glyph: selection is
    /// carried by the pill behind it, as it already is for a photo.
    func iconName(isSelected: Bool) -> String {
        switch self {
        case .scan:    return isSelected ? "NavTipCardSelected" : "NavTipCard"
        case .wallet:  return isSelected ? "NavWalletSelected"  : "NavWallet"
        case .chat:    return isSelected ? "NavChatSelected"    : "NavChat"
        case .tipCard: return "NavPeople"
        }
    }

    /// VoiceOver label for the tab's button.
    var accessibilityLabel: String {
        switch self {
        case .scan:    return "Scan"
        case .wallet:  return "Wallet"
        case .chat:    return "Chat"
        case .tipCard: return "You"
        }
    }
}
