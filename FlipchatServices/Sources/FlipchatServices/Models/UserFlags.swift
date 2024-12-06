//
//  UserFlags.swift
//  FlipchatServices
//
//  Created by Dima Bart on 2024-12-06.
//

import Foundation

public struct UserFlags: Codable, Hashable, Equatable, Sendable {
    
    public let isStaff: Bool
    public let isRegistered: Bool
    public let startGroupCost: Kin
    public let feeDestination: PublicKey
    
    // MARK: - Init -
    
    public init(isStaff: Bool, isRegistered: Bool, startGroupCost: Kin, feeDestination: PublicKey) {
        self.isStaff = isStaff
        self.isRegistered = isRegistered
        self.startGroupCost = startGroupCost
        self.feeDestination = feeDestination
    }
}

extension UserFlags {
    public static let mock = UserFlags(
        isStaff: false,
        isRegistered: true,
        startGroupCost: 200,
        feeDestination: .mock
    )
}
