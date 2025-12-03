//
//  Key+Comparable.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/1/25.
//
extension PublicKey: Comparable {
    public static func < (lhs: Key32, rhs: Key32) -> Bool {
        lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
    }
}
