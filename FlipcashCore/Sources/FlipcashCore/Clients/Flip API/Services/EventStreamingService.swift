//
//  EventStreamingService.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

/// Wraps the generated `event.v1 EventStreaming` v2 client and exposes the single
/// bidirectional `StreamEvents` RPC as a retained `BidirectionalGRPCStream`. The
/// stream lifecycle (ping/pong, reconnect, backoff) lives in `EventStreamer`.
final class EventStreamingService: Sendable {

    private let service: Flipcash_Event_V1_EventStreaming.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Event_V1_EventStreaming.Client(wrapping: client)
    }

    func openEventStream(
        onResponse: @escaping @Sendable (Flipcash_Event_V1_StreamEventsResponse) -> Void,
        onComplete: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) -> BidirectionalGRPCStream<Flipcash_Event_V1_StreamEventsRequest, Flipcash_Event_V1_StreamEventsResponse> {
        let stream = BidirectionalGRPCStream<Flipcash_Event_V1_StreamEventsRequest, Flipcash_Event_V1_StreamEventsResponse>()
        stream.open(onResponse: onResponse, onComplete: onComplete) { requests, onResponse in
            try await self.service.streamEvents(
                requestProducer: { writer in
                    for await request in requests {
                        try await writer.write(request)
                    }
                },
                onResponse: { streamResponse in
                    for try await message in streamResponse.messages {
                        onResponse(message)
                    }
                }
            )
        }
        return stream
    }
}
