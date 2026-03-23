//
//  IndexedCollectionTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@Suite("IndexedCollection")
struct IndexedCollectionTests {

    @Test("produces the same index-element pairs as Array(enumerated())")
    func matchesEnumerated() throws {
        let items = ["a", "b", "c", "d"]

        let fromEnumerated = Array(items.enumerated()).map { (index: $0.offset, element: $0.element) }
        let fromIndexed = items.indexed().map { (index: $0.index, element: $0.element) }

        try #require(fromEnumerated.count == fromIndexed.count)
        for (enumerated, indexed) in zip(fromEnumerated, fromIndexed) {
            #expect(enumerated.index == indexed.index)
            #expect(enumerated.element == indexed.element)
        }
    }

    @Test("empty collection produces no elements")
    func emptyCollection() {
        let items: [String] = []
        let indexed = Array(items.indexed())
        #expect(indexed.isEmpty)
    }

    @Test("single element has index zero")
    func singleElement() throws {
        let items = ["only"]
        let indexed = Array(items.indexed())

        try #require(indexed.count == 1)
        #expect(indexed[0].index == 0)
        #expect(indexed[0].element == "only")
    }

    @Test("indices are sequential starting from zero")
    func sequentialIndices() {
        let items = [10, 20, 30, 40, 50]
        let indices = items.indexed().map(\.index)
        #expect(indices == [0, 1, 2, 3, 4])
    }

    @Test("elements preserve original order")
    func preservesOrder() {
        let items = ["z", "a", "m"]
        let elements = items.indexed().map(\.element)
        #expect(elements == ["z", "a", "m"])
    }

    @Test("works with array slices")
    func arraySlice() throws {
        let items = [10, 20, 30, 40, 50]
        let slice = items[2...4] // [30, 40, 50]
        let indexed = Array(slice.indexed())

        try #require(indexed.count == 3)
        #expect(indexed[0].index == 0)
        #expect(indexed[0].element == 30)
        #expect(indexed[1].index == 1)
        #expect(indexed[1].element == 40)
        #expect(indexed[2].index == 2)
        #expect(indexed[2].element == 50)
    }
}
