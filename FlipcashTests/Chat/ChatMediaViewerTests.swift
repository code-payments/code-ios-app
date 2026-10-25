//
//  ChatMediaViewerTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Observation
import UIKit
import FlipcashCore
@testable import FlipcashUI

@Observable
private final class ReactionsModel {
    var liked = false
}

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
        ChatMediaViewerRequest(message: message, localImage: localImage, remote: remoteURL.map { ChatMediaLocation(url: $0) }, placeholder: nil) { nil }
    }

    // MARK: - Request

    @Test("A viewable photo opens with its blob and URL")
    func viewablePhotoOpens() throws {
        let viewer = try #require(request(message(media())))
        #expect(viewer.blobID == Self.blobID)
        #expect(viewer.remote?.url == Self.remoteURL)
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
        let viewer = try #require(request(message(media()), localImage: Self.localImage, remoteURL: nil))
        #expect(viewer.localImage === Self.localImage)
    }

    // MARK: - Viewer

    @Test("The viewer zooms in from the tapped photo")
    func zoomsFromSource() throws {
        let source = UIView()
        let request = try #require(ChatMediaViewerRequest(
            message: message(media()), localImage: Self.localImage, remote: nil, placeholder: nil
        ) { source })
        let viewer = makeViewer(request)

        #expect(viewer.preferredTransition != nil)
        #expect(request.sourceView() === source)
    }

    @Test("Pinch zooms the photo itself, past its fitted size")
    func pinchZoomsThePhoto() throws {
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)))

        #expect(viewer.scrollView.maximumZoomScale > viewer.scrollView.minimumZoomScale)
        #expect(viewer.viewForZooming(in: viewer.scrollView) === viewer.imageView)
    }

    @Test("The viewer is always dark, so its glass and glyphs match the black backdrop")
    func viewerIsDark() throws {
        let request = try #require(ChatMediaViewerRequest(
            message: message(media()), localImage: Self.localImage, remote: nil, placeholder: nil
        ) { nil })
        let viewer = makeViewer(request)
        #expect(viewer.overrideUserInterfaceStyle == .dark)
        #expect(viewer.view.traitCollection.userInterfaceStyle == .dark)
    }

    @Test("Double-tap zooms in, and a second double-tap zooms back out")
    func doubleTapTogglesZoom() {
        let scale = ChatMediaViewerController.doubleTapTargetScale
        #expect(scale(1, 1) > 1)
        #expect(scale(2.5, 1) == 1)
    }

    private func makeViewer(
        _ request: ChatMediaViewerRequest,
        onReply: @escaping () -> Void = {},
        onForward: @escaping () -> Void = {},
        onSave: @escaping (UIImage) async throws -> Void = { _ in },
        onReact: @escaping (String) -> Void = { _ in },
        entries: @escaping () -> [ReactionStrip.Entry] = { [ReactionStrip.Entry(emoji: "👍", highlighted: false), ReactionStrip.Entry(emoji: "❤️", highlighted: false)] }
    ) -> ChatMediaViewerController {
        let viewer = ChatMediaViewerController(
            request: request, onReply: onReply, onForward: onForward, onSave: onSave,
            onReact: onReact, onMoreReactions: {}, reactionEntries: entries
        )
        viewer.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        viewer.view.layoutIfNeeded()
        return viewer
    }

    @Test("The photo opens with no buttons showing")
    func opensWithControlsHidden() throws {
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)))

        #expect(viewer.areControlsHidden)
        #expect(viewer.closeButton.alpha == 0)
        #expect(!viewer.closeButton.isUserInteractionEnabled)
        #expect(viewer.closeButton.accessibilityElementsHidden)
    }

    @Test("A tap shows the buttons, and a second tap hides them again")
    func tapTogglesControls() throws {
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)))

        viewer.setControlsHidden(false, animated: false)
        #expect(!viewer.areControlsHidden)
        for view in [viewer.closeButton, viewer.leadingPill, viewer.trailingPill] {
            #expect(view.alpha == 1)
            #expect(view.isUserInteractionEnabled)
            #expect(!view.accessibilityElementsHidden)
        }

        viewer.setControlsHidden(true, animated: false)
        #expect(viewer.areControlsHidden)
        #expect(viewer.closeButton.alpha == 0)
        for pill in [viewer.leadingPill, viewer.trailingPill] {
            #expect(pill.alpha == 0)
            #expect(pill.accessibilityElementsHidden)
            #expect(!pill.isUserInteractionEnabled)
        }
    }

    @Test("Every button carries an accessibility label")
    func buttonsAreLabelled() throws {
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)))
        let labels = [viewer.closeButton, viewer.reactButton, viewer.replyButton, viewer.saveButton, viewer.forwardButton].map(\.accessibilityLabel)
        #expect(labels == ["Close", "React", "Reply", "Save", "Forward"])
    }

    @Test("Save waits until the photo itself has loaded")
    func saveWaitsForPhoto() throws {
        let placeholder = UIImage(systemName: "photo")!
        let request = try #require(ChatMediaViewerRequest(
            message: message(media()), localImage: nil, remote: ChatMediaLocation(url: URL(string: "https://example.invalid/never.jpg")!), placeholder: placeholder
        ) { nil })
        var saved: UIImage?
        let viewer = makeViewer(request, onSave: { saved = $0 })

        #expect(viewer.imageView.image === placeholder)
        #expect(!viewer.saveButton.isEnabled)
        viewer.saveButton.sendActions(for: .touchUpInside)
        #expect(saved == nil)
    }

    @Test("Save is enabled once the photo is loaded, and writes it")
    func saveEnabledWhenLoaded() async throws {
        var saved: UIImage?
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)), onSave: { saved = $0 })

        #expect(viewer.saveButton.isEnabled)
        viewer.saveButton.sendActions(for: .touchUpInside)
        try await Task.sleep(for: .milliseconds(100))
        #expect(saved === Self.localImage)
    }

    @Test("The zoom toggle goes to the double-tap scale, and a second call returns to fit")
    func zoomButtonTogglesScale() throws {
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)))
        let center = CGPoint(x: viewer.imageView.bounds.midX, y: viewer.imageView.bounds.midY)

        viewer.toggleZoom(about: center, animated: false)
        #expect(viewer.scrollView.zoomScale > viewer.scrollView.minimumZoomScale)

        viewer.toggleZoom(about: center, animated: false)
        #expect(viewer.scrollView.zoomScale == viewer.scrollView.minimumZoomScale)
    }

    @Test("React shows only when the row can react, loaded photo or not")
    func reactFollowsCanReact() throws {
        let reactable = makeViewer(try #require(request(message(media()), localImage: Self.localImage)))
        #expect(!reactable.reactButton.isHidden)

        let placeholder = UIImage(systemName: "photo")!
        let unloaded = try #require(ChatMediaViewerRequest(
            message: message(media()), localImage: nil, remote: ChatMediaLocation(url: URL(string: "https://example.invalid/never.jpg")!), placeholder: placeholder
        ) { nil })
        #expect(!makeViewer(unloaded).reactButton.isHidden)

        let locked = ChatMessage(id: "photo", content: .media(media()), sender: .other, canReact: false)
        #expect(request(locked, localImage: Self.localImage) == nil)
    }

    @Test("React opens the strip, a pick calls the handler and dismisses it, and the viewer stays")
    func reactStripPick() throws {
        var picked: String?
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)), onReact: { picked = $0 })
        viewer.setControlsHidden(false, animated: false)

        viewer.reactButton.sendActions(for: .touchUpInside)
        let strip = try #require(viewer.reactionStrip)
        #expect(strip.superview === viewer.view)

        strip.onSelect?("👍")
        #expect(picked == "👍")
        #expect(viewer.reactionStrip == nil)
    }

    @Test("Hiding the chrome dismisses the strip without reacting")
    func hidingChromeDismissesStrip() throws {
        var picked: String?
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)), onReact: { picked = $0 })
        viewer.setControlsHidden(false, animated: false)
        viewer.reactButton.sendActions(for: .touchUpInside)
        #expect(viewer.reactionStrip != nil)

        viewer.setControlsHidden(true, animated: false)
        #expect(viewer.reactionStrip == nil)
        #expect(picked == nil)
    }

    @Test("The open strip re-reads its entries when the reactions it depends on change")
    func stripFollowsLiveReactions() async throws {
        let model = ReactionsModel()
        var reads = 0
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)), entries: {
            reads += 1
            return [ReactionStrip.Entry(emoji: "👍", highlighted: model.liked)]
        })
        viewer.setControlsHidden(false, animated: false)
        viewer.reactButton.sendActions(for: .touchUpInside)
        let before = reads

        model.liked = true
        try await Task.sleep(for: .milliseconds(100))

        #expect(reads > before)
        #expect(viewer.reactionStrip != nil)
    }

    @Test("Close sits above the tap catcher, so one tap on it still closes the viewer")
    func closeStaysAboveCatcher() throws {
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)))
        viewer.setControlsHidden(false, animated: false)
        viewer.reactButton.sendActions(for: .touchUpInside)

        let subviews = viewer.view.subviews
        let catcher = try #require(subviews.first { $0 is UIControl && $0 !== viewer.closeButton })
        let closeIndex = try #require(subviews.firstIndex(of: viewer.closeButton))
        let catcherIndex = try #require(subviews.firstIndex(of: catcher))
        #expect(closeIndex > catcherIndex)
    }

    @Test("With Reduce Motion on, zoom still changes scale and the strip appears without scaling")
    func reduceMotion() throws {
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)))
        viewer.reducesMotion = { true }
        let center = CGPoint(x: viewer.imageView.bounds.midX, y: viewer.imageView.bounds.midY)

        viewer.toggleZoom(about: center, animated: true)
        #expect(viewer.scrollView.zoomScale > viewer.scrollView.minimumZoomScale)
        viewer.toggleZoom(about: center, animated: true)
        #expect(viewer.scrollView.zoomScale == viewer.scrollView.minimumZoomScale)

        viewer.setControlsHidden(false, animated: false)
        viewer.reactButton.sendActions(for: .touchUpInside)
        #expect(viewer.reactionStrip?.transform == .identity)
    }

    @Test("A second React tap closes the strip")
    func secondTapClosesStrip() throws {
        let viewer = makeViewer(try #require(request(message(media()), localImage: Self.localImage)))
        viewer.reactButton.sendActions(for: .touchUpInside)
        viewer.reactButton.sendActions(for: .touchUpInside)
        #expect(viewer.reactionStrip == nil)
    }

    @Test("Reply and Forward follow the row's context-menu actions")
    func replyAndForwardFollowCapabilities() throws {
        let plain = makeViewer(try #require(request(message(media()), localImage: Self.localImage)))
        #expect(plain.replyButton.isHidden)
        #expect(plain.forwardButton.isHidden)

        let withActions = ChatMessage(id: "photo", content: .media(media()), sender: .other, actions: [.reply, .forward], canReact: true)
        let capable = makeViewer(try #require(request(withActions, localImage: Self.localImage)))
        #expect(!capable.replyButton.isHidden)
        #expect(!capable.forwardButton.isHidden)
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
