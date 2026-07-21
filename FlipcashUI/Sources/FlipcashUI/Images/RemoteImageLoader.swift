//
//  RemoteImageLoader.swift
//  FlipcashUI
//

import UIKit
import Kingfisher

/// Loads a remote image eagerly, for callers that need the bytes rather than a
/// view — rendering to an image, or compositing into a graphic.
public enum RemoteImageLoader {

    /// Returns the image at `url`, cached under `cacheKey`.
    ///
    /// Pass a durable key for a signed URL: those are re-minted on every fetch,
    /// so a URL-derived key would re-download identical bytes each time.
    public static func image(at url: URL, cacheKey: String) async throws -> UIImage {
        let resource = KF.ImageResource(downloadURL: url, cacheKey: cacheKey)
        return try await KingfisherManager.shared.retrieveImage(with: resource).image
    }
}
