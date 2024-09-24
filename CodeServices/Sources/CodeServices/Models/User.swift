//
//  User.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public struct User: Equatable, Sendable {
    
    public let id: ID
    public let containerID: ID
    public let phone: Phone?

    // Not serialized
    
    public let betaFlagsAllowed: Bool
    public let enableBuyModule: Bool
    public let eligibleAirdrops: Set<AirdropType>
    
    public init(id: ID, containerID: ID, phone: Phone?, betaFlagsAllowed: Bool, enableBuyModule: Bool, eligibleAirdrops: [AirdropType]) {
        self.id = id
        self.containerID = containerID
        self.phone = phone
        self.betaFlagsAllowed = betaFlagsAllowed
        self.enableBuyModule = enableBuyModule
        self.eligibleAirdrops = Set(eligibleAirdrops)
    }
}

// MARK: - Proto -

extension User {
    init(codeUser: Code_User_V1_User, containerID: Code_Common_V1_DataContainerId, betaFlagsAllowed: Bool, enableBuyModule: Bool, eligibleAirdrops: [Code_Transaction_V2_AirdropType]) {
        self.init(
            id: .init(data: codeUser.id.value),
            containerID: .init(data: containerID.value),
            phone: Phone(codeUser.view.phoneNumber),
            betaFlagsAllowed: betaFlagsAllowed,
            enableBuyModule: enableBuyModule,
            eligibleAirdrops: eligibleAirdrops.compactMap { AirdropType(rawValue: $0.rawValue) }
        )
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
        enableBuyModule: true,
        eligibleAirdrops: []
    )
}
