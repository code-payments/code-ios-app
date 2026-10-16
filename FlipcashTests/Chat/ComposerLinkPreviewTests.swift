//
//  ComposerLinkPreviewTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import UIKit
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("ComposerLinkPreview")
struct ComposerLinkPreviewTests {

    private static let page = ComposerLinkPreview.Page(title: "  Example\nTitle ", description: "A page.", image: nil, thumbnail: nil)

    /// A preview whose loader answers `page` and counts the URLs it was asked for.
    private func preview(answering page: ComposerLinkPreview.Page? = Self.page) -> (ComposerLinkPreview, Box) {
        let box = Box()
        let preview = ComposerLinkPreview()
        preview.load = { url in
            box.asked.append(url.absoluteString)
            return page
        }
        return (preview, box)
    }

    private final class Box { var asked: [String] = [] }

    private func settle(_ preview: ComposerLinkPreview) async {
        for _ in 0..<20 where { if case .loading = preview.state { true } else { false } }() {
            await Task.yield()
        }
    }

    @Test
    func aDraftLinkLoadsItsPreview() async {
        let (preview, box) = preview()
        preview.update(for: "look https://example.com/a")
        #expect(preview.link == "https://example.com/a")
        await settle(preview)
        #expect(box.asked == ["https://example.com/a"])
        guard case .ready = preview.state else { Issue.record("not ready"); return }
    }

    @Test
    func aRestoredDraftLinkLoadsItsPreview() async {
        let composer = ComposerModel()
        var asked: [String] = []
        composer.linkPreview.load = { url in
            asked.append(url.absoluteString)
            return Self.page
        }
        composer.restore(ChatDraft(text: "https://example.com/a", replyTarget: nil))
        await settle(composer.linkPreview)
        #expect(asked == ["https://example.com/a"])
        #expect(composer.showsLinkPreview)
    }

    @Test
    func typingAroundTheSameLinkFetchesOnce() async {
        let (preview, box) = preview()
        preview.update(for: "https://example.com/a")
        await settle(preview)
        preview.update(for: "https://example.com/a and more")
        preview.update(for: "so https://example.com/a and more")
        await settle(preview)
        #expect(box.asked.count == 1)
    }

    @Test
    func aFailedFetchIsNotRetriedOnEveryKeystroke() async {
        let (preview, box) = preview(answering: nil)
        preview.update(for: "https://example.com/a")
        await settle(preview)
        preview.update(for: "https://example.com/a x")
        await settle(preview)
        #expect(preview.link == nil)
        #expect(box.asked.count == 1)
    }

    @Test
    func aRemovedPreviewStaysOffWhileItsLinkStays() async {
        let (preview, box) = preview()
        preview.update(for: "https://example.com/a")
        await settle(preview)
        preview.remove()
        #expect(preview.link == nil)
        preview.update(for: "https://example.com/a and more")
        await settle(preview)
        #expect(preview.link == nil)
        #expect(box.asked.count == 1)
    }

    @Test
    func aRemovedPreviewComesBackOnceItsLinkIsEditedOut() async {
        let (preview, box) = preview()
        preview.update(for: "https://example.com/a")
        await settle(preview)
        preview.remove()
        preview.update(for: "https://example.com/")
        preview.update(for: "https://example.com/a")
        await settle(preview)
        #expect(preview.link == "https://example.com/a")
        #expect(box.asked.last == "https://example.com/a")
    }

    @Test
    func resetForgetsRemovals() async {
        let (preview, box) = preview()
        preview.update(for: "https://example.com/a")
        await settle(preview)
        preview.remove()
        preview.reset()
        preview.update(for: "https://example.com/a")
        await settle(preview)
        #expect(preview.link == "https://example.com/a")
        #expect(box.asked.count == 2)
    }

    @Test
    func noLinkMeansNoFetch() async {
        let (preview, box) = preview()
        preview.update(for: "no links here")
        await settle(preview)
        #expect(preview.link == nil)
        #expect(box.asked.isEmpty)
    }

    @Test
    func theAttachmentIsCleanedAtSend() async throws {
        let (preview, _) = preview()
        preview.update(for: "https://example.com/a")
        await settle(preview)
        let sent = try #require(preview.attachment(for: "see https://example.com/a"))
        #expect(sent.url == "https://example.com/a")
        #expect(sent.title == "Example Title")
        #expect(sent.description == "A page.")
    }

    @Test
    func aBareDomainIsSentAsHTTPS() async throws {
        let (preview, box) = preview()
        preview.update(for: "see example.com")
        await settle(preview)
        #expect(box.asked == ["https://example.com"])
        let sent = try #require(preview.attachment(for: "see example.com"))
        #expect(sent.url == "https://example.com")
    }

    @Test
    func aCapitalisedSchemeGetsNoCard() async {
        let (preview, box) = preview()
        preview.update(for: "Https://example.com")
        await settle(preview)
        #expect(preview.link == nil)
        #expect(box.asked.isEmpty)
    }

    @Test
    func noAttachmentOnceTheLinkIsNoLongerWhole() async {
        let (preview, _) = preview()
        preview.update(for: "https://example.com/a")
        await settle(preview)
        #expect(preview.attachment(for: "https://example.com/abc") == nil)
        #expect(preview.attachment(for: "nothing") == nil)
    }

    @Test
    func noAttachmentWhileLoading() {
        let preview = ComposerLinkPreview()
        preview.load = { _ in try? await Task.sleep(for: .seconds(60)); return Self.page }
        preview.update(for: "https://example.com/a")
        #expect(preview.attachment(for: "https://example.com/a") == nil)
        preview.reset()
    }

    @Test
    func aTitleThatCleansToNothingSendsNoPreview() async {
        let (preview, _) = preview(answering: .init(title: " \n\t ", description: nil, image: nil, thumbnail: nil))
        preview.update(for: "https://example.com/a")
        await settle(preview)
        #expect(preview.attachment(for: "https://example.com/a") == nil)
    }

    // MARK: - Image upload

    private static let picture = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
    private static let uploaded = MediaAttachment(blobID: BlobID(data: Data(repeating: 7, count: 16)), width: 4, height: 4, blurhash: nil)

    /// A preview whose page has an image and whose upload waits until `release` answers it.
    private func uploadingPreview() -> (ComposerLinkPreview, (MediaAttachment?) -> Void) {
        let page = ComposerLinkPreview.Page(title: "Example", description: nil, image: nil, thumbnail: Self.picture)
        let (preview, _) = preview(answering: page)
        let (answers, answer) = AsyncStream.makeStream(of: MediaAttachment?.self)
        preview.upload = { _ in
            for await image in answers { return image }
            return nil
        }
        return (preview, { answer.yield($0) })
    }

    private func settleUpload(_ preview: ComposerLinkPreview) async {
        for _ in 0..<50 {
            if case .ready(_, _, let page) = preview.state, !page.isUploadingImage { return }
            await Task.yield()
        }
    }

    @Test
    func thePageShowsBeforeItsImageUploads() async {
        let (preview, release) = uploadingPreview()
        preview.update(for: "https://example.com/a")
        await settle(preview)
        guard case .ready(_, _, let page) = preview.state else { Issue.record("not ready"); return }
        #expect(page.thumbnail != nil)
        #expect(page.isUploadingImage)
        #expect(preview.attachment(for: "https://example.com/a")?.image == nil)
        release(Self.uploaded)
        await settleUpload(preview)
        #expect(preview.attachment(for: "https://example.com/a")?.image == Self.uploaded)
    }

    @Test
    func aFailedUploadDropsTheThumbnail() async {
        let (preview, release) = uploadingPreview()
        preview.update(for: "https://example.com/a")
        await settle(preview)
        release(nil)
        await settleUpload(preview)
        guard case .ready(_, _, let page) = preview.state else { Issue.record("not ready"); return }
        #expect(page.thumbnail == nil)
        #expect(preview.attachment(for: "https://example.com/a")?.title == "Example")
    }

    @Test
    func withoutAnUploaderThePageGoesWithoutItsImage() async {
        let page = ComposerLinkPreview.Page(title: "Example", description: nil, image: nil, thumbnail: Self.picture)
        let (preview, _) = preview(answering: page)
        preview.update(for: "https://example.com/a")
        await settle(preview)
        guard case .ready(_, _, let ready) = preview.state else { Issue.record("not ready"); return }
        #expect(ready.thumbnail == nil)
    }
}
