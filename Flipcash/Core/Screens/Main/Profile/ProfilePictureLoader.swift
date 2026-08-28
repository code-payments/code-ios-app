//
//  ProfilePictureLoader.swift
//  Flipcash
//

import UIKit
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.profile-picture")

/// Fetches the thumbnail behind a profile picture.
///
/// Every surface that draws one — the tab bar, the tip card, the photo editor —
/// fetches it the same way, and none of them treat a failure as fatal: each
/// falls back to what it drew before there was a picture.
enum ProfilePictureLoader {

    /// The picture's thumbnail, or nil when there is no picture, the blob has no
    /// download URL, or the fetch failed.
    static func thumbnail(
        for picture: ProfilePicture?,
        using client: FlipClient,
        owner: KeyPair
    ) async -> UIImage? {
        guard let blobID = picture?.thumbnailBlobID else { return nil }

        // Answered from the cache before the round trip below, so a relaunch draws
        // the picture at first paint instead of after a download URL comes back.
        // Safe to trust: a blob is immutable, so a new picture is a new key.
        if let cached = await RemoteImageLoader.cachedImage(cacheKey: blobID.description) {
            return cached
        }

        do {
            // Download URLs expire, so one is minted per load and never stored.
            guard let url = try await client.blobDownloadURL(blobID: blobID, owner: owner) else {
                logger.info("Profile picture blob has no download URL", metadata: ["blobId": "\(blobID)"])
                return nil
            }

            return try await RemoteImageLoader.image(at: url, cacheKey: blobID.description)
        } catch {
            guard !Task.isCancelled else { return nil }
            logger.info("Failed to load a profile picture", metadata: ["error": "\(error)"])
            return nil
        }
    }
}
