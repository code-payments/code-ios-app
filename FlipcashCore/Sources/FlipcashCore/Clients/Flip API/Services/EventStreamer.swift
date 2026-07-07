//
//  EventStreamer.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.event-streamer")

/// The connection state of the event stream. The streamer reports these facts;
/// it's the consumer's job to decide what they mean — e.g. refetch the window a
/// drop left, or drive a "reconnecting" indicator.
public enum EventStreamConnectionState: Sendable {
    /// A connection proved it's delivering (its first ping arrived). Emitted once
    /// per connection, so a reconnect produces a fresh `.live`.
    case live
    /// The stream was torn down — a drop being reconnected, or a stop.
    case disconnected
}

/// Owns the single per-user bidirectional event stream (`event.v1 StreamEvents`)
/// and decodes conversation updates into `ConversationStreamEvent`s consumed via `events`. The
/// server enforces one stream per user, so exactly one instance must exist per
/// session; opening a second silently evicts the first. The owner must call
/// `stop()` on logout so a stale stream doesn't evict the next session's.
public actor EventStreamer {

    public typealias StreamReference = BidirectionalGRPCStream<
        Flipcash_Event_V1_StreamEventsRequest,
        Flipcash_Event_V1_StreamEventsResponse
    >

    /// Decoded conversation updates. Consume with `for await event in streamer.events`.
    public nonisolated let events: AsyncStream<ConversationStreamEvent>
    private let continuation: AsyncStream<ConversationStreamEvent>.Continuation

    /// The stream's connection state over time. The event stream itself carries no cursor, so a
    /// consumer treats the first `.live` as the initial connection and, on each `.live` after that
    /// (a reconnect), reconciles the missed window from its own durable cursor (chat catch-up runs
    /// `GetDelta`). Consume with `for await state in streamer.connectionState`.
    public nonisolated let connectionState: AsyncStream<EventStreamConnectionState>
    private let connectionStateContinuation: AsyncStream<EventStreamConnectionState>.Continuation

    private let service: EventStreamingService
    private var owner: KeyPair?

    private var streamReference: StreamReference?
    private var isStreaming = false
    private var isReconnecting = false
    private var backoff = ReconnectBackoff()
    private var reconnectTask: Task<Void, Never>?
    private var pingTimeoutTask: Task<Void, Never>?
    private var pingTracker = PingTracker()
    /// Bumped on every `openStream()`; gRPC callbacks capture the value at open
    /// time so a torn-down stream's late status can't tear down its replacement.
    private var streamGeneration: UInt = 0
    /// Whether the current connection has been reported `.live`. Dedupes the
    /// per-ping liveness proof into a single `.live` per connection, and gates
    /// the matching `.disconnected` on teardown.
    private var isConnectionLive = false

    init(service: EventStreamingService) {
        self.service = service
        let (stream, continuation) = AsyncStream<ConversationStreamEvent>.makeStream()
        self.events = stream
        self.continuation = continuation
        let (connectionState, connectionStateContinuation) = AsyncStream<EventStreamConnectionState>.makeStream()
        self.connectionState = connectionState
        self.connectionStateContinuation = connectionStateContinuation
    }

    deinit {
        pingTimeoutTask?.cancel()
        reconnectTask?.cancel()
        streamReference?.cancel()
        continuation.finish()
        connectionStateContinuation.finish()
    }

    // MARK: - Public API

    /// Open the event stream for the signed-in owner. Idempotent.
    public func start(owner: KeyPair) {
        guard !isStreaming else { return }
        self.owner = owner
        isStreaming = true
        openStream()
    }

    /// Re-open the stream if it died (e.g. after returning from background).
    public func ensureConnected() {
        guard isStreaming else { return }
        if isLikelyHealthy, !isReconnecting { return }
        logger.warning("Event stream not connected, forcing reconnect")
        resetAndTeardown()
        openStream()
    }

    /// A live stream that has received a ping recently. Wall-clock based via
    /// `PingTracker`, so it stays accurate across app suspension.
    private var isLikelyHealthy: Bool {
        streamReference != nil && pingTracker.hasRecentPing
    }

    public func stop() {
        isStreaming = false
        isReconnecting = false
        reportConnection(live: false)
        backoff.reset()
        owner = nil
        pingTimeoutTask?.cancel()
        pingTimeoutTask = nil
        pingTracker = PingTracker()
        reconnectTask?.cancel()
        reconnectTask = nil
        streamReference?.cancel()
        streamReference = nil
        logger.debug("Stopped event stream")
    }

    // MARK: - Private

    private func openStream() {
        guard isStreaming, let owner else {
            logger.warning("Cannot open event stream: not streaming or no owner")
            return
        }

        if let existing = streamReference {
            existing.cancel()
            streamReference = nil
        }
        pingTimeoutTask?.cancel()
        pingTimeoutTask = nil
        pingTracker = PingTracker()
        isReconnecting = false

        streamGeneration += 1
        let generation = streamGeneration

        let reference = service.openEventStream { [weak self] response in
            guard let self else { return }
            Task { await self.handleResponse(response, generation: generation) }
        } onComplete: { [weak self] result in
            guard let self else { return }
            Task { await self.handleStreamStatus(result, generation: generation) }
        }

        // The open handshake: the first message carries auth + a freshness nonce.
        let request = Flipcash_Event_V1_StreamEventsRequest.with {
            $0.params = .with {
                $0.ts = .init(date: .now)
                $0.auth = owner.authFor(message: $0)
            }
        }
        reference.sendMessage(request)

        self.streamReference = reference

        schedulePingTimeout(seconds: pingTracker.timeoutSeconds)
        // Treat open as a liveness signal so `ensureConnected` doesn't tear down
        // a fresh stream that hasn't received its first ping yet.
        pingTracker.lastPing = .now
        logger.info("Opened event stream", metadata: ["generation": "\(generation)"])
    }

    private func handleResponse(_ response: Flipcash_Event_V1_StreamEventsResponse, generation: UInt) {
        guard generation == streamGeneration else { return }

        switch response.type {
        case .ping(let ping):
            handlePing(ping)
        case .events(let batch):
            for event in batch.events {
                handleEvent(event)
            }
        case .error(let error):
            handleStreamError(error)
        case nil:
            logger.warning("Received empty event stream response")
        }
    }

    private func handleEvent(_ event: Flipcash_Event_V1_Event) {
        for streamEvent in ConversationStreamEvent.decode(event) {
            continuation.yield(streamEvent)
        }
    }

    private func handlePing(_ ping: Flipcash_Event_V1_ServerPing) {
        // A received ping is the stream's proof of life — the only safe point to
        // clear the reconnect backoff, so a stream that dies before its first ping
        // keeps escalating the delay instead of hammering reconnect.
        backoff.reset()

        // The same proof of life marks the connection delivering — once per
        // connection — so the consumer can refetch the window a drop left.
        reportConnection(live: true)

        let timeout = pingTracker.receivedPing(updatedTimeout: Int(ping.pingDelay.seconds))
        schedulePingTimeout(seconds: timeout)

        let pong = Flipcash_Event_V1_StreamEventsRequest.with {
            $0.pong = .with { $0.timestamp = .init(date: .now) }
        }
        streamReference?.sendMessage(pong)
    }

    private func handleStreamError(_ error: Flipcash_Event_V1_StreamEventsResponse.StreamError) {
        switch error.code {
        case .denied:
            logger.error("Event stream denied, stopping")
            stop()
        case .invalidTimestamp:
            logger.warning("Event stream rejected timestamp, reconnecting")
            reconnect()
        case .UNRECOGNIZED:
            logger.warning("Event stream returned an unrecognized error code")
            reconnect()
        }
    }

    private func handleTimeout() {
        logger.warning("Event stream ping timeout, reconnecting")
        reconnect()
    }

    private func handleStreamStatus(_ result: Result<Void, any Error>, generation: UInt) {
        guard generation == streamGeneration else { return }

        switch result {
        case .success:
            logger.debug("Event stream closed normally")
        case .failure(let error):
            if let rpcError = error as? RPCError,
               [.unavailable, .deadlineExceeded, .cancelled].contains(rpcError.code) {
                logger.warning("Event stream closed", metadata: [
                    "code": "\(rpcError.code)",
                    "message": "\(error)",
                ])
            } else {
                logger.error("Event stream closed unexpectedly", metadata: ["error": "\(error)"])
            }
        }

        reconnect()
    }

    private func resetAndTeardown() {
        pingTimeoutTask?.cancel()
        pingTimeoutTask = nil
        pingTracker = PingTracker()
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        backoff.reset()
        reportConnection(live: false)
        streamReference?.cancel()
        streamReference = nil
    }

    /// Emits a connection-state transition, ignoring repeats — every ping would
    /// otherwise re-report `.live`, and several teardown paths can each fire.
    private func reportConnection(live: Bool) {
        guard isConnectionLive != live else { return }
        isConnectionLive = live
        if live {
            // Mark when the stream starts delivering (first ping) — the edge that gates the
            // missed-window refetch, and the one transition no other log captures.
            logger.info("Event stream went live", metadata: ["generation": "\(streamGeneration)"])
        }
        connectionStateContinuation.yield(live ? .live : .disconnected)
    }

    private func schedulePingTimeout(seconds: Int) {
        pingTimeoutTask?.cancel()
        pingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.handleTimeout()
        }
    }

    private func reconnect() {
        guard isStreaming, !isReconnecting else { return }
        isReconnecting = true

        pingTimeoutTask?.cancel()
        pingTimeoutTask = nil
        pingTracker = PingTracker()
        reportConnection(live: false)
        streamReference?.cancel()
        streamReference = nil

        let delay = backoff.next()

        logger.debug("Reconnecting event stream", metadata: [
            "delaySeconds": "\(delay)",
            "attempt": "\(backoff.attempts)",
        ])

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.performReconnect()
        }
    }

    private func performReconnect() {
        guard isStreaming else {
            isReconnecting = false
            return
        }
        openStream()
    }
}
