//
//  ChatPhotoPrefetch.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The network a photo prefetch would download over, as far as ``ChatPhotoPrefetch`` cares.
public struct ChatPhotoPrefetchNetwork: Equatable, Sendable {

    /// Whether iOS will let the app open a connection.
    public let connected: Bool

    /// Whether Low Data Mode is on for this network (`NWPath.isConstrained`).
    public let constrained: Bool

    /// Whether the network is cellular, a personal hotspot or roaming (`NWPath.isExpensive`). It is
    /// not a reason to skip: Android prefetches on every connected network, roaming included.
    public let expensive: Bool

    public init(connected: Bool, constrained: Bool, expensive: Bool) {
        self.connected = connected
        self.constrained = constrained
        self.expensive = expensive
    }
}

/// Why a photo that just arrived is not downloaded before its chat is opened.
public enum ChatPhotoPrefetchSkip: String, Sendable {
    /// The photo is this account's own; it was sent from here or is already on another device.
    case own
    /// The bubble draws only the BlurHash and loads nothing.
    case redacted
    /// The chat is muted, so its photos are not worth data before the user looks.
    case muted
    /// The copy the bubble draws is already in the cache.
    case cached
    case offline
    case lowDataMode
}

/// Whether a photo that just arrived is downloaded before its chat is opened. The same rules as
/// Android's `photoPrefetchSkip`, so both apps spend data on the same photos.
public enum ChatPhotoPrefetch {

    /// Why the photo is skipped, or nil to download it. The photo's own state is reported before the
    /// network's, so a log line names the reason that would still hold on a better network.
    public static func skip(
        own: Bool,
        redacted: Bool,
        muted: Bool,
        cached: Bool,
        network: ChatPhotoPrefetchNetwork
    ) -> ChatPhotoPrefetchSkip? {
        if own { return .own }
        if redacted { return .redacted }
        if muted { return .muted }
        if cached { return .cached }
        if !network.connected { return .offline }
        if network.constrained { return .lowDataMode }
        return nil
    }
}
