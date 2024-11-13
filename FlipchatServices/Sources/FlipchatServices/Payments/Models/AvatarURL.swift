//
//  AvatarURL.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct AvatarURL {
    
    public let normal: URL
    public let bigger: URL
    public let mini: URL
    public let original: URL
    
    // MARK: - Init -
    
    init(normal: URL, bigger: URL, mini: URL, original: URL) {
        self.normal = normal
        self.bigger = bigger
        self.mini = mini
        self.original = original
    }
    
    public init(profileImageString: String) throws {
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
        
        guard let baseURL = URL(string: string) else {
            throw Error.invalidURL
        }
        
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
    
    public func url(for size: Size) -> URL {
        switch size {
        case .mini:
            return mini
        case .normal:
            return normal
        case .bigger:
            return bigger
        case .original:
            return original
        }
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

extension AvatarURL {
    public enum Size {
        case mini
        case normal
        case bigger
        case original
    }
}

extension AvatarURL {
    public enum Error: Swift.Error {
        case invalidURL
    }
}
