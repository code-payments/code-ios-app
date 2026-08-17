//
//  WalletCardExpansion.swift
//  Flipcash
//

import Observation

/// Whether a token card is currently expanded into the currency info page.
///
/// The expansion is an overlay rather than a push, so the tab bar's usual
/// "hide while a stack is non-empty" rule does not see it; the wallet reports it
/// here instead.
@Observable
final class WalletCardExpansion {
    var isExpanded = false
}
