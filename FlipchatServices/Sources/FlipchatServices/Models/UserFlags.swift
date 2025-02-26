//
//  UserFlags.swift
//  FlipchatServices
//
//  Created by Dima Bart on 2024-12-06.
//

import Foundation
import FlipchatAPI

public struct UserFlags: Codable, Hashable, Equatable, Sendable {
    
    /// Is this user associated with a Flipchat staff member?
    public let isStaff: Bool
    
    /// The fee payment amount for starting a new group
    public let startGroupCost: Kin
    
    /// The destination account where fees should be paid to
    public let feeDestination: PublicKey
    
    // Is this a fully registered account using IAP for account creation?
    public let isRegistered: Bool
    
    // Can this user call NotifyIsTyping at all?
    public let canSendTypingNotifications: Bool
    
    // Can this user call NotifyIsTyping in chats where they are a listener?
    public let canSendListenerTypingNotifications: Bool
    
    // Interval (in seconds) between calling NotifyIsTyping
    public let typingUpdateInterval: Int
    
    // Client-side timeout (in seconds) for when they haven't seen an IsTyping event from a user.
    // After this timeout has elapsed, client should assume the user has stopped typing.
    public let typingTimeout: Int
    
    // MARK: - Init -
    
    init(isStaff: Bool, startGroupCost: Kin, feeDestination: PublicKey, isRegistered: Bool, canSendTypingNotifications: Bool, canSendListenerTypingNotifications: Bool, typingUpdateInterval: Int, typingTimeout: Int) {
        self.isStaff = isStaff
        self.startGroupCost = startGroupCost
        self.feeDestination = feeDestination
        self.isRegistered = isRegistered
        self.canSendTypingNotifications = canSendTypingNotifications
        self.canSendListenerTypingNotifications = canSendListenerTypingNotifications
        self.typingUpdateInterval = typingUpdateInterval
        self.typingTimeout = typingTimeout
    }
}

extension UserFlags {
    public static let mock = UserFlags(
        isStaff: false,
        startGroupCost: 200,
        feeDestination: .mock,
        isRegistered: true,
        canSendTypingNotifications: true,
        canSendListenerTypingNotifications: true,
        typingUpdateInterval: 5,
        typingTimeout: 60
    )
}

extension UserFlags {
    init?(_ proto: Flipchat_Account_V1_UserFlags) {
        guard
            let destination = PublicKey(proto.feeDestination.value)
        else {
            return nil
        }
        
        self.init(
            isStaff: proto.isStaff,
            startGroupCost: Kin(quarks: proto.startGroupFee.quarks),
            feeDestination: destination,
            isRegistered: proto.isRegisteredAccount,
            canSendTypingNotifications: proto.canSendIsTypingNotifications,
            canSendListenerTypingNotifications: proto.canSendIsTypingNotificationsAsListener,
            typingUpdateInterval: Int(proto.isTypingNotificationInterval.seconds),
            typingTimeout: Int(proto.isTypingNotificationTimeout.seconds)
        )
    }
}
