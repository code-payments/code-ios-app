//
//  SHA512.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import SharedCoreKit

/// SHA-512, computed by the shared Kotlin implementation. See `SHA256` for why this
/// buffers rather than streaming.
public struct SHA512: HashType {

    private var buffer = Data()

    public init() {}

    public mutating func update(_ data: Data) {
        buffer.append(data)
    }

    public func digestBytes() -> [Byte] {
        [Byte](SharedHash.sha512(buffer))
    }
}
