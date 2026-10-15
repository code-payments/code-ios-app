//
//  ComposerLinkPreviewTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
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
    func aRemovedPreviewStaysOffForTheDraft() async {
        let (preview, box) = preview()
        preview.update(for: "https://example.com/a")
        await settle(preview)
        preview.remove()
        #expect(preview.link == nil)
        preview.update(for: "")
        preview.update(for: "https://example.com/a")
        await settle(preview)
        #expect(preview.link == nil)
        #expect(box.asked.count == 1)
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
}
