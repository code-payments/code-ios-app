//
//  TipController.swift
//  Code
//
//  Created by Dima Bart on 2024-04-03.
//

import SwiftUI
import CodeServices

@MainActor
class TipController: ObservableObject {
    
    private(set) var inflightUser: (String, Code.Payload)?
    
    private(set) var userMetadata: TwitterUser?
    
    private(set) var userAvatar: Image?
    
    private let client: Client
    
    private var cachedUsers: [String: TwitterUser] = [:]
    private var cachedAvatars: [String: Image] = [:]
    
    // MARK: - Init -
    
    init(client: Client) {
        self.client = client
    }
    
    // MARK: - Actions -
    
    func fetchUser(username: String, payload: Code.Payload) async throws {
        inflightUser = (username, payload)
        
        let metadata = try await fetch(username: username)
        userMetadata = metadata
        userAvatar = try await fetchAvatar(username: username, url: metadata.avatarURL)
    }
    
    func fetch(username: String) async throws -> TwitterUser {
        let key = username.lowercased()
        
        if let cachedUser = cachedUsers[key] {
            return cachedUser
        }
        
        let user = try await client.fetchTwitterUser(username: username)
        
        cachedUsers[key] = user
        
        return user
    }
    
    func fetchAvatar(username: String, url: URL) async throws -> Image {
        let key = username.lowercased()
        
        if let cachedAvatar = cachedAvatars[key] {
            return cachedAvatar
        }
        
        let avatarURL = AvatarURL(profileImageString: url.absoluteString)
        let avatar = try await ImageLoader.shared.load(avatarURL.original)
        
        cachedAvatars[key] = avatar
        
        return avatar
    }
    
    func resetInflightUser() {
        inflightUser = nil
        userMetadata = nil
    }
}

struct AvatarURL {
    
    let normal: URL
    let bigger: URL
    let mini: URL
    let original: URL
    
    // MARK: - Init -
    
    init(normal: URL, bigger: URL, mini: URL, original: URL) {
        self.normal = normal
        self.bigger = bigger
        self.mini = mini
        self.original = original
    }
    
    init(profileImageString: String) {
        let suffixes: Set = [
            "_normal",
            "_bigger",
            "_mini",
            "_original",
        ]
        
        var string = profileImageString
        
        suffixes.forEach { suffix in
            string = string.replacingOccurrences(of: suffix, with: "")
        }
        
        let baseURL = URL(string: string)!
        
        let imagePath = baseURL.lastPathComponent
        var components = imagePath.components(separatedBy: ".")
        if components.count == 2 {
            components[0] = "\(components[0])"
        }
        
        self.init(
            normal:   Self.applying(suffix: "_normal", to: baseURL),
            bigger:   Self.applying(suffix: "_bigger", to: baseURL),
            mini:     Self.applying(suffix: "_mini",   to: baseURL),
            original: baseURL
        )
    }
    
    private static func applying(suffix: String, to baseURL: URL) -> URL {
        let separator = "."
        let imagePath = baseURL.lastPathComponent
        
        var components = imagePath.components(separatedBy: separator)
        if components.count == 2 {
            components[0] = "\(components[0])\(suffix)"
        }
        let newImagePath = components.joined(separator: separator)
        
        var updatedURL = baseURL
        
        updatedURL.deleteLastPathComponent()
        updatedURL.appendPathComponent(newImagePath)
        
        return updatedURL
    }
}

// MARK: - Image Loader -

class ImageLoader {
    
    static let shared = ImageLoader()
    
    private init() {}
    
    func load(_ url: URL) async throws -> Image {
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let image = UIImage(data: data) else {
            throw Error.invalidImageData
        }
        
        return Image(uiImage: image)
    }
}

extension ImageLoader {
    enum Error: Swift.Error {
        case invalidImageData
    }
}
