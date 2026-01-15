//
//  Message.Version.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/2/25.
//

internal let messageVersionSerializationOffset: UInt8 = 127

public enum MessageVersion: UInt8 {
    case legacy = 0
    case v0 = 1
}
