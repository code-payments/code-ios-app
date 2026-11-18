//
//  ResolvingClientTransport.swift
//  FlipcashCore
//

import GRPCCore
import GRPCNIOTransportHTTP2
import Synchronization

/// A client transport that requests a fresh server lookup when its channel refuses an RPC as unavailable while another stream is open.
// After a GOAWAY the channel refuses new RPCs with `.unavailable` while a long-lived stream holds
// the old connection open, and a push resolver is never told to look again. A pushed result makes
// the channel dial a replacement connection, which ends the wedge. The refusal is thrown by
// `withStream` before any interceptor runs, so the request has to be made here. With no stream
// open the refusal is an ordinary outage; a lookup then would reset the channel's reconnect
// backoff, so it is left alone.
public struct ResolvingClientTransport: ClientTransport {

    /// The byte container the underlying HTTP/2 transport uses.
    public typealias Bytes = HTTP2ClientTransport.TransportServices.Bytes

    private let base: HTTP2ClientTransport.TransportServices
    private let requests: ResolveRequests
    private let openStreams = OpenStreams()

    /// Wraps `base`, sending a request to `requests` when `base` refuses an RPC as unavailable while another stream is open.
    init(base: HTTP2ClientTransport.TransportServices, requests: ResolveRequests) {
        self.base = base
        self.requests = requests
    }

    /// The underlying transport's retry throttle.
    public var retryThrottle: RetryThrottle? { base.retryThrottle }

    /// Runs the underlying transport's connections until shutdown.
    public func connect() async throws {
        try await base.connect()
    }

    /// Stops the underlying transport accepting new RPCs and lets open ones finish.
    public func beginGracefulShutdown() {
        base.beginGracefulShutdown()
    }

    /// Opens a stream on the underlying transport, requesting a fresh lookup if it is refused as unavailable while another stream is open.
    public func withStream<T: Sendable>(
        descriptor: MethodDescriptor,
        options: CallOptions,
        _ closure: (_ stream: RPCStream<Inbound, Outbound>, _ context: ClientContext) async throws -> T
    ) async throws -> T {
        do {
            return try await base.withStream(descriptor: descriptor, options: options) { stream, context in
                openStreams.add(1)
                defer { openStreams.add(-1) }
                return try await closure(stream, context)
            }
        } catch let error as RPCError where error.code == .unavailable {
            if openStreams.count > 0 {
                requests.request()
            }
            throw error
        }
    }

    /// The underlying transport's configuration for `descriptor`.
    public func config(forMethod descriptor: MethodDescriptor) -> MethodConfig? {
        base.config(forMethod: descriptor)
    }
}

/// How many streams the transport has open right now.
private final class OpenStreams: Sendable {

    private let value = Atomic<Int>(0)

    /// The number of open streams.
    var count: Int { value.load(ordering: .relaxed) }

    /// Adjusts the count by `delta`.
    func add(_ delta: Int) {
        value.add(delta, ordering: .relaxed)
    }
}
