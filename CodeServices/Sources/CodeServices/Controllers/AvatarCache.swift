//
//  AvatarCache.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import UIKit

@MainActor
public class AvatarCache {
    
    private var cachedAvatars: [String: UIImage] = [:]
    
    public init() {
        
    }
    
    public func isCached(url: URL, size: AvatarURL.Size = .bigger) throws -> Bool {
        let avatar = try AvatarURL(profileImageString: url.absoluteString)
        let avatarURL = avatar.url(for: size)
        
        let key = avatarURL.absoluteString
        
        return cachedAvatars[key] != nil
    }
    
    public func preloadAvatar(url: URL, size: AvatarURL.Size = .original) {
        Task {
            _ = try await loadAvatar(url: url, size: size)
        }
    }
    
    public func loadAvatar(url: URL, size: AvatarURL.Size = .original, ignoreCache: Bool = false) async throws -> UIImage {
        let avatar = try AvatarURL(profileImageString: url.absoluteString)
        let avatarURL = avatar.url(for: size)
        
        let key = avatarURL.absoluteString
        
        if !ignoreCache, let cachedAvatar = cachedAvatars[key] {
            return cachedAvatar
        }
        
        if ignoreCache {
            // Remove any values in case the subsequent
            // load fails, we won't have any stale images
            // in the cache left over
            cachedAvatars.removeValue(forKey: key)
        }
        
        let image = try await ImageLoader.shared.load(avatarURL)
        trace(.success, components: "Size: \(size)", "Image URL: \(avatarURL.absoluteString)")
        
        cachedAvatars[key] = image
        
        return image
    }
}

extension AvatarCache {
    public static let shared = AvatarCache()
}

// MARK: - Image Loader -

@MainActor
public class ImageLoader {
    
    public static let shared = ImageLoader()
    
    private init() {}
    
    public func load(_ url: URL) async throws -> UIImage {
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let image = UIImage(data: data) else {
            throw Error.invalidImageData
        }
        
        return image//Image(uiImage: image)
    }
}

extension ImageLoader {
    enum Error: Swift.Error {
        case invalidImageData
    }
}
