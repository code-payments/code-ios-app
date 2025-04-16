//
//  User.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

public struct User: Equatable, Sendable {
    
    public let id: ID

    // Not serialized
    
    public let betaFlagsAllowed: Bool
    public let enableBuyModule: Bool
    public let eligibleAirdrops: Set<AirdropType>
    
    public init(id: ID, betaFlagsAllowed: Bool, enableBuyModule: Bool, eligibleAirdrops: [AirdropType]) {
        self.id = id
        self.betaFlagsAllowed = betaFlagsAllowed
        self.enableBuyModule = enableBuyModule
        self.eligibleAirdrops = Set(eligibleAirdrops)
    }
}

// MARK: - Proto -

//extension User {
//    init(codeUser: Code_User_V1_User, containerID: Code_Common_V1_DataContainerId, betaFlagsAllowed: Bool, enableBuyModule: Bool, eligibleAirdrops: [Code_Transaction_V2_AirdropType]) {
//        self.init(
//            id: .init(data: codeUser.id.value),
//            containerID: .init(data: containerID.value),
//            phone: Phone(codeUser.view.phoneNumber),
//            betaFlagsAllowed: betaFlagsAllowed,
//            enableBuyModule: enableBuyModule,
//            eligibleAirdrops: eligibleAirdrops.compactMap { AirdropType(rawValue: $0.rawValue) }
//        )
//    }
//}

// MARK: - Codable -

extension User: Codable {
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let id = try container.decode(ID.self, forKey: .id)
        
        self.init(
            id: id,
            betaFlagsAllowed: false,
            enableBuyModule: false,
            eligibleAirdrops: []
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
        enableBuyModule: true,
        eligibleAirdrops: []
    )
}
