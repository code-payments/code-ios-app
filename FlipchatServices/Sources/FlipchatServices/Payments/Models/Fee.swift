//
//  Fee.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Fee: Equatable, Hashable, Sendable {
    public var destination: PublicKey
    public var bps: Int
}
