//
//  CNAuthorizationStatusTests.swift
//  FlipcashTests
//

import Contacts
import Testing
@testable import Flipcash

@Suite("CNAuthorizationStatus.allowsContactAccess")
struct CNAuthorizationStatusAllowsContactAccessTests {

    private static let cases: [(CNAuthorizationStatus, Bool)] = [
        (.authorized,    true),
        (.limited,       true),
        (.notDetermined, false),
        (.denied,        false),
        (.restricted,    false),
    ]

    @Test(
        "Only .authorized and .limited allow contact access",
        arguments: cases,
    )
    func allowsContactAccess(status: CNAuthorizationStatus, expected: Bool) {
        #expect(status.allowsContactAccess == expected)
    }
}
