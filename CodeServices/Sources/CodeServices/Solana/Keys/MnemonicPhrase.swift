//
//  MnemonicPhrase.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct MnemonicPhrase: Codable, Equatable, Hashable {
    
    public let kind: Kind
    public let words: [String]
    
    public var phrase: String {
        words.joined(separator: " ")
    }
    
    public init?(words: [String]) {
        switch words.count {
        case 12:
            self.kind = .words12
        case 24:
            self.kind = .words24
        default:
            return nil
        }
        
        guard let _ = try? Mnemonic.toEntropy(words) else {
            // Validates the words
            return nil
        }
        
        self.words = words
    }
}

extension MnemonicPhrase {
    public func solanaKeyPair() -> KeyPair {
        KeyPair(mnemonic: self, path: .solana)
    }
}

// MARK: - Generate -

extension MnemonicPhrase {
    public static func generate(_ kind: Kind) -> MnemonicPhrase {
        switch kind {
        case .words12:
            return Seed16.generate()!.mnemonic
        case .words24:
            return Seed32.generate()!.mnemonic
        }
    }
}

// MARK: - Base64 -

extension MnemonicPhrase {
    
    public var base64EncodedEntropy: String {
        let entropy = try! Mnemonic.toEntropy(words)
        return entropy.data.base64EncodedString()
    }
    
    public init?(base64EncodedEntropy: String) {
        guard let data = Data(base64Encoded: base64EncodedEntropy) else {
            return nil
        }
        
        guard let words = try? Mnemonic.toMnemonic(data.bytes) else {
            return nil
        }
        
        self.init(words: words)
    }
}

// MARK: - Base58 -

extension MnemonicPhrase {
    
    public var base58EncodedEntropy: String {
        let entropyBytes = try! Mnemonic.toEntropy(words)
        switch kind {
        case .words12:
            return Key16(entropyBytes)!.base58
        case .words24:
            return Key32(entropyBytes)!.base58
        }
    }
    
    public init?(base58EncodedEntropy: String) {
        let entropyBytes = (Key32(base58: base58EncodedEntropy)?.bytes ?? Key16(base58: base58EncodedEntropy)?.bytes) ?? []
        
        guard !entropyBytes.isEmpty else {
            return nil
        }
        
        guard let words = try? Mnemonic.toMnemonic(entropyBytes) else {
            return nil
        }
        
        self.init(words: words)
    }
}

// MARK: - Kind -

extension MnemonicPhrase {
    public enum Kind: Codable, Equatable, Hashable {
        case words12
        case words24
    }
}

