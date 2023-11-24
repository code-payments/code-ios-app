//
//  Types.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public typealias Seed16     = Key16

public typealias PublicKey  = Key32
public typealias Seed32     = Key32
public typealias Hash       = Key32

public typealias PrivateKey = Key64
public typealias Signature  = Key64

extension Key32 {
    public static let mock = Key32(base58: "EBDRoayCDDUvDgCimta45ajQeXbexv7aKqJubruqpyvu")!
}

extension Key64 {
    public static let mock = Key64(base58: "5WuSx6eLmz26LxLzeaAKabtQ9xTpFjjEo8v2rCWHsAcxnGxmLuSav5rgb1JfWqXP2SaqtjLPUNBEXYTfGYdufjmt")!
}
