//
//  ChannelGoAwayRecoveryTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import Synchronization
import GRPCCore
import GRPCNIOTransportHTTP2
@testable import FlipcashCore

/// A server GOAWAY while a long-lived stream holds the connection open used to leave every new RPC
/// failing with "Channel isn't ready, no subchannel available." until the stream ended: pick-first
/// waits for the going-away connection to close and the push resolver never re-resolves. These
/// tests shut a local server down gracefully (GOAWAY, open streams keep running) with a
/// replacement on the same port, using the app's production client wiring.
@Suite("Channel GOAWAY recovery")
struct ChannelGoAwayRecoveryTests {

    @Test("Unary RPCs recover after a GOAWAY lands while a stream is open")
    func unaryRecoversAfterGoAway() async throws {
        let server = try await LocalServer.start(port: 0)
        defer { server.stop() }

        let requests = ResolveRequests()
        let lookups = LookupCounter(requests)
        defer { lookups.stop() }
        let client = try GRPCTransport.makeClient(
            host: "127.0.0.1",
            port: server.port,
            transportSecurity: .plaintext,
            resolveRequests: requests
        )
        let connections = Task { try await client.runConnections() }
        defer {
            client.beginGracefulShutdown()
            connections.cancel()
        }

        // Stands in for the event stream: bidirectional and never half-closed, so the server's
        // graceful shutdown leaves it running and it holds the going-away connection open.
        let (received, receivedContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let stream = Task {
            defer { receivedContinuation.finish() }
            try await client.bidirectionalStreaming(
                request: StreamingClientRequest(of: String.self) { writer in
                    try await writer.write("hold")
                    try await Task.sleep(for: .seconds(3600))
                },
                descriptor: LocalServer.hold,
                serializer: UTF8Codec(),
                deserializer: UTF8Codec(),
                options: .defaults
            ) { response in
                for try await _ in response.messages { receivedContinuation.yield() }
            }
        }
        defer { stream.cancel() }

        var messages = received.makeAsyncIterator()
        try #require(await messages.next() != nil)
        #expect(try await echo(on: client) == "hi")

        server.beginGracefulShutdown()
        // Binding the replacement while the old listener is still closing tears down the held
        // stream, so give the GOAWAY time to land first.
        try await Task.sleep(for: .seconds(1))
        let replacement = try await LocalServer.start(port: server.port)
        defer { replacement.stop() }

        let recovered = await eventually(within: .seconds(5)) {
            (try? await echo(on: client)) == "hi"
        }
        #expect(recovered)
        #expect(lookups.count > 0)

        // The stream must still be on the old connection, or the GOAWAY never held it open.
        _ = await messages.next()
        #expect(await messages.next() != nil)
    }

    @Test("An outage with no stream open requests no lookup, leaving the reconnect backoff alone")
    func outageWithoutStreamRequestsNoLookup() async throws {
        let server = try await LocalServer.start(port: 0)
        let requests = ResolveRequests(minimumInterval: .zero)
        let lookups = LookupCounter(requests)
        defer { lookups.stop() }
        let client = try GRPCTransport.makeClient(
            host: "127.0.0.1",
            port: server.port,
            transportSecurity: .plaintext,
            resolveRequests: requests
        )
        let connections = Task { try await client.runConnections() }
        defer {
            client.beginGracefulShutdown()
            connections.cancel()
        }

        #expect(try await echo(on: client) == "hi")
        server.stop()

        var refusals = 0
        for _ in 0..<8 {
            do {
                _ = try await echo(on: client)
            } catch let error as RPCError where error.code == .unavailable {
                refusals += 1
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(refusals > 0)
        try await Task.sleep(for: .milliseconds(200))
        #expect(lookups.count == 0)
    }

    // MARK: - Helpers

    private func echo(on client: GRPCClient<AppTransport>) async throws -> String {
        try await client.unary(
            request: ClientRequest(message: "hi"),
            descriptor: LocalServer.echo,
            serializer: UTF8Codec(),
            deserializer: UTF8Codec(),
            options: .unaryDefault(timeout: .seconds(2))
        ) { try $0.message }
    }

    private func eventually(within limit: Duration, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }
}

/// Counts the lookup requests a `ResolveRequests` sends after it was made.
private final class LookupCounter: Sendable {

    private final class Total: Sendable {
        let value = Mutex(0)
    }

    private let total = Total()
    private let task: Task<Void, Never>

    init(_ requests: ResolveRequests) {
        let stream = requests.stream()
        let total = total
        task = Task {
            for await _ in stream { total.value.withLock { $0 += 1 } }
        }
    }

    var count: Int { total.value.withLock { $0 } }

    func stop() {
        task.cancel()
    }
}

/// An HTTP/2 server on loopback serving a unary echo and a bidirectional stream that writes every 200ms until cancelled.
/// Its graceful shutdown sends GOAWAY and never forces open streams closed.
private final class LocalServer: Sendable {

    static let echo = MethodDescriptor(fullyQualifiedService: "test.Echo", method: "Get")
    static let hold = MethodDescriptor(fullyQualifiedService: "test.Echo", method: "Hold")

    private let server: GRPCServer<HTTP2ServerTransport.Posix>
    private let task: Task<Void, any Error>
    let port: Int

    private init(server: GRPCServer<HTTP2ServerTransport.Posix>, task: Task<Void, any Error>, port: Int) {
        self.server = server
        self.task = task
        self.port = port
    }

    /// Starts serving on `port` (0 picks one), retrying while a previous listener on it closes.
    static func start(port: Int) async throws -> LocalServer {
        var lastError: (any Error)?
        for _ in 0..<20 {
            do {
                return try await bind(port: port)
            } catch {
                lastError = error
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        throw lastError!
    }

    private static func bind(port: Int) async throws -> LocalServer {
        let transport = HTTP2ServerTransport.Posix(
            address: .ipv4(host: "127.0.0.1", port: port),
            transportSecurity: .plaintext,
            config: .defaults
        )

        var router = RPCRouter<HTTP2ServerTransport.Posix>()
        router.registerHandler(
            forMethod: echo,
            deserializer: UTF8Codec(),
            serializer: UTF8Codec()
        ) { request, _ in
            let message = try await request.messages.reduce(into: "") { $0 += $1 }
            return StreamingServerResponse(single: ServerResponse(message: message))
        }
        router.registerHandler(
            forMethod: hold,
            deserializer: UTF8Codec(),
            serializer: UTF8Codec()
        ) { request, _ in
            StreamingServerResponse { writer in
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await _ in request.messages {}
                    }
                    group.addTask {
                        while true {
                            try await writer.write("ping")
                            try await Task.sleep(for: .milliseconds(200))
                        }
                    }
                    try await group.next()
                    group.cancelAll()
                }
                return [:]
            }
        }

        let server = GRPCServer(transport: transport, router: router)
        let task = Task { try await server.serve() }
        let address = try await transport.listeningAddress
        let port = try #require(address.ipv4?.port)
        return LocalServer(server: server, task: task, port: port)
    }

    /// Sends GOAWAY on every connection and stops listening; open RPCs keep running.
    func beginGracefulShutdown() {
        server.beginGracefulShutdown()
    }

    func stop() {
        server.beginGracefulShutdown()
        task.cancel()
    }
}

private struct UTF8Codec: MessageSerializer, MessageDeserializer {
    func serialize<Bytes: GRPCContiguousBytes>(_ message: String) throws -> Bytes {
        Bytes(Array(message.utf8))
    }

    func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> String {
        serializedMessageBytes.withUnsafeBytes { String(decoding: $0, as: UTF8.self) }
    }
}
