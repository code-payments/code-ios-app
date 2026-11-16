//
//  ChatMediaInFlightTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI
import Kingfisher

/// A row is reconfigured whenever the transcript updates around it, and the URL it was handed can
/// expire or be minted again while its photo downloads. Starting over then would throw away the
/// bytes already in, which costs most on a slow connection.
@Suite("Chat photo cell in-flight download", .timeLimit(.minutes(1)))
@MainActor
struct ChatMediaInFlightTests {

    @Test("A row reconfigured with a re-minted URL mid-download keeps the download it started")
    func remintedURLKeepsDownload() async throws {
        let server = try LoopbackPhotoServer(holding: true)
        let port = try await server.start()
        defer { server.stop() }
        let row = Self.row()
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        cell.configure(with: row, maxWidth: 240, localImage: nil, remote: ChatMediaLocation(url: Self.url(port, signature: "1")))
        await server.waitForRequests(1)
        cell.configure(with: row, maxWidth: 240, localImage: nil, remote: ChatMediaLocation(url: Self.url(port, signature: "2")))
        server.release()
        try await Self.untilLoaded(cell)

        #expect(server.requestCount == 1)
        #expect(cell.imageView.image != nil)
    }

    @Test("A row reconfigured after its URL expired mid-download keeps the download it started")
    func expiredURLKeepsDownload() async throws {
        let server = try LoopbackPhotoServer(holding: true)
        let port = try await server.start()
        defer { server.stop() }
        let row = Self.row()
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        cell.configure(with: row, maxWidth: 240, localImage: nil, remote: ChatMediaLocation(url: Self.url(port, signature: "1")))
        await server.waitForRequests(1)
        cell.configure(with: row, maxWidth: 240, localImage: nil, remote: nil)
        server.release()
        try await Self.untilLoaded(cell)

        #expect(server.requestCount == 1)
        #expect(cell.imageView.image != nil)
    }

    /// A row of its own photo, so no cached copy from another test answers the load.
    private static func row() -> ChatMessage {
        let media = ChatMediaContent(
            blobID: BlobID(data: Data(UUID().uuidString.utf8)),
            width: 1,
            height: 1,
            blurhash: nil,
            caption: nil,
            isRedacted: false
        )
        return ChatMessage(id: "1", content: .media(media), sender: .other, canReact: true)
    }

    private static func url(_ port: UInt16, signature: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)/photo.png?Signature=\(signature)")!
    }

    /// Kingfisher clears the view's task once its load finishes or is cancelled, so this returns
    /// either way; the suite's time limit only catches a load that never ends.
    private static func untilLoaded(_ cell: ChatMediaCell) async throws {
        while cell.imageView.kf.taskIdentifier != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
