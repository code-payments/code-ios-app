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
    internal let blobService: BlobService
    internal let blobUploader: BlobUploader
    internal let settingsService: SettingsService
    internal let moderationService: ModerationService
    internal let contactListService: ContactListService
    internal let resolverService: ResolverService
    internal let chatService: ChatService
    internal let chatMessagingService: ChatMessagingService

    /// The single per-user event stream. Started on login, stopped on logout.
    public let eventStreamer: EventStreamer

    // MARK: - Init -

    public init(network: Network) throws {
        self.network = network

        let transport = try GRPCTransport.makeTransportServices(
            host: network.hostForCore,
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
                logger.error("Flip connection loop terminated", metadata: ["error": "\(error)"])
            }
        }

        self.accountService     = AccountService(client: client)
        self.activityService    = ActivityService(client: client)
        self.pushService        = PushService(client: client)
        self.thirdPartyService  = ThirdPartyService(client: client)
        self.phoneService       = PhoneService(client: client)
        self.emailService       = EmailService(client: client)
        self.profileService     = ProfileService(client: client)

        let blobService         = BlobService(client: client)
        self.blobService        = blobService
        self.blobUploader       = BlobUploader(
            reserving: blobService,
            transport: URLSessionBlobUploader()
        )

        self.settingsService    = SettingsService(client: client)
        self.moderationService  = ModerationService(client: client)
        self.contactListService = ContactListService(client: client)
        self.resolverService    = ResolverService(client: client)
        self.chatService        = ChatService(client: client)
        self.chatMessagingService = ChatMessagingService(client: client)
        self.eventStreamer      = EventStreamer(service: EventStreamingService(client: client))
    }

    deinit {
        grpcClient.beginGracefulShutdown()
        connectionTask.cancel()
    }

    // MARK: - Channel Lifecycle -

    /// Pre-warm the connection by issuing a lightweight unauthenticated call.
    /// The response is irrelevant — we only need the transport to start connecting.
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

extension FlipClient {
    public static let mock = try! FlipClient(network: .mainNet)
}
