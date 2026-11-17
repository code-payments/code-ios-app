//
//  ChatMediaRetrieveTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import Network
@testable import FlipcashUI
import Kingfisher

@Suite("Chat photo retrieve")
@MainActor
struct ChatMediaRetrieveTests {

    /// Link cards and the viewer load through `retrieve`, not an image view. Kingfisher reads a
    /// download's timings after decoding it, through a weak reference that only the returned task
    /// keeps alive, so a load that drops the task logs no timings.
    ///
    /// A `URLProtocol` stub can't stand in for the server: its transactions carry no response, so
    /// Kingfisher reports no timings for any load through one.
    @Test("A network load outside an image view reports its timings")
    func networkLoadKeepsMetrics() async throws {
        let server = try LoopbackPhotoServer()
        let port = try await server.start()
        defer { server.stop() }

        let downloader = ImageDownloader(name: "chat-media-retrieve-test")
        let cache = ImageCache(name: "chat-media-retrieve-test-\(UUID().uuidString)")
        let manager = KingfisherManager(downloader: downloader, cache: cache)
        let url = URL(string: "http://127.0.0.1:\(port)/photo-\(UUID().uuidString).png")!

        let result = await ChatMediaImageSource.retrieve(.network(url), options: [.targetCache(cache)], manager: manager)

        let value = try result.get()
        #expect(value.cacheType == .none)
        #expect(value.metrics != nil)
    }
}

/// Answers every HTTP request on a loopback port with a 1×1 PNG, then closes the connection.
private final class LoopbackPhotoServer: @unchecked Sendable {

    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private let listener: NWListener
    private let queue = DispatchQueue(label: "chat-media-retrieve-test.server")
    /// Read and cleared only on `queue`, where the listener reports its state.
    private var ready: CheckedContinuation<Void, Error>?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
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
            listener.newConnectionHandler = { [queue] connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                    var response = Data((
                        "HTTP/1.1 200 OK\r\n" +
                        "Content-Type: image/png\r\n" +
                        "Content-Length: \(Self.png.count)\r\n" +
                        "Connection: close\r\n\r\n"
                    ).utf8)
                    response.append(Self.png)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            listener.start(queue: queue)
        }
        guard let port = listener.port?.rawValue else { throw URLError(.cannotConnectToHost) }
        return port
    }

    func stop() {
        listener.cancel()
    }
}
