//
//  EventStreamer.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPC

private let logger = Logger(label: "flipcash.event-streamer")

/// Owns the single per-user bidirectional event stream (`event.v1 StreamEvents`)
/// and decodes chat updates into `ChatStreamEvent`s consumed via `events`. The
/// server enforces one stream per user, so exactly one instance must exist per
/// session; opening a second silently evicts the first.
public actor EventStreamer {

    public typealias StreamReference = BidirectionalStreamReference<
        Flipcash_Event_V1_StreamEventsRequest,
        Flipcash_Event_V1_StreamEventsResponse
    >

    /// Decoded chat updates. Consume with `for await event in streamer.events`.
    public nonisolated let events: AsyncStream<ChatStreamEvent>
    private let continuation: AsyncStream<ChatStreamEvent>.Continuation

    private let service: EventStreamingService
    private var owner: KeyPair?

    private var streamReference: StreamReference?
    private var isStreaming = false
    private var isReconnecting = false
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var pingTimeoutTask: Task<Void, Never>?
    private var pingTracker = PingTracker()
    /// Bumped on every `openStream()`; gRPC callbacks capture the value at open
    /// time so a torn-down stream's late status can't tear down its replacement.
    private var streamGeneration: UInt = 0
    private static let maxReconnectDelay: TimeInterval = 30
    private static let baseReconnectDelay: TimeInterval = 1

    init(service: EventStreamingService) {
        self.service = service
        let (stream, continuation) = AsyncStream<ChatStreamEvent>.makeStream()
        self.events = stream
        self.continuation = continuation
    }

    deinit {
        pingTimeoutTask?.cancel()
        reconnectTask?.cancel()
        streamReference?.destroy()
        continuation.finish()
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
        if streamReference?.stream != nil, pingTracker.hasRecentPing, !isReconnecting {
            return
        }
        logger.warning("Event stream not connected, forcing reconnect")
        resetAndTeardown()
        openStream()
    }

    public func stop() {
        isStreaming = false
        isReconnecting = false
        reconnectAttempts = 0
        owner = nil
        pingTimeoutTask?.cancel()
        pingTimeoutTask = nil
        pingTracker = PingTracker()
        reconnectTask?.cancel()
        reconnectTask = nil
        streamReference?.destroy()
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
            existing.destroy()
            streamReference = nil
        }
        pingTimeoutTask?.cancel()
        pingTimeoutTask = nil
        pingTracker = PingTracker()
        isReconnecting = false
        reconnectAttempts = 0

        streamGeneration += 1
        let generation = streamGeneration

        let reference = StreamReference()
        reference.retain()

        let stream = service.service.streamEvents(callOptions: .streaming) { [weak self] response in
            guard let self else { return }
            Task { await self.handleResponse(response, generation: generation) }
        }

        // The open handshake: the first message carries auth + a freshness nonce.
        let request = Flipcash_Event_V1_StreamEventsRequest.with {
            $0.params = .with {
                $0.ts = .init(date: .now)
                $0.auth = owner.authFor(message: $0)
            }
        }
        _ = stream.sendMessage(request)

        stream.status.whenComplete { [weak self] result in
            guard let self else { return }
            Task { await self.handleStreamStatus(result, generation: generation) }
        }

        self.streamReference = reference
        reference.stream = stream

        schedulePingTimeout(seconds: pingTracker.timeoutSeconds)
        // Treat open as a liveness signal so `ensureConnected` doesn't tear down
        // a fresh stream that hasn't received its first ping yet.
        pingTracker.lastPing = .now
        logger.info("Opened event stream")
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
        // Test events and future event types are ignored by the PoC.
        guard case .chatUpdate(let update)? = event.type else { return }

        let chatID = ChatID(update.chat)

        let messages = update.newMessages.messages.compactMap(ChatMessage.init)
        if !messages.isEmpty {
            continuation.yield(.newMessages(chatID: chatID, messages: messages))
        }

        for metadataUpdate in update.metadataUpdates {
            switch metadataUpdate.kind {
            case .fullRefresh(let refresh):
                continuation.yield(.metadataRefresh(Conversation(refresh.metadata)))
            case .lastActivityChanged(let changed):
                continuation.yield(.lastActivityChanged(chatID: chatID, date: changed.newLastActivity.date))
            case nil:
                break
            }
        }
    }

    private func handlePing(_ ping: Flipcash_Event_V1_ServerPing) {
        let timeout = pingTracker.receivedPing(updatedTimeout: Int(ping.pingDelay.seconds))
        schedulePingTimeout(seconds: timeout)

        let pong = Flipcash_Event_V1_StreamEventsRequest.with {
            $0.pong = .with { $0.timestamp = .init(date: .now) }
        }
        _ = streamReference?.stream?.sendMessage(pong)
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

    private func handleStreamStatus(_ result: Result<GRPCStatus, Error>, generation: UInt) {
        guard generation == streamGeneration else { return }

        switch result {
        case .success(let status):
            logger.debug("Event stream closed", metadata: ["code": "\(status.code)"])
        case .failure(let error):
            logger.error("Event stream error", metadata: ["error": "\(error)"])
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
        reconnectAttempts = 0
        streamReference?.destroy()
        streamReference = nil
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
        streamReference?.destroy()
        streamReference = nil

        reconnectAttempts += 1
        let delay = min(
            Self.baseReconnectDelay * pow(2.0, Double(reconnectAttempts - 1)),
            Self.maxReconnectDelay
        )

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
