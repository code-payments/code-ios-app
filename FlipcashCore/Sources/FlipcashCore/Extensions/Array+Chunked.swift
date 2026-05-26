//
//  Array+Chunked.swift
//  FlipcashCore
//

import Foundation

public extension Array {
    /// Splits the array into consecutive chunks of at most `size` elements.
    /// The final chunk may be smaller. Empty arrays produce an empty result.
    ///
    /// - Precondition: `size > 0`
    func chunked(into size: Int) -> [[Element]] {
        precondition(size > 0, "chunk size must be greater than 0")
        guard !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
