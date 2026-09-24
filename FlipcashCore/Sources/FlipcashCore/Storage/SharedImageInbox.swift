//
//  SharedImageInbox.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The handover between the share extension and the app: one file, written by the extension
/// and taken by the app.
///
/// A file rather than a pasteboard or a URL payload, because a photo is megabytes and both
/// of those have limits an image will hit. One file rather than a queue, because sharing a
/// second image before the first is scanned means the second is the one the user is looking
/// at.
///
/// `container` is injectable so the tests can use a temporary directory; in both real
/// targets it is the App Group container.
public struct SharedImageInbox: Sendable {

    /// The host of the URL the extension opens to hand over.
    private static let handoffHost = "scan-shared-image"

    private static let filename = "shared-image.data"

    private let container: URL

    public init(container: URL) {
        self.container = container
    }

    /// The group container, or nil if the App Group is not configured — which in practice
    /// means the entitlement is missing from one of the two targets.
    public init?() {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: NotificationPreviewCache.appGroup
            )
        else {
            return nil
        }
        self.init(container: container)
    }

    /// A fresh URL for the extension to open, carrying a nonce.
    ///
    /// The nonce is what makes two shares two deep links: `DeepLinkController` drops a repeat
    /// of the same URL within its repeat window, so a constant URL would make sharing a second
    /// image within a few seconds do nothing at all.
    public static func handoffURL() -> URL {
        var components = URLComponents()
        components.scheme = "flipcash"
        components.host = handoffHost
        components.queryItems = [URLQueryItem(name: "n", value: UUID().uuidString)]
        return components.url!
    }

    /// Whether a URL is a handover, whatever nonce it carries.
    public static func isHandoff(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "flipcash" && url.host()?.lowercased() == handoffHost
    }

    private var fileURL: URL {
        container.appendingPathComponent(Self.filename)
    }

    /// Replaces whatever is there. Written with `.completeFileProtectionUntilFirstUserAuthentication`
    /// so the app can read it after a share that happened while the device was locked.
    public func deposit(_ data: Data) throws {
        try data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    /// Reads and removes. Once, deliberately: a relaunch must not rescan an image the user
    /// already dealt with.
    public func take() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        try? FileManager.default.removeItem(at: fileURL)
        return data
    }
}
