//
//  HMAC.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import SharedCoreKit

/// HMAC, computed by the shared Kotlin implementation. Buffers for the same reason
/// `SHA256` does.
public struct HMAC {

    public let algorithm: Algorithm

    private let key: Data
    private var buffer = Data()

    public init(algorithm: Algorithm, key: Data) {
        self.algorithm = algorithm
        self.key = key
    }

    public mutating func update(_ data: Data) {
        buffer.append(data)
    }

    public mutating func update(_ UTF8String: String) {
        update(Data(UTF8String.utf8))
    }

    public func digestBytes() -> [Byte] {
        switch algorithm {
        case .sha256: return [Byte](SharedHash.hmacSHA256(key: key, message: buffer))
        case .sha512: return [Byte](SharedHash.hmacSHA512(key: key, message: buffer))
        }
    }

    public func digestData() -> Data {
        Data(digestBytes())
    }
}

// MARK: - Algorithm -

extension HMAC {
    /// Only the two the shared implementation offers. The CommonCrypto-backed enum this
    /// replaces also listed sha1/sha224/sha384; nothing in the app or its tests used them.
    public enum Algorithm {
        case sha256
        case sha512
    }
}
