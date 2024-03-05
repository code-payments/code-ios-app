//
//  Client.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine
import NIO
import GRPC

public class Client {
    
    public let network: Network
    public let context: Context
    public let channel: ClientConnection
    
    public let queue: DispatchQueue
    
    internal let accountService: AccountService
    internal let transactionService: TransactionService
    internal let messagingService: MessagingService
    internal let phoneService: PhoneService
    internal let inviteService: InviteService
    internal let currencyService: CurrencyService
    internal let identityService: IdentityService
    internal let contactsService: ContactsService
    internal let pushService: PushService
    internal let chatService: ChatService
    internal let badgeService: BadgeService
    internal let deviceService: DeviceService
    
    // MARK: - Init -
    
    public init(network: Network, context: Context = .init(), queue: DispatchQueue = .main) {
        self.network = network
        self.context = context
        self.queue   = queue
        self.channel = ClientConnection.appConnection(
            host: network.host,
            port: network.port
        )
        
        self.accountService     = AccountService(channel: channel, queue: queue)
        self.transactionService = TransactionService(channel: channel, queue: queue)
        self.messagingService   = MessagingService(channel: channel, queue: queue)
        self.phoneService       = PhoneService(channel: channel, queue: queue)
        self.inviteService      = InviteService(channel: channel, queue: queue)
        self.currencyService    = CurrencyService(channel: channel, queue: queue)
        self.identityService    = IdentityService(channel: channel, queue: queue)
        self.contactsService    = ContactsService(channel: channel, queue: queue)
        self.pushService        = PushService(channel: channel, queue: queue)
        self.chatService        = ChatService(channel: channel, queue: queue)
        self.badgeService       = BadgeService(channel: channel, queue: queue)
        self.deviceService      = DeviceService(channel: channel, queue: queue)
    }
    
    deinit {
        trace(.warning, components: "Deallocating Client")
    }
}

// MARK: - KRE -

public enum KRE {
    public static let index: Int = 268
}

// MARK: - Context -

extension Client {
    public struct Context {
        
        /// "Kin Rewards Engine" index representing an app ID
        /// obtained through a Kin portal outside the scope
        /// of this application
        public var kreIndex: Int?
        
        public init(kreIndex: Int? = nil) {
            self.kreIndex = kreIndex
        }
    }
}

// MARK: - Error -

public enum ClientError: Error {
    case pollLimitReached
}

public enum ErrorGeneric: Error {
    case unknown
}
