//
//  Key+Mnemonic.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension KeyType {
    
    public var mnemonic: MnemonicPhrase {
        let words = try! Mnemonic.toMnemonic(bytes)
        return MnemonicPhrase(words: words)!
    }
    
    public init?(mnemonic: MnemonicPhrase) {
        guard let bytes = try? Mnemonic.toEntropy(mnemonic.words) else {
            return nil
        }
        
        self.init(bytes)
    }
}
