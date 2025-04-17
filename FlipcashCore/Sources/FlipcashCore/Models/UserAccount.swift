//
//  UserAccount.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-16.
//

import Foundation

public struct UserAccount: Hashable, Equatable, Sendable, Codable {
    
    public let userID: UserID
    public let keyAccount: KeyAccount
    
    public init(userID: UserID, keyAccount: KeyAccount) {
        self.userID = userID
        self.keyAccount = keyAccount
    }
}
