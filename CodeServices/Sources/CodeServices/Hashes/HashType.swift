//
//  HashType.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public protocol HashType {
    init()
    mutating func update(_ data: Data)
    func digestBytes() -> [Byte]
}

public extension HashType {
    mutating func update(_ UTF8String: String) {
        update(Data(UTF8String.utf8))
    }
    
    func digestData() -> Data {
        Data(digestBytes())
    }
}

public extension HashType {
    static func digest(_ string: String) -> Data {
        digest(Data(string.utf8))
    }
    
    static func digest(_ data: Data) -> Data {
        var hash = Self.init()
        hash.update(data)
        return hash.digestData()
    }
}
