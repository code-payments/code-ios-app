//
//  ChatMediaViewerTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@Suite("Chat photo viewer")
@MainActor
struct ChatMediaViewerTests {

    private static let blobID = BlobID(data: Data([1]))
    private static let remoteURL = URL(string: "https://example.com/a.jpg")!
    private static let localImage = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
    }

    private func media(isRedacted: Bool = false) -> ChatMediaContent {
        ChatMediaContent(blobID: Self.blobID, width: 40, height: 30, blurhash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj", caption: nil, isRedacted: isRedacted)
    }

    private func message(
        _ media: ChatMediaContent,
        canReact: Bool = true,
        receipt: ChatReceipt? = nil
    ) -> ChatMessage {
        ChatMessage(id: "photo", content: .media(media), sender: .other, receipt: receipt, canReact: canReact)
    }

    private func request(
        _ message: ChatMessage,
        localImage: UIImage? = nil,
        remoteURL: URL? = ChatMediaViewerTests.remoteURL
    ) -> ChatMediaViewerRequest? {
        ChatMediaViewerRequest(message: message, localImage: localImage, remoteURL: remoteURL, placeholder: nil) { nil }
    }

    // MARK: - Request

    @Test("A viewable photo opens with its blob and URL")
    func viewablePhotoOpens() throws {
        let request = try #require(request(message(media())))
        #expect(request.blobID == Self.blobID)
        #expect(request.remoteURL == Self.remoteURL)
    }

    @Test("A redacted photo, or one seen while previewing a group, never opens")
    func blurhashOnlyNeverOpens() {
        #expect(request(message(media(isRedacted: true))) == nil)
        #expect(request(message(media(), canReact: false)) == nil)
        #expect(request(message(media(isRedacted: true)), localImage: Self.localImage) == nil)
    }

    @Test("A failed send opens nothing: its tap is the retry")
    func failedRowNeverOpens() {
        #expect(request(message(media(), receipt: .failed("Not delivered")), localImage: Self.localImage) == nil)
    }

    @Test("A photo with nothing to show yet opens nothing")
    func unresolvedPhotoNeverOpens() {
        #expect(request(message(media()), remoteURL: nil) == nil)
    }

    @Test("A pending send opens on its staged image")
    func pendingSendOpens() throws {
        let request = try #require(request(message(media()), localImage: Self.localImage, remoteURL: nil))
        #expect(request.localImage === Self.localImage)
    }

    // MARK: - Viewer

    @Test("The viewer zooms in from the tapped photo")
    func zoomsFromSource() throws {
        let source = UIView()
        let request = try #require(ChatMediaViewerRequest(
            message: message(media()), localImage: Self.localImage, remoteURL: nil, placeholder: nil
        ) { source })
        let viewer = ChatMediaViewerController(request: request) { _ in }

        #expect(viewer.preferredTransition != nil)
        #expect(request.sourceView() === source)
    }

    @Test("Pinch zooms the photo itself, past its fitted size")
    func pinchZoomsThePhoto() throws {
        let viewer = ChatMediaViewerController(request: try #require(request(message(media()), localImage: Self.localImage))) { _ in }
        viewer.loadViewIfNeeded()

        #expect(viewer.scrollView.maximumZoomScale > viewer.scrollView.minimumZoomScale)
        #expect(viewer.viewForZooming(in: viewer.scrollView) === viewer.imageView)
    }

    @Test("Double-tap zooms in, and a second double-tap zooms back out")
    func doubleTapTogglesZoom() {
        let scale = ChatMediaViewerController.doubleTapTargetScale
        #expect(scale(1, 1) > 1)
        #expect(scale(2.5, 1) == 1)
    }

    @Test("Share hands the loaded photo to the share sheet")
    func sharesLoadedPhoto() throws {
        var shared: UIImage?
        let viewer = ChatMediaViewerController(request: try #require(request(message(media()), localImage: Self.localImage))) { shared = $0 }
        viewer.loadViewIfNeeded()

        #expect(viewer.shareButton.isEnabled)
        viewer.shareButton.sendActions(for: .touchUpInside)
        #expect(shared === Self.localImage)
    }

    @Test("Share waits until the photo itself has loaded")
    func shareWaitsForPhoto() throws {
        let placeholder = UIImage(systemName: "photo")!
        let request = try #require(ChatMediaViewerRequest(
            message: message(media()), localImage: nil, remoteURL: URL(string: "https://example.invalid/never.jpg")!, placeholder: placeholder
        ) { nil })
        var shared: UIImage?
        let viewer = ChatMediaViewerController(request: request) { shared = $0 }
        viewer.loadViewIfNeeded()

        #expect(viewer.imageView.image === placeholder)
        #expect(!viewer.shareButton.isEnabled)
        viewer.shareButton.sendActions(for: .touchUpInside)
        #expect(shared == nil)
    }

    // MARK: - Transcript wiring

    private func transcript(_ message: ChatMessage, localImage: UIImage? = nil) -> (ChatViewController, ChatMediaCell) {
        let controller = ChatViewController()
        controller.pendingMediaImage = { _ in localImage }
        controller.loadViewIfNeeded()
        controller.update(items: [.message(message)])
        let cell = controller.collectionView(controller.collectionView, cellForItemAt: IndexPath(item: 0, section: 0))
        return (controller, cell as! ChatMediaCell)
    }

    @Test("Tapping a viewable photo asks the owner to open it")
    func tapOpensViewer() {
        let (controller, cell) = transcript(message(media()), localImage: Self.localImage)
        var opened: ChatMediaViewerRequest?
        controller.onMediaTap = { opened = $0 }

        cell.onImageTap?()

        #expect(opened?.blobID == Self.blobID)
        #expect(opened?.localImage === Self.localImage)
    }

    @Test("A redacted photo's tap, even forced, opens nothing")
    func blurhashOnlyTapOpensNothing() {
        let (controller, cell) = transcript(message(media(isRedacted: true)), localImage: Self.localImage)
        var opened = false
        controller.onMediaTap = { _ in opened = true }

        #expect(!cell.imageTap.isEnabled)
        cell.onImageTap?()

        #expect(!opened)
    }

    @Test("The photo's tap leaves the transcript's keyboard-dismiss tap free to fire")
    func photoTapDoesNotSwallowKeyboardDismiss() throws {
        let (controller, cell) = transcript(message(media()), localImage: Self.localImage)
        let dismissTap = try #require(controller.collectionView.gestureRecognizers?.first {
            $0 is UITapGestureRecognizer && $0.delegate === controller
        } as? UITapGestureRecognizer)

        #expect(!dismissTap.cancelsTouchesInView)
        #expect(controller.gestureRecognizer(dismissTap, shouldRecognizeSimultaneouslyWith: cell.imageTap))
    }
}
