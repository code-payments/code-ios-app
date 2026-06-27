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

    private var grpcClient: GRPCClient<AppTransport>

    /// The long-running connection loop. Must be retained for the client's
    /// lifetime — dropping this task makes the client inert and every RPC hangs.
    private var connectionTask: Task<Void, Never>

    /// Guards against overlapping `rebuildTransport()` calls — the event stream
    /// can request a rebuild repeatedly while it's already in flight.
    private var isRebuildingTransport = false

    internal private(set) var accountService: AccountService
    internal private(set) var activityService: ActivityService
    internal private(set) var pushService: PushService
    internal private(set) var thirdPartyService: ThirdPartyService
    internal private(set) var phoneService: PhoneService
    internal private(set) var emailService: EmailService
    internal private(set) var profileService: ProfileService
    internal private(set) var settingsService: SettingsService
    internal private(set) var moderationService: ModerationService
    internal private(set) var contactListService: ContactListService
    internal private(set) var resolverService: ResolverService
    internal private(set) var chatService: ChatService
    internal private(set) var chatMessagingService: ChatMessagingService

    /// The single per-user event stream. Started on login, stopped on logout.
    /// Retained across a transport rebuild — only its underlying service is
    /// re-pointed (`adoptRebuiltService`) so consumers keep their reference.
    public let eventStreamer: EventStreamer

    // MARK: - Init -

    public init(network: Network) throws {
        self.network = network

        let client = try Self.makeClient(network: network)
        self.grpcClient = client
        self.connectionTask = Self.runConnections(client)

        self.accountService     = AccountService(client: client)
        self.activityService    = ActivityService(client: client)
        self.pushService        = PushService(client: client)
        self.thirdPartyService  = ThirdPartyService(client: client)
        self.phoneService       = PhoneService(client: client)
        self.emailService       = EmailService(client: client)
        self.profileService     = ProfileService(client: client)
        self.settingsService    = SettingsService(client: client)
        self.moderationService  = ModerationService(client: client)
        self.contactListService = ContactListService(client: client)
        self.resolverService    = ResolverService(client: client)
        self.chatService        = ChatService(client: client)
        self.chatMessagingService = ChatMessagingService(client: client)
        self.eventStreamer      = EventStreamer(service: EventStreamingService(client: client))

        // The event stream is the Flip channel's liveness probe. When it can't
        // recover after repeated reopens despite the transport reporting itself
        // connected (the "wedged-ready" failure mode), it asks us to rebuild the
        // whole transport — the only recovery grpc-swift's own machinery can't
        // perform for a connection that never closes.
        let streamer = eventStreamer
        Task { await streamer.setOnWedged { [weak self] in
            Task { @MainActor in self?.rebuildTransport() }
        } }
    }

    deinit {
        grpcClient.beginGracefulShutdown()
        connectionTask.cancel()
    }

    // MARK: - Transport Lifecycle -

    private static func makeClient(network: Network) throws -> GRPCClient<AppTransport> {
        let transport = try GRPCTransport.makeTransportServices(
            host: network.hostForCore,
            port: network.port
        )
        return GRPCClient(transport: transport, interceptors: [UserAgentClientInterceptor()])
    }

    private static func runConnections(_ client: GRPCClient<AppTransport>) -> Task<Void, Never> {
        Task {
            do {
                try await client.runConnections()
            } catch {
                // Only reachable on a fatal transport error (graceful shutdown
                // returns normally) — every RPC after this point will fail.
                logger.error("Flip connection loop terminated", metadata: ["error": "\(error)"])
            }
        }
    }

    /// Tear down the current transport and stand up a fresh one, re-pointing
    /// every service at the new client. Triggered by `EventStreamer` when the
    /// connection is wedged in a ready-but-dead state that no stream-level retry
    /// can recover. Idempotent while a rebuild is in flight.
    public func rebuildTransport() {
        guard !isRebuildingTransport else { return }
        isRebuildingTransport = true
        logger.warning("Rebuilding Flip transport — connection wedged while reporting ready")

        connectionTask.cancel()
        grpcClient.beginGracefulShutdown()

        let client: GRPCClient<AppTransport>
        do {
            client = try Self.makeClient(network: network)
        } catch {
            logger.error("Failed to rebuild Flip transport", metadata: ["error": "\(error)"])
            isRebuildingTransport = false
            return
        }

        grpcClient = client
        connectionTask = Self.runConnections(client)

        accountService     = AccountService(client: client)
        activityService    = ActivityService(client: client)
        pushService        = PushService(client: client)
        thirdPartyService  = ThirdPartyService(client: client)
        phoneService       = PhoneService(client: client)
        emailService       = EmailService(client: client)
        profileService     = ProfileService(client: client)
        settingsService    = SettingsService(client: client)
        moderationService  = ModerationService(client: client)
        contactListService = ContactListService(client: client)
        resolverService    = ResolverService(client: client)
        chatService        = ChatService(client: client)
        chatMessagingService = ChatMessagingService(client: client)

        let newEventService = EventStreamingService(client: client)
        let streamer = eventStreamer
        Task {
            await streamer.adoptRebuiltService(newEventService)
            await MainActor.run { self.isRebuildingTransport = false }
        }
    }

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
