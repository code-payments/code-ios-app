//
//  QueueTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

@MainActor
class QueueTests: XCTestCase {
    
    func testQueueBlocked() {
        let queue = Queue(isBlocked: true)
        var counter = 0
        
        queue.enqueue { counter += 1 }
        queue.enqueue { counter += 1 }
        
        XCTAssertEqual(counter, 0)
    }
    
    func testQueueUnblocked() {
        let queue = Queue(isBlocked: false)
        var counter = 0
        
        queue.enqueue { counter += 1 }
        queue.enqueue { counter += 1 }
        
        XCTAssertEqual(counter, 2)
    }
    
    func testQueueFulfills() {
        let queue = Queue(isBlocked: true)
        var counter = 0
        
        queue.enqueue { counter += 1 }
        queue.enqueue { counter += 1 }
        
        XCTAssertEqual(counter, 0)
        
        queue.setUnblocked()
        XCTAssertEqual(counter, 2)
    }
    
    func testQueueComprehensive() {
        let queue = Queue(isBlocked: false)
        var counter = 0
        
        queue.enqueue {
            counter += 1
        }
        
        XCTAssertEqual(counter, 1)
        
        queue.setBlocked()
        
        queue.enqueue { counter += 1 }
        queue.enqueue { counter += 1 }
        queue.enqueue { counter += 1 }
        
        XCTAssertEqual(counter, 1)
        
        queue.setUnblocked()
        
        XCTAssertEqual(counter, 4)
        
        queue.enqueue { counter += 1 }
        queue.enqueue { counter += 1 }
        
        XCTAssertEqual(counter, 6)
    }
}
