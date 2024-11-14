//
//  TwitterUser.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

public struct TwitterUser: Equatable, Hashable, Codable {
    
    public let username: String
    public let displayName: String
    public let avatarURL: URL
    public let followerCount: Int
    public let tipAddress: PublicKey
    public let verificationStatus: VerificationStatus
    public let costOfFriendship: Fiat
    public let isFriend: Bool
    public let friendChatID: ChatID?
    
    public init(username: String, displayName: String, avatarURL: URL, followerCount: Int, tipAddress: PublicKey, verificationStatus: VerificationStatus, costOfFriendship: Fiat, isFriend: Bool, friendChatID: ChatID?) {
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.followerCount = followerCount
        self.tipAddress = tipAddress
        self.verificationStatus = verificationStatus
        self.costOfFriendship = costOfFriendship
        self.isFriend = isFriend
        self.friendChatID = friendChatID
    }
}

extension TwitterUser {
    public enum VerificationStatus: Int, Equatable, Hashable, Codable {
        case none
        case blue
        case business
        case government
        case unknown = -1
    }
}

extension TwitterUser {
//    init(_ proto: Code_User_V1_TwitterUser) throws {
//        guard
//            let avatarURL = URL(string: proto.profilePicURL),
//            let tipAddress = PublicKey(proto.tipAddress.value)
//        else {
//            throw Error.parseFailed
//        }
//        
//        let cost: Fiat
//        
//        if proto.hasFriendshipCost, let currency = CurrencyCode(currencyCode: proto.friendshipCost.currency) {
//            cost = Fiat(currency: currency, amount: proto.friendshipCost.nativeAmount)
//        } else {
//            cost = Fiat(currency: .usd, amount: 1.00)
//        }
//        
//        self.init(
//            username: proto.username,
//            displayName: proto.name,
//            avatarURL: avatarURL,
//            followerCount: Int(proto.followerCount),
//            tipAddress:  tipAddress,
//            verificationStatus: VerificationStatus(rawValue: proto.verifiedType.rawValue) ?? .unknown,
//            costOfFriendship: cost,
//            isFriend: proto.isFriend,
//            friendChatID: proto.friendChatID.value.isEmpty ? nil : ChatID(data: proto.friendChatID.value)
//        )
//    }
}

extension TwitterUser {
    enum Error: Swift.Error {
        case parseFailed
    }
}
