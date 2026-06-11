//
//  Client.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import GRPCCore

private let logger = Logger(label: "flipcash.payment-client")

@MainActor
public class Client: ObservableObject {

    public let network: Network

    private let grpcClient: GRPCClient<AppTransport>

    /// The long-running connection loop. gRPC v2 does nothing until
    /// `runConnections()` is running, and it must be retained for the client's
    /// lifetime — dropping this task makes the client inert and every RPC hangs.
    private let connectionTask: Task<Void, Never>

    internal let accountService: AccountInfoService
    internal let transactionService: TransactionService
    internal let currencyService: CurrencyService
    internal let messagingService: MessagingService

    // MARK: - Init -

    public init(network: Network) throws {
        self.network = network

        let transport = try GRPCTransport.makeTransportServices(
            host: network.hostForPayments,
            port: network.port
        )
        let client = GRPCClient(transport: transport, interceptors: [UserAgentClientInterceptor()])
        self.grpcClient = client
        self.connectionTask = Task {
            do {
                try await client.runConnections()
            } catch {
                // Only reachable on a fatal transport error (graceful shutdown
                // returns normally) — every RPC after this point will fail.
                logger.error("Payment connection loop terminated", metadata: ["error": "\(error)"])
            }
        }

        self.accountService     = AccountInfoService(client: client)
        self.transactionService = TransactionService(client: client)
        self.currencyService    = CurrencyService(client: client)
        self.messagingService   = MessagingService(client: client)
    }

    deinit {
        // Graceful shutdown drains in-flight streams before the connection closes;
        // cancelling the task ends the connection loop.
        grpcClient.beginGracefulShutdown()
        connectionTask.cancel()
    }

    // MARK: - Channel Lifecycle -

    /// Pre-warm the connection by issuing a lightweight unary call. The response
    /// is irrelevant — we only need the transport to start connecting.
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

extension Client {
    public static let mock = try! Client(network: .mainNet)
}
