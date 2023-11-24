//
//  Data+Bytes.swift
//  Code
//
//  Created by Dima Bart on 2021-02-10.
//

import Foundation
import CryptoKit

extension Data {
    
    static let nonceLength: Int = 11
    
    static var nonce: Data {
        var data = Data(count: nonceLength)
        let result = data.withUnsafeMutableBytes { (pointer: UnsafeMutableRawBufferPointer) in
            SecRandomCopyBytes(kSecRandomDefault, nonceLength, pointer.baseAddress!)
        }
        
        if result == errSecSuccess {
            return data
        } else {
            let uuid = UUID().uuid
            return Data([
                uuid.0, uuid.1, uuid.2, uuid.3,
                uuid.4, uuid.5, uuid.6, uuid.7,
                uuid.8, uuid.9, uuid.10,
            ])
        }
    }
    
//    var bytes: [UInt8] {
//        withUnsafeBytes { Array($0) }
//    }
}

extension SHA256.Digest {
    var bytes: [UInt8] {
        withUnsafeBytes { Array($0) }
    }
}
