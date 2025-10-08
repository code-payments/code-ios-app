//
//  MindDescription.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-10-07.
//

import Foundation

public struct MintDescription: Equatable, Hashable, Codable, Sendable {
    public let ticker: String
    public let mint: PublicKey
    
    public init(ticker: String, mint: PublicKey) {
        self.ticker = ticker
        self.mint = mint
    }
}

extension MintDescription: Identifiable {
    public var id: String {
        mint.base58
    }
}

extension MintDescription {
    public static let usdc: MintDescription = .init(
        ticker: "USDC",
        mint: PublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")!
    )
}
