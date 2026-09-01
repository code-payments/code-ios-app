//
//  Key+Generate.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Security

extension Seed16 {
    
    public static func generate() -> Seed16? {
        guard let bytes = Data.randomSeed(count: Seed16.length) else {
            return nil
        }
        
        return try? Seed16([Byte](bytes))
    }
}

extension Seed32 {
    
    public static func generate() -> Seed32? {
        guard let bytes = Data.randomSeed(count: Seed32.length) else {
            return nil
        }
        
        return try? Seed32([Byte](bytes))
    }
}

// MARK: - Entropy -

extension Data {
    
    /// Cryptographically secure random bytes, previously the vendored C library's
    /// `ed25519_create_seed`. The shared Kotlin module excludes `seed.c` on purpose --
    /// it takes a caller-supplied seed rather than reaching for platform entropy.
    /// Returns `nil` on failure, matching what the C entry point reported through its
    /// status code.
    static func randomSeed(count: Int) -> Data? {
        var bytes = [Byte](repeating: 0, count: count)
        
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            return nil
        }
        
        return Data(bytes)
    }
}
