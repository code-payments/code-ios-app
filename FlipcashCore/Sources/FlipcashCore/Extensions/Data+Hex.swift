//
//  Data+Hex.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Data {
    
    public func hexString() -> String {
        hexEncodedString()
    }
    
    public func hexEncodedString() -> String {
        let hexDigits = Array("0123456789abcdef".utf16)
        var chars: [unichar] = []
        chars.reserveCapacity(2 * count)
        for byte in self {
            chars.append(hexDigits[Int(byte / 16)])
            chars.append(hexDigits[Int(byte % 16)])
        }
        return String(utf16CodeUnits: chars, count: chars.count)
    }
}
