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
    }
    
    deinit {
        trace(.warning, components: "Deallocating Client")
    }

    // MARK: - Streaming -

    /// Create a LiveMintDataStreamer for streaming exchange rates and reserve states
    public func createLiveMintDataStreamer(verifiedProtoService: VerifiedProtoService) -> LiveMintDataStreamer {
        LiveMintDataStreamer(
            service: currencyService,
            verifiedProtoService: verifiedProtoService,
            queue: queue
        )
    }
}

extension ClientConnection {
    public static func appConnection(host: String, port: Int) -> ClientConnection {
        .usingTLSBackedByNIOSSL(on: MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount))
        .withErrorDelegate(CodeServiceErrorDelegate())
//        .withKeepalive(
//            .init(interval: .seconds(30), permitWithoutCalls: true)
//        )
//        .withConnectionIdleTimeout(.minutes(5))
//        .withConnectionTimeout(minimum: .minutes(1))
        .connect(host: host, port: port)
    }
}

extension Client {
    public static let mock = Client(network: .testNet)
}
