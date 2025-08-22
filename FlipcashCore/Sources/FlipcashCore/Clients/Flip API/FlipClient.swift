//
//  FlipClient.swift
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
public class FlipClient: ObservableObject {
    
    public let network: Network
    public let channel: ClientConnection
    
    public let queue: DispatchQueue
    
    internal let accountService: AccountService
    internal let activityService: ActivityService
    internal let iapService: IAPService
    internal let pushService: PushService
    internal let poolService: PoolService
    internal let thirdPartyService: ThirdPartyService
    internal let phoneService: PhoneService
    internal let emailService: EmailService
    internal let profileService: ProfileService
    
    // MARK: - Init -
    
    public init(network: Network) {
        self.network = network
        self.queue   = .main
        self.channel = ClientConnection.appConnection(
            host: network.hostForCore,
            port: network.port
        )
        
        self.accountService    = AccountService(channel: channel, queue: queue)
        self.activityService   = ActivityService(channel: channel, queue: queue)
        self.iapService        = IAPService(channel: channel, queue: queue)
        self.pushService       = PushService(channel: channel, queue: queue)
        self.poolService       = PoolService(channel: channel, queue: queue)
        self.thirdPartyService = ThirdPartyService(channel: channel, queue: queue)
        self.phoneService      = PhoneService(channel: channel, queue: queue)
        self.emailService      = EmailService(channel: channel, queue: queue)
        self.profileService    = ProfileService(channel: channel, queue: queue)
    }
    
    deinit {
        trace(.warning, components: "Deallocating Client")
    }
}

extension FlipClient {
    public static let mock = FlipClient(network: .testNet)
}
