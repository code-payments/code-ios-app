//
//  LiveMintDataStreamer.swift
//  FlipcashCore
//
//  Created by Claude.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPC

private let logger = Logger(label: "flipcash.live-mint-data-streamer")

/// Manages bidirectional streaming for live mint data (exchange rates and reserve states).
/// Handles connection lifecycle, ping/pong keepalive, and auto-reconnection.
public actor LiveMintDataStreamer {

    public typealias StreamReference = BidirectionalStreamReference<
        Ocp_Currency_V1_StreamLiveMintDataRequest,
        Ocp_Currency_V1_StreamLiveMintDataResponse
    >

    private let service: CurrencyService
    private let verifiedProtoService: VerifiedProtoService

    private var streamReference: StreamReference?
    private var subscribedMints: Set<PublicKey> = []
    private var isStreaming = false
    private var isReconnecting = false
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var pingTimeoutTask: Task<Void, Never>?
    private var pingTracker = PingTracker()
    /// Bumped on every `openStream()`. gRPC response and status callbacks
    /// capture the value at open time and pass it back; handlers ignore
    /// callbacks whose generation doesn't match the current stream so a
    /// torn-down stream's late `.cancelled` can't tear down its replacement.
    private var streamGeneration: UInt = 0
    /// Set when a subscription update is sent on the existing stream.
    /// The server typically aborts the stream in response, so the next
    /// close should reconnect immediately without backoff.
    private var sentSubscriptionUpdate = false
    private static let maxReconnectDelay: TimeInterval = 30.0
    private static let baseReconnectDelay: TimeInterval = 1.0

    // MARK: - Init

    init(service: CurrencyService, verifiedProtoService: VerifiedProtoService) {
        self.service = service
        self.verifiedProtoService = verifiedProtoService
    }

    deinit {
        pingTimeoutTask?.cancel()
        reconnectTask?.cancel()
        streamReference?.destroy()
    }

    // MARK: - Public API

    /// Start streaming live mint data for the specified mints
    public func start(mints: some Collection<PublicKey>) {
        let mintSet = Set(mints)
        guard !isStreaming else {
            // Already streaming, just update mints if needed
            if mintSet != subscribedMints {
                updateMints(mintSet)
            }
            return
        }

        subscribedMints = mintSet
        isStreaming = true
        openStream()
    }

    /// Ensure the stream is alive. If it died (e.g. after backgrounding),
    /// tear it down and reopen immediately — bypassing exponential backoff.
    public func ensureConnected() {
        guard isStreaming, !subscribedMints.isEmpty else { return }

        // If the stream is alive and has received a recent ping, nothing to do
        if isLikelyHealthy, !isReconnecting {
            return
        }

        logger.warning("Stream not connected on foreground, forcing reconnect")
        resetAndTeardown()
        openStream()
    }

    private var isLikelyHealthy: Bool {
        streamReference?.stream != nil && pingTracker.hasRecentPing
    }

    /// Stop the stream
    public func stop() {
        isStreaming = false
        isReconnecting = false
        sentSubscriptionUpdate = false
        reconnectAttempts = 0
        pingTimeoutTask?.cancel()
        pingTimeoutTask = nil
        pingTracker = PingTracker()
        reconnectTask?.cancel()
        reconnectTask = nil
        streamReference?.destroy()
        streamReference = nil
        logger.debug("Stopped live mint data stream")
    }

    /// Update the set of mints to subscribe to.
    /// Sends a new request on the existing stream to avoid tearing it down.
    public func updateMints(_ mints: Set<PublicKey>) {
        guard mints != subscribedMints else { return }

        subscribedMints = mints

        if isStreaming, let stream = streamReference?.stream {
            // Send updated mint list on existing stream — no teardown needed.
            // The server may abort the stream in response; sentSubscriptionUpdate
            // tells handleStreamStatus to reconnect immediately.
            let request = Ocp_Currency_V1_StreamLiveMintDataRequest.with {
                $0.request = .with {
                    $0.mints = mints.map(\.solanaAccountID)
                }
            }
            _ = stream.sendMessage(request)
            sentSubscriptionUpdate = true
            logger.debug("Updated mint subscription", metadata: ["count": "\(mints.count)"])
        } else if isStreaming {
            // No active stream — open a new one
            openStream()
        }
    }

    // MARK: - Private

    private func openStream() {
        guard isStreaming, !subscribedMints.isEmpty else {
            logger.warning("Cannot open stream: not streaming or no mints")
            return
        }

        // Clean up any existing stream before creating a new one
        if let existing = streamReference {
            logger.debug("Cleaning up existing stream before opening new one")
            existing.destroy()
            streamReference = nil
        }
        pingTimeoutTask?.cancel()
        pingTimeoutTask = nil
        pingTracker = PingTracker()

        // Reset reconnect state on successful stream open
        isReconnecting = false
        reconnectAttempts = 0

        logger.info("Opening live mint data stream", metadata: ["count": "\(subscribedMints.count)"])

        streamGeneration += 1
        let generation = streamGeneration

        let reference = StreamReference()
        reference.retain()

        let stream = service.service.streamLiveMintData(callOptions: .streaming) { [weak self] response in
            guard let self else { return }
            Task { await self.handleResponse(response, generation: generation) }
        }

        // Send initial request with mints
        let request = Ocp_Currency_V1_StreamLiveMintDataRequest.with {
            $0.request = .with {
                $0.mints = subscribedMints.map(\.solanaAccountID)
            }
        }

        _ = stream.sendMessage(request)

        // Handle stream status changes
        stream.status.whenComplete { [weak self] result in
            guard let self else { return }
            Task { await self.handleStreamStatus(result, generation: generation) }
        }

        self.streamReference = reference
        reference.stream = stream

        schedulePingTimeout(seconds: pingTracker.timeoutSeconds)
        // Treat stream open as a liveness signal so `ensureConnected` doesn't
        // tear down a fresh stream that hasn't received its first ping yet.
        pingTracker.lastPing = .now
    }

    private func handleResponse(_ response: Ocp_Currency_V1_StreamLiveMintDataResponse, generation: UInt) async {
        guard generation == streamGeneration else { return }

        guard let type = response.type else {
            logger.warning("Received empty stream response")
            return
        }

        switch type {
        case .data(let liveData):
            await handleLiveData(liveData)

        case .ping(let ping):
            handlePing(ping)
        }
    }

    private func handleLiveData(_ liveData: Ocp_Currency_V1_StreamLiveMintDataResponse.LiveData) async {
        guard let type = liveData.type else {
            logger.warning("Received empty live data")
            return
        }

        switch type {
        case .coreMintFiatExchangeRates(let batch):
            await verifiedProtoService.saveRates(batch.exchangeRates)
        case .launchpadCurrencyReserveStates(let batch):
            await verifiedProtoService.saveReserveStates(batch.reserveStates)
        }
    }

    private func handlePing(_ ping: Ocp_Common_V1_ServerPing) {
        let timeout = pingTracker.receivedPing(updatedTimeout: Int(ping.pingDelay.seconds))
        schedulePingTimeout(seconds: timeout)

        let pongRequest = Ocp_Currency_V1_StreamLiveMintDataRequest.with {
            $0.pong = Ocp_Common_V1_ClientPong.with {
                $0.timestamp = .init(seconds: Int64(Date().timeIntervalSince1970))
            }
        }

        _ = streamReference?.stream?.sendMessage(pongRequest)
    }

    private func handleTimeout() {
        logger.warning("Stream timeout, reconnecting")
        reconnect()
    }

    private func handleStreamStatus(_ result: Result<GRPCStatus, Error>, generation: UInt) {
        guard generation == streamGeneration else {
            logger.debug("Ignoring status from previous stream generation", metadata: [
                "generation": "\(generation)",
                "current": "\(streamGeneration)",
            ])
            return
        }

        let wasSubscriptionUpdate = sentSubscriptionUpdate
        sentSubscriptionUpdate = false

        switch result {
        case .success(let status):
            switch status.code {
            case .ok:
                logger.debug("Stream closed normally")
                reconnect()

            case .aborted where wasSubscriptionUpdate:
                // Server aborts the stream after a subscription change.
                // Reconnect immediately — this is expected, not a failure.
                logger.debug("Stream aborted after subscription update, reopening")
                immediateReconnect()

            case .unavailable, .deadlineExceeded, .cancelled:
                logger.warning("Stream closed with \(status.code)")
                reconnect()

            default:
                logger.warning("Stream closed with status", metadata: [
                    "code": "\(status.code)",
                    "message": "\(status.message ?? "nil")"
                ])
                reconnect()
            }

        case .failure(let error):
            logger.error("Stream error", metadata: ["error": "\(error)"])
            reconnect()
        }
    }

    /// Cancel any pending backoff, tear down the current stream, and
    /// reset reconnection counters so the next `openStream()` starts fresh.
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
            guard let self else { return }
            await self.handleTimeout()
        }
    }

    /// Reconnect immediately without backoff. Used when the server closes
    /// the stream in response to a subscription update — not a real failure.
    private func immediateReconnect() {
        guard isStreaming else { return }
        resetAndTeardown()
        openStream()
    }

    private func reconnect() {
        guard isStreaming else { return }

        // Prevent multiple concurrent reconnection attempts
        guard !isReconnecting else {
            logger.debug("Already reconnecting, skipping duplicate attempt")
            return
        }
        isReconnecting = true

        // Clean up previous streams
        pingTimeoutTask?.cancel()
        pingTimeoutTask = nil
        pingTracker = PingTracker()
        streamReference?.destroy()
        streamReference = nil

        // Calculate exponential backoff delay
        reconnectAttempts += 1
        let delay = min(
            Self.baseReconnectDelay * pow(2.0, Double(reconnectAttempts - 1)),
            Self.maxReconnectDelay
        )

        logger.debug("Reconnecting live mint data stream", metadata: [
            "delaySeconds": "\(delay)",
            "attempt": "\(reconnectAttempts)"
        ])

        // Delay before reconnecting with exponential backoff
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
