//
//  Client.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine
import NIO
import GRPC

@MainActor
public class Client: ObservableObject {
    
    public let network: Network
    public let context: Context
    public let channel: ClientConnection
    
    public let queue: DispatchQueue
    
    internal let accountService: AccountInfoService
    internal let transactionService: TransactionService
    internal let messagingService: MessagingService
    internal let currencyService: CurrencyService
    internal let chatService: ChatService
    internal let badgeService: BadgeService
    internal let deviceService: DeviceService
    
    // MARK: - Init -
    
    public init(network: Network, context: Context = .init(), queue: DispatchQueue = .main) {
        self.network = network
        self.context = context
        self.queue   = queue
        self.channel = ClientConnection.appConnection(
            host: network.paymentsHost,
            port: network.port
        )
        
        self.accountService     = AccountInfoService(channel: channel, queue: queue)
        self.transactionService = TransactionService(channel: channel, queue: queue)
        self.messagingService   = MessagingService(channel: channel, queue: queue)
        self.currencyService    = CurrencyService(channel: channel, queue: queue)
        self.chatService        = ChatService(channel: channel, queue: queue)
        self.badgeService       = BadgeService(channel: channel, queue: queue)
        self.deviceService      = DeviceService(channel: channel, queue: queue)
    }
    
    deinit {
        trace(.warning, components: "Deallocating Client")
    }
}

extension Client {
    public static let mock = Client(network: .testNet)
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
