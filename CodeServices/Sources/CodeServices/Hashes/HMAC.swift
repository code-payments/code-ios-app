//
//  HMAC.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CommonCrypto

public struct HMAC {
    
    public let algorithm: Algorithm
    
    private var context = CCHmacContext()
    
    public init(algorithm: Algorithm, key: Data) {
        self.algorithm = algorithm
        
        key.withUnsafeBytes {
            CCHmacInit(&context, algorithm.alg, $0.baseAddress, $0.count)
        }
    }
    
    public mutating func update(_ data: Data) {
        data.withUnsafeBytes {
            CCHmacUpdate(&context, $0.baseAddress, $0.count)
        }
    }
    
    public mutating func update(_ UTF8String: String) {
        update(Data(UTF8String.utf8))
    }
    
    public func digestBytes() -> [Byte] {
        var mutableContext = context
        var bytes = [Byte](repeating: 0,  count: algorithm.digestLength)
        
        CCHmacFinal(&mutableContext, &bytes)
        
        return bytes
    }
    
    public func digestData() -> Data {
        Data(digestBytes())
    }
}

// MARK: - Algorithm -

extension HMAC {
    public enum Algorithm {
        case sha1
        case sha224
        case sha256
        case sha384
        case sha512
    }
}

// MARK: - Utilities -

private extension HMAC.Algorithm {
    var alg: CCHmacAlgorithm {
        switch self {
        case .sha1:   return CCHmacAlgorithm(kCCHmacAlgSHA1)
        case .sha224: return CCHmacAlgorithm(kCCHmacAlgSHA224)
        case .sha256: return CCHmacAlgorithm(kCCHmacAlgSHA256)
        case .sha384: return CCHmacAlgorithm(kCCHmacAlgSHA384)
        case .sha512: return CCHmacAlgorithm(kCCHmacAlgSHA512)
        }
    }
    
    var digestLength: Int {
        switch self {
        case .sha1:   return Int(CC_SHA1_DIGEST_LENGTH)
        case .sha224: return Int(CC_SHA224_DIGEST_LENGTH)
        case .sha256: return Int(CC_SHA256_DIGEST_LENGTH)
        case .sha384: return Int(CC_SHA384_DIGEST_LENGTH)
        case .sha512: return Int(CC_SHA512_DIGEST_LENGTH)
        }
    }
}
