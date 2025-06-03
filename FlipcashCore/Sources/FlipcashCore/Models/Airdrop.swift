//
//  Airdrop.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-10.
//

import Foundation
import FlipcashAPI

public struct Airdrop: Sendable {
    public let type: AirdropType
    public let date: Date
    public let exchangedFiat: ExchangedFiat
    
    public init(type: AirdropType, date: Date, exchangedFiat: ExchangedFiat) {
        self.type = type
        self.date = date
        self.exchangedFiat = exchangedFiat
    }
}

// MARK: - Errors -

extension AirdropType {
    public enum Error: Swift.Error {
        case unsupportedAirdropType
    }
}

// MARK: - Type -

public enum AirdropType: Int, Codable, Equatable, Sendable {
    case unknown
    case onboardingBonus
    case welcomeBonus
}

// MARK: - Proto -

extension AirdropType {
    
    init(_ grpcType: Code_Transaction_V2_AirdropType) throws {
        switch grpcType {
        case .unknown:
            self = .unknown
        case .onboardingBonus:
            self = .onboardingBonus
        case .welcomeBonus:
            self = .welcomeBonus
        default:
            throw Error.unsupportedAirdropType
        }
    }
    
    var grpcType: Code_Transaction_V2_AirdropType {
        switch self {
        case .unknown:
            return .unknown
        case .onboardingBonus:
            return .onboardingBonus
        case .welcomeBonus:
            return .welcomeBonus
        }
    }
}
