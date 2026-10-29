//
//  HomeTab.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The tabs of the v2 tab-bar UI, in display order (left → right). Chat sits
/// second, beside the scanner that feeds it. Declaration order is the bar's
/// order, not the launch tab; see ``initial`` and ``postOnboarding``. Matches Android's
/// `NavBarButton.tabs`.
///
/// Icons are Central glyphs (``icon(isSelected:)``), tinted at the call site.
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

    /// The tab's Central glyph: filled when selected, outlined otherwise, per the tab bar spec.
    func icon(isSelected: Bool) -> Icon {
        switch self {
        case .scan:    return isSelected ? .kikCodeFilled      : .kikCode
        case .chat:    return isSelected ? .chatBubblesFilled  : .chatBubbles
        case .wallet:  return isSelected ? .wallet5Filled      : .wallet5
        case .tipCard: return isSelected ? .peopleCircleFilled : .peopleCircle
        }
    }

    /// The label under the tab's icon, which is also its VoiceOver label
    /// (node 10642:1325).
    var title: String {
        switch self {
        case .scan:    return String(localized: "Scan", comment: "Home tab bar label")
        case .chat:    return String(localized: "Chat", comment: "Home tab bar label")
        case .wallet:  return String(localized: "Money", comment: "Home tab bar label")
        case .tipCard: return String(localized: "You", comment: "Home tab bar label")
        }
    }
}
