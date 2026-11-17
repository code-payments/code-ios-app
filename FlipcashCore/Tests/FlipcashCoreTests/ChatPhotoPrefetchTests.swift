//
//  ChatPhotoPrefetchTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
@testable import FlipcashCore

/// Ports of Android's `PhotoPrefetchPolicyTest`, case for case, so both apps skip the same photos.
/// Android's Data Saver is iOS's Low Data Mode. The own-message and expensive-network cases are
/// additions: Android drops its own messages before the policy, and has no roaming input.
@Suite("Chat photo prefetch policy")
struct ChatPhotoPrefetchTests {

    private let online = ChatPhotoPrefetchNetwork(connected: true, constrained: false, expensive: false)

    private func skip(
        own: Bool = false,
        redacted: Bool = false,
        muted: Bool = false,
        cached: Bool = false,
        network: ChatPhotoPrefetchNetwork? = nil
    ) -> ChatPhotoPrefetchSkip? {
        ChatPhotoPrefetch.skip(own: own, redacted: redacted, muted: muted, cached: cached, network: network ?? online)
    }

    @Test("A new photo on a connected network is fetched")
    func fetched() {
        #expect(skip() == nil)
    }

    @Test("A redacted photo is not fetched")
    func redacted() {
        #expect(skip(redacted: true) == .redacted)
    }

    @Test("A photo in a muted chat is not fetched")
    func muted() {
        #expect(skip(muted: true) == .muted)
    }

    @Test("A photo already cached is not fetched again")
    func cached() {
        #expect(skip(cached: true) == .cached)
    }

    @Test("Nothing is fetched without a network")
    func offline() {
        #expect(skip(network: .init(connected: false, constrained: false, expensive: false)) == .offline)
    }

    @Test("Nothing is fetched while Low Data Mode is on")
    func lowDataMode() {
        #expect(skip(network: .init(connected: true, constrained: true, expensive: false)) == .lowDataMode)
    }

    @Test("The photo's own state is reported before the network's")
    func photoStateFirst() {
        let offlineInLowData = ChatPhotoPrefetchNetwork(connected: false, constrained: true, expensive: false)
        #expect(skip(redacted: true, muted: true, network: offlineInLowData) == .redacted)
        #expect(skip(muted: true, cached: true, network: offlineInLowData) == .muted)
        #expect(skip(cached: true, network: offlineInLowData) == .cached)
        #expect(skip(network: offlineInLowData) == .offline)
    }

    // MARK: - Additions

    @Test("A photo this account sent is not fetched, whatever else holds")
    func own() {
        #expect(skip(own: true) == .own)
        #expect(skip(own: true, redacted: true, muted: true, cached: true, network: .init(connected: false, constrained: true, expensive: true)) == .own)
    }

    @Test("Cellular, a hotspot or roaming is no reason to skip")
    func expensive() {
        #expect(skip(network: .init(connected: true, constrained: false, expensive: true)) == nil)
    }
}

/// The bubble width a prefetch picks its copy for, which must be the width the transcript lays out.
@Suite("Chat photo bubble layout")
struct ChatPhotoBubbleLayoutTests {

    @Test("A DM photo spans the fraction of the row")
    func directMessage() {
        #expect(ChatPhotoBubbleLayout.maxWidth(rowWidth: 400, attributedIncoming: false) == 400 * 0.78)
    }

    @Test("A group member's photo leaves the avatar gutter out")
    func attributedIncoming() {
        #expect(ChatPhotoBubbleLayout.maxWidth(rowWidth: 400, attributedIncoming: true) == (400 - 32) * 0.78)
    }

    @Test("A row wider than a phone is sized as a phone-width row")
    func wideRow() {
        #expect(ChatPhotoBubbleLayout.maxWidth(rowWidth: 1024, attributedIncoming: false) == 440 * 0.78)
        #expect(ChatPhotoBubbleLayout.maxWidth(rowWidth: 1024, attributedIncoming: true) == (440 - 32) * 0.78)
    }

    @Test("The target is the bubble width in pixels, rounded")
    func targetPixels() {
        #expect(ChatPhotoBubbleLayout.targetPixels(maxWidth: 306.54, scale: 3) == 920)
        #expect(ChatPhotoBubbleLayout.targetPixels(maxWidth: 306.54, scale: 2) == 613)
    }

    @Test("A view not yet on a screen is taken as 3x")
    func unknownScale() {
        #expect(ChatPhotoBubbleLayout.targetPixels(maxWidth: 100, scale: 0) == 300)
    }
}
