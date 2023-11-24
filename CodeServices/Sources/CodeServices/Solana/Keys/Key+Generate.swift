//
//  Key+Generate.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import ed25519

extension Seed16 {
    
    public static func generate() -> Seed16? {
        var bytes = [Byte].zeroed(with: Seed16.length)
        let result = bytes.withUnsafeMutableBufferPointer {
            ed25519_create_seed_16($0.baseAddress)
        }
        
        guard result == 0 else {
            return nil
        }
        
        return Seed16(bytes)
    }
}

extension Seed32 {
    
    public static func generate() -> Seed32? {
        var bytes = [Byte].zeroed(with: Seed32.length)
        let result = bytes.withUnsafeMutableBufferPointer {
            ed25519_create_seed_32($0.baseAddress)
        }
        
        guard result == 0 else {
            return nil
        }
        
        return Seed32(bytes)
    }
}
