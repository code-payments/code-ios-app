//
//  FlipClient.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import GRPCCore

private let logger = Logger(label: "flipcash.flip-client")

@MainActor
public class FlipClient: ObservableObject {

    public let network: Network

    private let grpcClient: GRPCClient<AppTransport>

    /// The long-running connection loop. Must be retained for the client's
    /// lifetime — dropping this task makes the client inert and every RPC hangs.
    private let connectionTask: Task<Void, Never>

    internal let accountService: AccountService
    internal let activityService: ActivityService
    internal let pushService: PushService
    internal let thirdPartyService: ThirdPartyService
    internal let phoneService: PhoneService
    internal let emailService: EmailService
    internal let profileService: ProfileService
    internal let settingsService: SettingsService
    internal let moderationService: ModerationService

    // MARK: - Init -

    public init(network: Network) throws {
        self.network = network

        let transport = try GRPCTransport.makeTransportServices(
            host: network.hostForCore,
            port: network.port
        )
        let client = GRPCClient(transport: transport, interceptors: [UserAgentClientInterceptor()])
        self.grpcClient = client
        self.connectionTask = Task { try? await client.runConnections() }

        self.accountService    = AccountService(client: client)
        self.activityService   = ActivityService(client: client)
        self.pushService       = PushService(client: client)
        self.thirdPartyService = ThirdPartyService(client: client)
        self.phoneService      = PhoneService(client: client)
        self.emailService      = EmailService(client: client)
        self.profileService    = ProfileService(client: client)
        self.settingsService   = SettingsService(client: client)
        self.moderationService = ModerationService(client: client)
    }

    deinit {
        grpcClient.beginGracefulShutdown()
        connectionTask.cancel()
    }

    // MARK: - Channel Lifecycle -

    /// Pre-warm the connection by issuing a lightweight unauthenticated call.
    /// The response is irrelevant — we only need the transport to start connecting.
    public func warmUpChannel() {
        accountService.fetchUnauthenticatedUserFlags { _ in }
    }
}

extension FlipClient {
    public static let mock = try! FlipClient(network: .testNet)
}
