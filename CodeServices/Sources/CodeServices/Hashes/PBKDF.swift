//
//  PBKDF.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CommonCrypto

public enum PBKDF {
    
    public static func deriveKey(algorithm: Algorithm, password: String, salt: String, rounds: Int = 2048) -> [Byte] {
        var bytes = [Byte](repeating: 0,  count: algorithm.digestLength)
        
        CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password,
            password.utf8.count,
            salt,
            salt.utf8.count,
            algorithm.alg,
            UInt32(rounds),
            &bytes,
            algorithm.digestLength
        )
        
        return bytes
    }
}

// MARK: - Algorithm -

extension PBKDF {
    public enum Algorithm {
        case sha1
        case sha224
        case sha256
        case sha384
        case sha512
    }
}

// MARK: - Utilities -

extension PBKDF.Algorithm {
    var alg: CCHmacAlgorithm {
        switch self {
        case .sha1:   return CCHmacAlgorithm(kCCPRFHmacAlgSHA1)
        case .sha224: return CCHmacAlgorithm(kCCPRFHmacAlgSHA224)
        case .sha256: return CCHmacAlgorithm(kCCPRFHmacAlgSHA256)
        case .sha384: return CCHmacAlgorithm(kCCPRFHmacAlgSHA384)
        case .sha512: return CCHmacAlgorithm(kCCPRFHmacAlgSHA512)
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
