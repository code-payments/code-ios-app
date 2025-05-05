//
//  Base58.swift
//  NeoSwift
//
//  Created by Luís Silva on 11/09/17.
//  Copyright © 2017 drei. All rights reserved.
//

import Foundation
import CodeCurves

/// Encodes and decodes base58 bytes and strings
///
/// Sourced from:
/// https://github.com/metaplex-foundation/Solana.Swift/blob/master/Sources/Solana/Vendor/Base58.swift
///
/// The current version is a modified version of the original:
/// https://github.com/CityOfZion/neo-swift/blob/master/NeoSwift/Models/Marketplace/Base58.swift
///
public enum Base58 {
    
    private static let base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

    public static func fromBytes(_ bytes: [UInt8]) -> String {
        var bytes = bytes
        var zerosCount = 0
        var length = 0

        for b in bytes {
            if b != 0 { break }
            zerosCount += 1
        }

        bytes.removeFirst(zerosCount)

        let size = bytes.count * 138 / 100 + 1

        var base58: [UInt8] = Array(repeating: 0, count: size)
        for b in bytes {
            var carry = Int(b)
            var i = 0

            for j in 0...base58.count-1 where carry != 0 || i < length {
                carry += 256 * Int(base58[base58.count - j - 1])
                base58[base58.count - j - 1] = UInt8(carry % 58)
                carry /= 58
                i += 1
            }

            assert(carry == 0)

            length = i
        }

        // skip leading zeros
        var zerosToRemove = 0
        var str = ""
        for b in base58 {
            if b != 0 { break }
            zerosToRemove += 1
        }
        base58.removeFirst(zerosToRemove)

        while 0 < zerosCount {
            str = "\(str)1"
            zerosCount -= 1
        }

        for b in base58 {
            str = "\(str)\(base58Alphabet[String.Index(encodedOffset: Int(b))])"
        }

        return str
    }
    
    public static func toBytes(_ base58: String) -> [UInt8] {
        // remove leading and trailing whitespaces
        let string = base58.trimmingCharacters(in: CharacterSet.whitespaces)

        guard !string.isEmpty else { return [] }

        var zerosCount = 0
        var length = 0
        for c in string {
            if c != "1" { break }
            zerosCount += 1
        }

        let size = string.lengthOfBytes(using: String.Encoding.utf8)
        var base58: [UInt8] = Array(repeating: 0, count: size)
        for c in string where c != " " {
            // search for base58 character
            guard let base58Index = base58Alphabet.firstIndex(of: c) else { return [] }

            var carry = base58Index.encodedOffset
            var i = 0
            for j in 0...base58.count where carry != 0 || i < length {
                carry += 58 * Int(base58[base58.count - j - 1])
                base58[base58.count - j - 1] = UInt8(carry % 256)
                carry /= 256
                i += 1
            }

            assert(carry == 0)
            length = i
        }

        // skip leading zeros
        var zerosToRemove = 0

        for b in base58 {
            if b != 0 { break }
            zerosToRemove += 1
        }
        base58.removeFirst(zerosToRemove)

        var result: [UInt8] = Array(repeating: 0, count: zerosCount)
        for b in base58 {
            result.append(b)
        }
        return result
    }
}

/// High-performance, optimized version (not yet tested)
/*
public enum Base58 {
    
    @inline(__always) private static let encodeAlphabet: [UInt8] =
        Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

    /// -1 marks “invalid”; 0…57 are the actual values
    @inline(__always) private static let decodeMap: [Int8] = {
        var map = [Int8](repeating: -1, count: 128)
        for (i, byte) in encodeAlphabet.enumerated() { map[Int(byte)] = Int8(i) }
        return map
    }()

    @inline(__always)
    public static func fromBytes(_ src: [UInt8]) -> String {
        var zeros = 0
        while zeros < src.count && src[zeros] == 0 { zeros += 1 }

        var b58 = [UInt8](repeating: 0,
                          count: (src.count - zeros) * 138 / 100 + 1) // log(256)/log(58)
        var length = 0

        for byte in src[zeros...] {
            var carry = Int(byte)
            var i = 0
            var j = b58.count - 1
            while j >= b58.count - length - 1 || carry != 0 {
                carry += 256 * Int(b58[j])
                b58[j] = UInt8(carry % 58)
                carry /= 58
                i += 1
                j -= 1
            }
            length = i
        }

        // Skip leading zeros in the base‑58 result
        var start = b58.count - length
        while start < b58.count && b58[start] == 0 { start += 1 }

        // Build the UTF‑8 bytes directly, then make a String once
        var outBytes = [UInt8](repeating: 0x31, count: zeros) // ASCII “1”
        outBytes.reserveCapacity(outBytes.count + (b58.count - start))
        for v in b58[start...] {
            outBytes.append(encodeAlphabet[Int(v)])
        }
        return String(decoding: outBytes, as: UTF8.self)
    }

    /// Reverse: Base‑58 string ➜ raw bytes
    @inline(__always)
    public static func toBytes(_ string: String) -> [UInt8] {
        let bytes = string.utf8

        // 1. Trim ASCII spaces
        var first = bytes.startIndex
        while first < bytes.endIndex && bytes[first] == 0x20 { first = bytes.index(after: first) }
        guard first < bytes.endIndex else { return [] }
        var last  = bytes.index(before: bytes.endIndex)
        while last > first && bytes[last] == 0x20 { last = bytes.index(before: last) }

        // 2. Count leading ‘1’s (zero bytes in output)
        var zeros = 0
        var p = first
        while p <= last && bytes[p] == 0x31 { zeros += 1; p = bytes.index(after: p) }

        // 3. Convert base‑58 ➜ base‑256
        let payloadLen = bytes.distance(from: p, to: bytes.index(after: last))
        let size       = payloadLen * 733 / 1000 + 1 // ⌈log(58)/log(256)⌉
        var b256       = [UInt8](repeating: 0, count: size)
        var length     = 0 // number of meaningful cells

        while p <= last {
            let ch = bytes[p]; p = bytes.index(after: p)
            guard ch < 0x80, decodeMap[Int(ch)] >= 0 else { return [] }

            var carry  = Int(decodeMap[Int(ch)])
            var i      = 0
            while carry != 0 || i < length { // ← **safe condition**
                let idx = b256.count - 1 - i // always ≥ 0
                carry += 58 * Int(b256[idx])
                b256[idx] = UInt8(carry & 0xFF)
                carry >>= 8
                i += 1
            }
            length = i
        }

        // 4. Skip leading zeros from the base‑256 buffer
        var start = b256.count - length
        while start < b256.count && b256[start] == 0 { start += 1 }

        // 5. Assemble final result
        var out = [UInt8](repeating: 0, count: zeros)
        out.reserveCapacity(out.count + (b256.count - start))
        out.append(contentsOf: b256[start...])
        return out
    }
}
*/
