//
//  ShortVec.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

enum ShortVec {
    static func encodeLength(_ length: UInt16) -> Data {
        var data = Data()
        
        var remaining = Int(length)
        while true {
            var byte = UInt8(remaining & 0x7f)
            remaining >>= 7
            
            if remaining == 0 {
                data.append(byte)
                return Data(data)
            }
            
            byte |= 0x80
            data.append(byte)
        }
        
        return data
    }
    
    static func encode(_ components: [Data]) -> Data {
        var container = encodeLength(UInt16(components.count))
        components.forEach {
            container.append($0)
        }
        return container
    }
    
    static func encode(_ data: Data) -> Data {
        var container = encodeLength(UInt16(data.count))
        container.append(data)
        return container
    }
    
    static func decodeLength(_ data: Data) -> (length: Int, remaining: Data) {
        print("ShortVec.decodeLength called with \(data.count) bytes")
        var length = 0
        var size = 0
        
        guard data.count > 0 else {
            print("ShortVec.decodeLength: empty data")
            return (length, Data())
        }
        
        let bytes = data.bytes
        while size < data.count {
            let byte = Int(bytes[size])
            length |= (byte & 0x7f) << (size * 7)
            size += 1
            if (byte & 0x80) == 0 {
                break
            }
        }
        
        print("ShortVec.decodeLength: decoded length=\(length), consumed \(size) bytes, data.count=\(data.count)")
        
        guard data.count > size else {
            print("ShortVec.decodeLength: no remaining data (data.count <= size)")
            return (length, Data())
        }
        
        print("ShortVec.decodeLength: about to call data.tail(from: \(size))")
        let remaining = data.tail(from: size)
        print("ShortVec.decodeLength: tail returned, returning (\(length), \(remaining.count) bytes)")
        
        return (
            length: length,
            remaining: remaining
        )
    }
}
