//
//  Data+SliceTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

import XCTest
@testable import CodeServices

final class DataSliceTests: XCTestCase {
 
    // MARK: - Consume -
    
    func testConsumeSubdata() {
        var data = Data([1, 2, 3, 4, 5])
        let slice  = data.consume(2)
        
        XCTAssertEqual(slice, Data([1, 2]))
        XCTAssertEqual(data, Data([3, 4, 5]))
        
        XCTAssertEqual(data.startIndex, 0)
        XCTAssertEqual(slice.startIndex, 0)
    }
    
    func testConsumeFull() {
        var data = Data([1, 2, 3, 4, 5])
        let slice  = data.consume(5)
        
        XCTAssertEqual(slice, Data([1, 2, 3, 4, 5]))
        XCTAssertEqual(data, Data())
        
        XCTAssertEqual(data.startIndex, 0)
        XCTAssertEqual(slice.startIndex, 0)
    }
    
    func testConsumeOverflow() {
        var data = Data([1, 2, 3, 4, 5])
        let slice  = data.consume(10)
        
        XCTAssertEqual(slice, Data([1, 2, 3, 4, 5]))
        XCTAssertEqual(data, Data())
        
        XCTAssertEqual(data.startIndex, 0)
        XCTAssertEqual(slice.startIndex, 0)
    }
    
    func testConsumeZero() {
        var data = Data([1, 2, 3, 4, 5])
        let slice  = data.consume(0)
        
        XCTAssertEqual(slice, Data())
        XCTAssertEqual(data, Data([1, 2, 3, 4, 5]))
        
        XCTAssertEqual(data.startIndex, 0)
        XCTAssertEqual(slice.startIndex, 0)
    }
    
    // MARK: - Tail -
    
    func testTailSubdata() {
        let data = Data([1, 2, 3, 4, 5])
        let slice  = data.tail(from: 2)
        
        XCTAssertEqual(slice, Data([3, 4, 5]))
        XCTAssertEqual(slice.startIndex, 0)
    }
    
    func testTailFromEnd() {
        let data = Data([1, 2, 3, 4, 5])
        let slice  = data.tail(from: 5)
        
        XCTAssertEqual(slice, Data())
        XCTAssertEqual(slice.startIndex, 0)
    }
    
    func testTailOverflow() {
        let data = Data([1, 2, 3, 4, 5])
        let slice  = data.tail(from: 10)
        
        XCTAssertEqual(slice, Data())
        XCTAssertEqual(slice.startIndex, 0)
    }
    
    func testTailFromZero() {
        let data = Data([1, 2, 3, 4, 5])
        let slice  = data.tail(from: 0)
        
        XCTAssertEqual(slice, Data([1, 2, 3, 4, 5]))
        XCTAssertEqual(slice.startIndex, 0)
    }
    
    // MARK: - Chunk -
    
    func testChunkValid() throws {
        let data = [
            0x11, 0x22, 0x33, 0x44,
            0x55, 0x66, 0x77, 0x88,
        ].data
        
        let doubles = try XCTUnwrap(data.chunk(size: 2, count: 4) {
            (one: $0.bytes[0], two: $0.bytes[1])
        })
        
        XCTAssertEqual(doubles.count, 4)
        XCTAssertEqual(doubles[1].one, 0x33)
        XCTAssertEqual(doubles[1].two, 0x44)
        
        let quads = try XCTUnwrap(data.chunk(size: 4, count: 2) {
            (one: $0.bytes[0], two: $0.bytes[1], three: $0.bytes[2], four: $0.bytes[3])
        })
        
        XCTAssertEqual(quads.count, 2)
        XCTAssertEqual(quads[1].one,   0x55)
        XCTAssertEqual(quads[1].two,   0x66)
        XCTAssertEqual(quads[1].three, 0x77)
        XCTAssertEqual(quads[1].four,  0x88)
    }
    
    func testChunkInvalidSize() {
        let data = [
            0x11, 0x22, 0x33, 0x44,
            0x55, 0x66, 0x77, 0x88,
        ].data
        
        let doubles = data.chunk(size: 2, count: 6, block: { $0 })
        XCTAssertNil(doubles)
        
        let triples = data.chunk(size: 3, count: 3, block: { $0 })
        XCTAssertNil(triples)
        
        let quads = data.chunk(size: 4, count: 3, block: { $0 })
        XCTAssertNil(quads)
    }
}
