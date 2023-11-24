//
//  FixedWidthInteger+Bytes.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension FixedWidthInteger {
    var bytes: [Byte] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }
    
    init?(bytes: [Byte], endianness: Endianness = .little) {
        guard bytes.count == MemoryLayout<Self>.size else {
            return nil
        }
        
        let integer = bytes.withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: Self.self).pointee
        }
        
        switch endianness {
        case .big:
            self.init(bigEndian: integer)
        case .little:
            self.init(littleEndian: integer)
        }
    }
    
    init?(data: Data, endianness: Endianness = .little) {
        guard data.count == MemoryLayout<Self>.size else {
            return nil
        }
        
        let integer = data.withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: Self.self).pointee
        }
        
        switch endianness {
        case .big:
            self.init(bigEndian: integer)
        case .little:
            self.init(littleEndian: integer)
        }
    }
}

enum Endianness {
    case little
    case big
}
