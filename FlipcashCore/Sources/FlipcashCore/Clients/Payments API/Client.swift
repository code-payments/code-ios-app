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

private let logger = Logger(label: "flipcash.payment-client")

@MainActor
public class Client: ObservableObject {
    
    public let network: Network
    public let channel: ClientConnection
    
    public let queue: DispatchQueue
    
    internal let accountService: AccountInfoService
    internal let transactionService: TransactionService
    internal let currencyService: CurrencyService
    internal let messagingService: MessagingService

    // MARK: - Init -

    public init(network: Network) {
        self.network = network
        self.queue   = .main
        self.channel = ClientConnection.appConnection(
            host: network.hostForPayments,
            port: network.port
        )

        self.accountService     = AccountInfoService(channel: channel, queue: queue)
        self.transactionService = TransactionService(channel: channel, queue: queue)
        self.currencyService    = CurrencyService(channel: channel, queue: queue)
        self.messagingService   = MessagingService(channel: channel, queue: queue)

        self.channel.connectivity.delegate = self
    }
    
    deinit {
        logger.debug("Deallocating Client")
    }

    // MARK: - Channel Lifecycle -

    /// Pre-warm the gRPC channel by triggering a lightweight unary call.
    /// Forces TCP+TLS reconnection if the underlying socket died during
    /// backgrounding (common: errno 57 / unavailable 14).
    /// The response is irrelevant — we only need the channel to start connecting.
    public func warmUpChannel() {
        currencyService.fetchMint(mint: .usdf) { result in
            switch result {
            case .success:
                logger.info("Channel warm-up succeeded")
            case .failure:
                logger.warning("Channel warm-up completed (channel reconnecting)")
            }
        }
    }

    // MARK: - Streaming -

    /// Create a LiveMintDataStreamer for streaming exchange rates and reserve states
    public func createLiveMintDataStreamer(verifiedProtoService: VerifiedProtoService) -> LiveMintDataStreamer {
        LiveMintDataStreamer(
            service: currencyService,
            verifiedProtoService: verifiedProtoService
        )
    }
}

extension ClientConnection {
    public static func appConnection(host: String, port: Int) -> ClientConnection {
        .usingTLSBackedByNIOSSL(on: MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount))
        .withErrorDelegate(CodeServiceErrorDelegate())
        .withKeepalive(.init(interval: .seconds(30), timeout: .seconds(10), permitWithoutCalls: true))
        .withConnectionIdleTimeout(.minutes(5))
        .connect(host: host, port: port)
    }
}

// MARK: - ConnectivityStateDelegate -

extension Client: ConnectivityStateDelegate {
    public nonisolated func connectivityStateDidChange(from oldState: ConnectivityState, to newState: ConnectivityState) {
        logger.info("Payment channel: \(oldState) → \(newState)")
    }

    public nonisolated func connectionStartedQuiescing() {
        logger.notice("Payment channel quiescing")
    }
}

extension Client {
    public static let mock = Client(network: .testNet)
}
