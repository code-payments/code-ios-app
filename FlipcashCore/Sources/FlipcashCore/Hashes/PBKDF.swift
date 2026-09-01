//
//  PBKDF.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import SharedCoreKit

public enum PBKDF {

    /// PBKDF2, computed by the shared Kotlin implementation. Returns the PRF's digest
    /// length, as the CommonCrypto version did.
    public static func deriveKey(
        algorithm: Algorithm, password: String, salt: String, rounds: Int = 2048
    ) -> [Byte] {
        switch algorithm {
        case .sha512:
            return [Byte](SharedHash.pbkdf2SHA512(
                password: password, salt: salt, iterations: rounds, keyLength: 64
            ))
        }
    }
}

// MARK: - Algorithm -

extension PBKDF {
    /// Only SHA-512 -- the BIP39 seed function is the sole caller. The CommonCrypto-backed
    /// enum this replaces also listed sha1/sha224/sha256/sha384.
    public enum Algorithm {
        case sha512
    }
}
