//
//  LiveMintDataStreamer.swift
//  FlipcashCore
//
//  Created by Claude.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation
import Combine
import FlipcashAPI
import GRPC

/// Manages bidirectional streaming for live mint data (exchange rates and reserve states).
/// Handles connection lifecycle, ping/pong keepalive, and auto-reconnection.
public final class LiveMintDataStreamer: @unchecked Sendable {

    public typealias StreamReference = BidirectionalStreamReference<
        Ocp_Currency_V1_StreamLiveMintDataRequest,
        Ocp_Currency_V1_StreamLiveMintDataResponse
    >

    private let service: CurrencyService
    private let verifiedProtoService: VerifiedProtoService
    private let queue: DispatchQueue

    private var streamReference: StreamReference?
    private var subscribedMints: [PublicKey] = []
    private var isStreaming = false

    // MARK: - Init

    init(service: CurrencyService, verifiedProtoService: VerifiedProtoService, queue: DispatchQueue) {
        self.service = service
        self.verifiedProtoService = verifiedProtoService
        self.queue = queue
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Start streaming live mint data for the specified mints
    public func start(mints: [PublicKey]) {
        guard !isStreaming else {
            // Already streaming, just update mints if needed
            if mints != subscribedMints {
                updateMints(mints)
            }
            return
        }

        subscribedMints = mints
        isStreaming = true
        openStream()
    }

    /// Stop the stream
    public func stop() {
        isStreaming = false
        streamReference?.destroy()
        streamReference = nil
        trace(.note, components: "Stopped live mint data stream")
    }

    /// Update the list of mints to subscribe to (restarts stream)
    public func updateMints(_ mints: [PublicKey]) {
        guard mints != subscribedMints else { return }

        subscribedMints = mints

        if isStreaming {
            // Close existing stream and reopen with new mints
            streamReference?.cancel()
            openStream()
        }
    }

    // MARK: - Private

    private func openStream() {
        guard isStreaming, !subscribedMints.isEmpty else {
            trace(.warning, components: "Cannot open stream: not streaming or no mints")
            return
        }

        trace(.open, components: "Opening live mint data stream for \(subscribedMints.count) mints")

        let reference = StreamReference()
        reference.retain()

        // Set timeout handler for reconnection
        reference.timeoutHandler = { [weak self] in
            self?.handleTimeout()
        }

        let stream = service.service.streamLiveMintData(callOptions: nil) { [weak self] response in
            self?.handleResponse(response)
        }

        // Send initial request with mints
        let request = Ocp_Currency_V1_StreamLiveMintDataRequest.with {
            $0.request = .with {
                $0.mints = subscribedMints.map(\.solanaAccountID)
            }
        }

        _ = stream.sendMessage(request)

        // Handle stream status changes
        stream.status.whenCompleteBlocking(onto: queue) { [weak self] result in
            self?.handleStreamStatus(result)
        }

        self.streamReference = reference
        reference.stream = stream
    }

    private func handleResponse(_ response: Ocp_Currency_V1_StreamLiveMintDataResponse) {
        guard let type = response.type else {
            trace(.warning, components: "Received empty stream response")
            return
        }

        switch type {
        case .data(let liveData):
            handleLiveData(liveData)

        case .ping(let ping):
            handlePing(ping)
        }
    }

    private func handleLiveData(_ liveData: Ocp_Currency_V1_StreamLiveMintDataResponse.LiveData) {
        guard let type = liveData.type else {
            trace(.warning, components: "Received empty live data")
            return
        }

        Task {
            switch type {
            case .coreMintFiatExchangeRates(let batch):
                await verifiedProtoService.saveRates(batch.exchangeRates)

            case .launchpadCurrencyReserveStates(let batch):
                await verifiedProtoService.saveReserveStates(batch.reserveStates)
            }
        }
    }

    private func handlePing(_ ping: Ocp_Common_V1_ServerPing) {
        trace(.receive, components: "Received ping, sending pong")

        // Update timeout based on server's ping interval
        streamReference?.receivedPing(updatedTimeout: Int(ping.pingDelay.seconds))

        // Send pong response
        let pongRequest = Ocp_Currency_V1_StreamLiveMintDataRequest.with {
            $0.pong = Ocp_Common_V1_ClientPong.with {
                $0.timestamp = .init(seconds: Int64(Date().timeIntervalSince1970))
            }
        }

        _ = streamReference?.stream?.sendMessage(pongRequest)
    }

    private func handleTimeout() {
        trace(.warning, components: "Stream timeout, reconnecting...")
        reconnect()
    }

    private func handleStreamStatus(_ result: Result<GRPCStatus, Error>) {
        switch result {
        case .success(let status):
            switch status.code {
            case .ok:
                trace(.note, components: "Stream closed normally")

            case .unavailable, .deadlineExceeded, .cancelled:
                trace(.warning, components: "Stream closed with \(status.code), reconnecting...")
                reconnect()

            default:
                trace(.failure, components: "Stream closed with status: \(status)")
            }

        case .failure(let error):
            trace(.failure, components: "Stream error: \(error)")
            reconnect()
        }
    }

    private func reconnect() {
        guard isStreaming else { return }

        // Clean up old stream
        streamReference?.release()
        streamReference = nil

        // Delay before reconnecting
        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.isStreaming else { return }
            self.openStream()
        }
    }
}
