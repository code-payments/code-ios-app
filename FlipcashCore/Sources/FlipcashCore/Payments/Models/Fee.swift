//
//  Fee.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-10.
//

import Foundation

public struct Fee: Equatable, Hashable, Sendable {
    public var destination: PublicKey
    public var bps: Int
}
