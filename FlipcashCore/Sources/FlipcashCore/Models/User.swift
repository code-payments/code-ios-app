//
//  User.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct User: Equatable, Sendable {
    
    public let id: ID

    // Not serialized
    
    public let betaFlagsAllowed: Bool
    public let enableBuyModule: Bool

    public init(id: ID, betaFlagsAllowed: Bool, enableBuyModule: Bool) {
        self.id = id
        self.betaFlagsAllowed = betaFlagsAllowed
        self.enableBuyModule = enableBuyModule
    }
}

// MARK: - Codable -

extension User: Codable {
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let id = try container.decode(ID.self, forKey: .id)
        
        self.init(
            id: id,
            betaFlagsAllowed: false,
            enableBuyModule: false
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
    }
}

extension User {
    enum CodingKeys: String, CodingKey {
        case id
    }
}

// MARK: - Mock -

public extension User {
    static let mock = User(
        id: .mock,
        betaFlagsAllowed: true,
        enableBuyModule: true
    )
}
