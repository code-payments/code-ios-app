//
//  Mnemonic.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

/// Mnemonic conversion to and from binary entropy
/// Reference: https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki
///
public enum Mnemonic {
    
    public static func toMnemonic(_ entropy: [UInt8], language: Language = .english) throws -> [String] {
        let (checksum, csBits) = try calculateChecksum(entropy)
        
        var bytes = [UInt8]()
        bytes.reserveCapacity(entropy.count + 1)
        bytes.append(contentsOf: entropy)
        bytes.append(checksum << (8 - csBits))
        
        var phrase = [String]()
        phrase.reserveCapacity((bytes.count * 8 + csBits) / 11)
        
        var hBits = (UInt16(bytes[0]) << 3), hBitsCount: UInt8 = 8
        
        bytes.withUnsafeBufferPointer { ptr in
            for byte in ptr.suffix(from: 1) {
                let remainderBitsCount = Int8(hBitsCount) - 3
                if remainderBitsCount >= 0 {
                    let index = Int(hBits + (UInt16(byte) >> remainderBitsCount))
                    hBits = UInt16(byte << (8 - remainderBitsCount)) << 3
                    hBitsCount = UInt8(remainderBitsCount)
                    phrase.append(language.word(for: index))
                } else {
                    hBits = hBits + (UInt16(byte) << abs(Int32(remainderBitsCount)))
                    hBitsCount += 8
                }
            }
        }
        
        return phrase
    }
    
    public static func toEntropy(_ words: [String], language: Language = .english) throws -> [UInt8] {
        guard words.count > 0, words.count <= 24, words.count % 3 == 0 else {
            throw Error.invalidMnemonic
        }
        
        var hBits: UInt8 = 0
        var hBitsCount: UInt8 = 0
        var bytes = [UInt8]()
        bytes.reserveCapacity(Int((Float(words.count) * 10.99) / 8) + 1)
        
        for word in words {
            guard let index = language.index(for: word) else {
                throw Error.invalidMnemonic
            }
            
            let remainderCount = hBitsCount + 3
            bytes.append(hBits + UInt8(index >> remainderCount))
            
            if remainderCount >= 8 {
                hBitsCount = remainderCount - 8
                bytes.append(UInt8(truncatingIfNeeded: index >> hBitsCount))
            } else {
                hBitsCount = remainderCount
            }
            
            hBits = UInt8(truncatingIfNeeded: index << (8 - hBitsCount))
        }
        
        if words.count < 24 {
            bytes.append(hBits)
        }
        
        let checksum = bytes.last!
        let entropy: [UInt8] = bytes.dropLast()
        let calculated = try calculateChecksum(entropy)
        
        guard checksum == (calculated.checksum << (8 - calculated.bits)) else {
            throw Error.invalidMnemonic
        }
        
        return entropy
    }
    
    // Calculate checksum
    private static func calculateChecksum(_ entropy: [UInt8]) throws -> (checksum: UInt8, bits: Int) {
        guard entropy.count > 0, entropy.count <= 32, entropy.count % 4 == 0 else {
            throw Error.invalidEntropy
        }
        
        let size = entropy.count / 4 // Calculate checksum size.
        let hash = SHA256.digest(entropy.data)
        return (hash[0] >> (8 - size), size)
    }
}

// MARK: - Error -

extension Mnemonic {
    public enum Error: Swift.Error {
        case invalidMnemonic
        case invalidStrengthSize
        case invalidEntropy
    }
}
