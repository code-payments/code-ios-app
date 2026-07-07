//
//  DepositMethod.swift
//  Flipcash
//

import Foundation

/// A way to bring USDF into the account. All three ultimately land USDF:
/// Coinbase & Other Wallet deliver USDC (swept to USDF); Phantom signs a
/// USDC→USDF swap into the deposit address.
nonisolated enum DepositMethod: Hashable, Sendable, CaseIterable, Identifiable {
    case coinbase
    case phantom
    case otherWallet

    var id: Self { self }
}
