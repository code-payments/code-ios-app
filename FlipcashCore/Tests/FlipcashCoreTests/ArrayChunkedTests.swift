//
//  ArrayChunkedTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import FlipcashCore

@Suite("Array.chunked")
struct ArrayChunkedTests {

    @Test("empty array produces empty chunks")
    func empty() {
        let result: [[Int]] = [].chunked(into: 5)
        #expect(result == [])
    }

    @Test("single element produces one chunk of one")
    func singleElement() {
        #expect([1].chunked(into: 5) == [[1]])
    }

    @Test("count less than size produces one full chunk")
    func underBatch() {
        #expect([1, 2, 3].chunked(into: 5) == [[1, 2, 3]])
    }

    @Test("count exactly batch size produces one chunk")
    func exactlyBatch() {
        #expect([1, 2, 3, 4, 5].chunked(into: 5) == [[1, 2, 3, 4, 5]])
    }

    @Test("count over batch size produces last chunk with remainder")
    func partialLastChunk() {
        #expect([1, 2, 3, 4, 5].chunked(into: 3) == [[1, 2, 3], [4, 5]])
    }

    @Test("exact multiple of batch size produces equal chunks")
    func exactMultiple() {
        #expect([1, 2, 3, 4, 5, 6].chunked(into: 2) == [[1, 2], [3, 4], [5, 6]])
    }

    @Test("chunk size of one produces one chunk per element")
    func chunkSizeOne() {
        #expect([1, 2, 3].chunked(into: 1) == [[1], [2], [3]])
    }

    @Test("chunked preserves element order")
    func preservesOrder() {
        let phones = ["+15551111", "+15552222", "+15553333", "+15554444"]
        #expect(phones.chunked(into: 2) == [
            ["+15551111", "+15552222"],
            ["+15553333", "+15554444"],
        ])
    }

    @Test("contact-sync batch size of 1000 holds for a realistic full upload")
    func contactSyncBatchSize() {
        let phones = (1...2500).map { "+155555\($0)" }
        let chunks = phones.chunked(into: 1000)

        #expect(chunks.count == 3)
        #expect(chunks[0].count == 1000)
        #expect(chunks[1].count == 1000)
        #expect(chunks[2].count == 500)
        #expect(chunks.flatMap { $0 } == phones)
    }
}
