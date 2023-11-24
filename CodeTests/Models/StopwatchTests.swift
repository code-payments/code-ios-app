//
//  StopwatchTests.swift
//  CodeTests
//
//  Created by Dima Bart on 2021-12-10.
//

import XCTest
@testable import Code

class StopwatchTests: XCTestCase {
    
    func testSeconds() {
        let (timer, stopwatch) = stopwatch()
        XCTAssertEqual(stopwatch.measure(in: .seconds), 0)
        
        timer.time += 1
        XCTAssertEqual(stopwatch.measure(in: .seconds), 1)
        
        timer.time += 5
        XCTAssertEqual(stopwatch.measure(in: .seconds), 6)
        
        timer.time += 2
        XCTAssertEqual(stopwatch.measure(in: .seconds), 8)
    }
    
    func testMilliseconds() {
        let (timer, stopwatch) = stopwatch()
        XCTAssertEqual(stopwatch.measure(in: .milliseconds), 0)
        
        timer.time += 0.8
        let t1 = stopwatch.measure(in: .milliseconds)
        XCTAssertTrue(798 < t1 && t1 < 802)
        
        timer.time += 0.5
        let t2 = stopwatch.measure(in: .milliseconds)
        XCTAssertTrue(1298 < t2 && t2 < 1302)

        timer.time += 0.2
        let t3 = stopwatch.measure(in: .milliseconds)
        XCTAssertTrue(1498 < t3 && t3 < 1502)
    }
    
    func testFormatting() {
        let (timer, stopwatch) = stopwatch()
        timer.time += 0.8
        let string = stopwatch.measure(in: .milliseconds).formattedString()
        
        XCTAssertEqual(string, "0.80")
    }
    
    // MARK: - Abacus -
    
    @MainActor
    func testTiming() {
        let abacus = Abacus()
        let timer = Timer(time: 100)

        XCTAssertFalse(abacus.isTracking(.grabTime))
        
        abacus.start(.grabTime, time: timer.timeProvider)
        XCTAssertTrue(abacus.isTracking(.grabTime))
        
        XCTAssertEqual(abacus.snapshot(.grabTime)!.measure(in: .seconds), 0)
        XCTAssertTrue(abacus.isTracking(.grabTime))
        
        timer.time += 1
        XCTAssertEqual(abacus.snapshot(.grabTime)!.measure(in: .seconds), 1)
        XCTAssertTrue(abacus.isTracking(.grabTime))
        
        timer.time += 5
        XCTAssertEqual(abacus.snapshot(.grabTime)!.measure(in: .seconds), 6)
        XCTAssertTrue(abacus.isTracking(.grabTime))
        
        timer.time += 2
        XCTAssertEqual(abacus.end(.grabTime)!.measure(in: .seconds), 8)
        XCTAssertFalse(abacus.isTracking(.grabTime))
        
        XCTAssertNil(abacus.end(.grabTime))
    }
    
    // MARK: - Utilities -
    
    private func stopwatch() -> (timer: Timer, stopwatch: Stopwatch) {
        let timer = Timer(time: 100)
        let stopwatch = Stopwatch(time: timer.timeProvider)
        return (timer, stopwatch)
    }
}

// MARK: - Test Timer -

private class Timer {
    
    var time: TimeInterval
    
    init(time: TimeInterval) {
        self.time = time
    }
    
    func timeProvider() -> TimeInterval {
        time
    }
}
