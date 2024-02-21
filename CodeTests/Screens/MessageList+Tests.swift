//
//  MessageList+Tests.swift
//  CodeTests
//
//  Created by Dima Bart on 2024-02-21.
//

import XCTest
import CodeServices
@testable import Code

class MessageListTests: XCTestCase {
    
    func testMessageGrouping() {
        let date = Date(timeIntervalSince1970: 1708542000) // Some date at 2pm EST
        let dates = [
            date.adding(hours: -1),  // 1pm
            date.adding(hours: -2),  // 12pm
            date.adding(hours: -3),  // 11am
            date.adding(hours: -4),  // 10am
            date.adding(hours: -5),  // 9am
            date.adding(hours: -6),  // 8am
            date.adding(hours: -7),  // 7am
            date.adding(hours: -8),  // 6am
            date.adding(hours: -9),  // 5am
            date.adding(hours: -10), // 4am
            date.adding(hours: -11), // 3am
            date.adding(hours: -12), // 2am
            date.adding(hours: -13), // 1am
            date.adding(hours: -14), // 12am ----- Day -----
            date.adding(hours: -15), // 11pm
            date.adding(hours: -16), // 10pm
            date.adding(hours: -17), // 9pm
            date.adding(hours: -18), // 8pm
            date.adding(hours: -19), // 7pm
            date.adding(hours: -20), // 6pm
            date.adding(hours: -21), // 5pm
            date.adding(hours: -22), // 4pm
            date.adding(hours: -23), // 3pm
            date.adding(hours: -24), // 2pm
            date.adding(hours: -25), // 1pm
            date.adding(hours: -26), // 12pm
            date.adding(hours: -27), // 11am
            date.adding(hours: -28), // 10am
            date.adding(hours: -29), // 9am
            date.adding(hours: -30), // 8am
            date.adding(hours: -31), // 7am
            date.adding(hours: -32), // 6am
            date.adding(hours: -33), // 5am
            date.adding(hours: -34), // 4am
            date.adding(hours: -35), // 3am
            date.adding(hours: -36), // 2am
            date.adding(hours: -37), // 1am
            date.adding(hours: -38), // 12am ----- Day -----
            date.adding(hours: -39), // 11pm
            date.adding(hours: -40), // 10pm
        ]
        
        let messages = dates.map {
            Chat.Message(
                id: .random,
                date: $0,
                contents: []
            )
        }
        
        let groups = messages.groupByDay()
        
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].messages.count, 2)
        XCTAssertEqual(groups[1].messages.count, 24)
        XCTAssertEqual(groups[2].messages.count, 14)
    }
}
