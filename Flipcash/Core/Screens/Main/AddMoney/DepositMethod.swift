//
//  DepositMethod.swift
//  Flipcash
//

import Foundation

/// A way to bring USDF into the account.
nonisolated enum DepositMethod: Hashable, Sendable, CaseIterable, Identifiable {
    case coinbase
    case phantom
    case otherWallet

    var id: Self { self }
}
