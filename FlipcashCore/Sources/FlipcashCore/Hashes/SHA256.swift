//
//  SHA256.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import SharedCoreKit

/// SHA-256, computed by the shared Kotlin implementation.
///
/// The shared side offers no streaming handle, and holding one across the framework
/// boundary would copy a byte array per update, so this buffers and hashes once at
/// `digestBytes()`. Every payload hashed here is small -- PDA seeds, conversation ids,
/// phone numbers -- so the buffer costs nothing worth optimising.
public struct SHA256: HashType {

    private var buffer = Data()

    public init() {}

    public mutating func update(_ data: Data) {
        buffer.append(data)
    }

    public func digestBytes() -> [Byte] {
        [Byte](SharedHash.sha256(buffer))
    }
}
