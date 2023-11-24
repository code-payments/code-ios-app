//
//  DerivedKey.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct DerivedKey: Codable, Equatable, Hashable {
    
    public var path: Derive.Path
    public var keyPair: KeyPair
    
    // MARK: - Init -
    
    public init(path: Derive.Path, keyPair: KeyPair) {
        self.path = path
        self.keyPair = keyPair
    }
}

extension DerivedKey {
    public static func derive(using path: Derive.Path, mnemonic: MnemonicPhrase) -> DerivedKey {
        self.init(
            path: path,
            keyPair: KeyPair(mnemonic: mnemonic, path: path)
        )
    }
}
