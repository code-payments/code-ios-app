//
//  WalletCardNamespace.swift
//  Flipcash
//

import SwiftUI

private struct WalletCardNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The wallet card stack's matched-transition namespace, handed down through
    /// the balance `NavigationStack` so a pushed currency-info screen can zoom out
    /// of the tapped token card. `nil` anywhere the wallet is not the source, in
    /// which case the screen pushes without a zoom.
    var walletCardNamespace: Namespace.ID? {
        get { self[WalletCardNamespaceKey.self] }
        set { self[WalletCardNamespaceKey.self] = newValue }
    }
}
