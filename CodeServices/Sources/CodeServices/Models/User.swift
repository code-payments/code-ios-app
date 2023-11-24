//
//  User.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct User: Equatable {
    
    public let id: ID
    public let containerID: ID
    public let phone: Phone?

    // Not serialized
    
    public let betaFlagsAllowed: Bool
    public let eligibleAirdrops: Set<AirdropType>
    
    public init(id: ID, containerID: ID, phone: Phone?, betaFlagsAllowed: Bool, eligibleAirdrops: [AirdropType]) {
        self.id = id
        self.containerID = containerID
        self.phone = phone
        self.betaFlagsAllowed = betaFlagsAllowed
        self.eligibleAirdrops = Set(eligibleAirdrops)
    }
}

// MARK: - Mock -

public extension User {
    private static func id() -> ID {
        .init(data: Data([0xFF, 0xFF, 0xFF, 0xFF]))
    }
              
    static let mock = User(
        id: id(),
        containerID: id(),
        phone: .mock,
        betaFlagsAllowed: true,
        eligibleAirdrops: []
    )
}
