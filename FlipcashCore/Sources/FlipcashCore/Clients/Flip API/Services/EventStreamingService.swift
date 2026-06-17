//
//  EventStreamingService.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPC

/// Thin wrapper exposing the generated `event.v1 EventStreaming` NIO client.
/// The stream lifecycle lives in `EventStreamer`.
class EventStreamingService: CodeService<Flipcash_Event_V1_EventStreamingNIOClient> {
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Event_V1_EventStreamingClientInterceptorFactoryProtocol {
    func makeStreamEventsInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Event_V1_StreamEventsRequest, Flipcash_Event_V1_StreamEventsResponse>] {
        makeInterceptors()
    }

    func makeForwardEventsInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Event_V1_ForwardEventsRequest, Flipcash_Event_V1_ForwardEventsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Event_V1_EventStreamingNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
