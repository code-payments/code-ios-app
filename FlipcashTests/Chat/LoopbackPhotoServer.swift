//
//  LoopbackPhotoServer.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Network

/// Answers every HTTP request on a loopback port with a 1×1 PNG, then closes the connection.
///
/// A server started `holding` keeps each request open until `release()`, so a test can act while a
/// download is in flight. A `URLProtocol` stub can't stand in for it: its transactions carry no
/// response, so Kingfisher reports no timings for any load through one.
final class LoopbackPhotoServer: @unchecked Sendable {

    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private let listener: NWListener
    private let queue = DispatchQueue(label: "loopback-photo-server")

    // Read and written only on `queue`.
    private var ready: CheckedContinuation<Void, Error>?
    private var holding: Bool
    private var held: [NWConnection] = []
    private var requests = 0
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(holding: Bool = false) throws {
        self.holding = holding
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// How many requests have arrived so far.
    var requestCount: Int {
        queue.sync { requests }
    }

    /// Starts listening and returns the port once the listener is ready.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ready = continuation
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    ready?.resume()
                    ready = nil
                case .failed(let error):
                    ready?.resume(throwing: error)
                    ready = nil
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [self] connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] _, _, _, _ in
                    requests += 1
                    let arrived = requestWaiters.filter { $0.count <= requests }
                    requestWaiters.removeAll { $0.count <= requests }
                    arrived.forEach { $0.continuation.resume() }
                    if holding {
                        held.append(connection)
                    } else {
                        Self.answer(connection)
                    }
                }
            }
            listener.start(queue: queue)
        }
        guard let port = listener.port?.rawValue else { throw URLError(.cannotConnectToHost) }
        return port
    }

    /// Returns once `count` requests have arrived.
    func waitForRequests(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if requests >= count {
                    continuation.resume()
                } else {
                    requestWaiters.append((count, continuation))
                }
            }
        }
    }

    /// Answers every held request, and every later one at once.
    func release() {
        queue.async { [self] in
            holding = false
            held.forEach(Self.answer)
            held.removeAll()
        }
    }

    func stop() {
        listener.cancel()
    }

    private static func answer(_ connection: NWConnection) {
        var response = Data((
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: image/png\r\n" +
            "Content-Length: \(png.count)\r\n" +
            "Connection: close\r\n\r\n"
        ).utf8)
        response.append(png)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
