//
//  ChatMediaImageSource.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import Kingfisher

/// Where a chat photo's bytes load from, for every view that draws one.
public enum ChatMediaImageSource {

    /// The photo at `url`, cached under its blob rather than the URL. The URL is signed and minted
    /// per fetch, so keying on it would re-download the same photo every session.
    public static func resource(blobID: BlobID?, url: URL) -> KF.ImageResource {
        KF.ImageResource(downloadURL: url, cacheKey: blobID.map { "chat-media-\($0.description)" } ?? url.absoluteString)
    }
}
