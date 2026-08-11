//
//  HomeTab.swift
//  Flipcash
//

import SwiftUI

/// The tabs of the v2 tab-bar UI, in display order (left → right). The app
/// launches on `.wallet` (wallet-first), mirroring the Android v2 UI.
///
/// Icons are SF Symbols for now — close stand-ins for the Figma nav glyphs
/// (`ic_nav_scan`/`wallet`/`chat`/`tipcard`); swap for exported assets when the
/// vectors land.
enum HomeTab: Int, CaseIterable, Identifiable, Hashable {
    case scan
    case wallet
    case chat
    case tipCard

    var id: Int { rawValue }

    /// The launch tab — wallet-first, per the v2 design.
    static let initial: HomeTab = .wallet

    var systemImage: String {
        switch self {
        case .scan:    return "viewfinder"
        case .wallet:  return "wallet.pass.fill"
        case .chat:    return "bubble.left.and.bubble.right.fill"
        case .tipCard: return "giftcard.fill"
        }
    }

    /// VoiceOver label for the tab's button.
    var accessibilityLabel: String {
        switch self {
        case .scan:    return "Scan"
        case .wallet:  return "Wallet"
        case .chat:    return "Chat"
        case .tipCard: return "Tip Card"
        }
    }
}
