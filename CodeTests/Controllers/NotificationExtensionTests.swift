//
//  NotificationExtensionTests.swift
//  CodeTests
//
//  Created by Dima Bart on 2023-04-14.
//

import XCTest
@testable import Code

class NotificationExtensionTests: XCTestCase {
    
    // MARK: - Login -
    
    func testWelcomeNotification() {
        let service = NotificationModifier()
        
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "chat_title": "title.chat.codeTeam",
            "message_content": "ChwKGnN1YnRpdGxlLmNoYXQud2VsY29tZUJvbnVz",
        ]
        
        let request = UNNotificationRequest(
            identifier: "123",
            content: content,
            trigger: nil
        )
        
        service.didReceive(request) { content in
            XCTAssertEqual(content.title, "Code Team")
            XCTAssertEqual(content.body, "Welcome to Code! Here is your first dollar to get you started:")
        }
    }
    
    func testAmountNotification() {
        let service = NotificationModifier()
        
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "chat_title": "title.chat.codeTeam",
            "message_content": "EhIIAhoOCgN1c2QRAAAAAAAA8D8",
        ]
        
        let request = UNNotificationRequest(
            identifier: "123",
            content: content,
            trigger: nil
        )
        
        service.didReceive(request) { content in
            XCTAssertEqual(content.title, "Code Team")
            XCTAssertEqual(content.body, "You received $1.00 of Kin")
        }
    }
}
