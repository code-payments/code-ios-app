//
//  SHA224.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CommonCrypto

public struct SHA224: HashType {
    
    private var context = CC_SHA256_CTX()
    
    public init() {
        CC_SHA224_Init(&context)
    }
    
    public mutating func update(_ data: Data) {
        data.withUnsafeBytes {
            _ = CC_SHA224_Update(&context, $0.baseAddress, CC_LONG($0.count))
        }
    }
    
    public func digestBytes() -> [Byte] {
        var mutableContext = context
        var bytes = [Byte](repeating: 0,  count: Int(CC_SHA224_DIGEST_LENGTH))
        
        CC_SHA224_Final(&bytes, &mutableContext)
        
        return bytes
    }
}
