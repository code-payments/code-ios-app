//
//  RandomAccessCollection+Indexed.swift
//  Flipcash
//
//  Provides a `RandomAccessCollection`-conforming wrapper around `enumerated()`.
//
//  `EnumeratedSequence` only conforms to `Sequence`, so using it directly in
//  `ForEach` requires wrapping in `Array(...)` — allocating a new array each
//  time the view body is evaluated.
//
//  `indexed()` returns an `IndexedCollection` that conforms to
//  `RandomAccessCollection`, avoiding the allocation while providing
//  the same `(index, element)` pairs.
//
//  If Swift ever adds `RandomAccessCollection` conformance to
//  `EnumeratedSequence`, this file can be removed and all `.indexed()`
//  call sites replaced with `.enumerated()`.
//

import Foundation

/// A pair of a zero-based index and its corresponding collection element.
nonisolated struct IndexedElement<Element> {
    let index: Int
    let element: Element
}

/// A `RandomAccessCollection` that pairs each element of a base collection
/// with its zero-based integer index — equivalent to `enumerated()` but
/// usable directly in `ForEach`.
nonisolated struct IndexedCollection<Base: RandomAccessCollection>: RandomAccessCollection {
    let base: Base

    var startIndex: Base.Index { base.startIndex }
    var endIndex: Base.Index { base.endIndex }

    subscript(position: Base.Index) -> IndexedElement<Base.Element> {
        let offset = base.distance(from: base.startIndex, to: position)
        return IndexedElement(index: offset, element: base[position])
    }

    func index(after i: Base.Index) -> Base.Index {
        base.index(after: i)
    }

    func index(before i: Base.Index) -> Base.Index {
        base.index(before: i)
    }
}

extension RandomAccessCollection {
    /// Returns an `IndexedCollection` that pairs each element with its
    /// zero-based index, conforming to `RandomAccessCollection`.
    ///
    /// Use this instead of `Array(collection.enumerated())` in `ForEach`
    /// to avoid per-evaluation array allocations.
    func indexed() -> IndexedCollection<Self> {
        IndexedCollection(base: self)
    }
}
