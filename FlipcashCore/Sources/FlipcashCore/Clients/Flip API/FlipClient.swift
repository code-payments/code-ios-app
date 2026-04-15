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

private let logger = Logger(label: "flipcash.flip-client")

@MainActor
public class FlipClient: ObservableObject {
    
    public let network: Network
    public let channel: ClientConnection
    
    public let queue: DispatchQueue
    
    internal let accountService: AccountService
    internal let activityService: ActivityService
    internal let iapService: IAPService
    internal let pushService: PushService
    internal let thirdPartyService: ThirdPartyService
    internal let phoneService: PhoneService
    internal let emailService: EmailService
    internal let profileService: ProfileService
    internal let settingsService: SettingsService

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
        self.thirdPartyService = ThirdPartyService(channel: channel, queue: queue)
        self.phoneService      = PhoneService(channel: channel, queue: queue)
        self.emailService      = EmailService(channel: channel, queue: queue)
        self.profileService    = ProfileService(channel: channel, queue: queue)
        self.settingsService   = SettingsService(channel: channel, queue: queue)

        self.channel.connectivity.delegate = self
    }
    
    deinit {
        logger.debug("Deallocating FlipClient")
    }

    // MARK: - Channel Lifecycle -

    /// Pre-warm the gRPC channel by triggering a lightweight unauthenticated
    /// call. Forces TCP+TLS reconnection if the underlying socket died during
    /// backgrounding. Without this, the first call on the cold channel after
    /// foregrounding tends to surface as a `GRPCStatus.Code.internalError`
    /// with an empty message, which the caller can't distinguish from a real
    /// server error.
    /// The response is irrelevant — we only need the channel to start connecting.
    public func warmUpChannel() {
        accountService.fetchUnauthenticatedUserFlags { result in
            switch result {
            case .success:
                logger.info("Flip channel warm-up succeeded")
            case .failure:
                logger.warning("Flip channel warm-up completed (channel reconnecting)")
            }
        }
    }
}

// MARK: - ConnectivityStateDelegate -

extension FlipClient: ConnectivityStateDelegate {
    public nonisolated func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
        logger.info("Flip channel: \(oldState) → \(newState)")
    }

    public nonisolated func connectionStartedQuiescing() {
        logger.notice("Flip channel quiescing")
    }
}

extension FlipClient {
    public static let mock = FlipClient(network: .testNet)
}
