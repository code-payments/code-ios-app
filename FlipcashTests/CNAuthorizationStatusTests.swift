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

@Suite("CNAuthorizationStatus.isLimited")
struct CNAuthorizationStatusIsLimitedTests {

    private static let cases: [(CNAuthorizationStatus, Bool)] = [
        (.limited,       true),
        (.authorized,    false),
        (.notDetermined, false),
        (.denied,        false),
        (.restricted,    false),
    ]

    @Test(
        "isLimited is true only for .limited",
        arguments: cases,
    )
    func isLimited(status: CNAuthorizationStatus, expected: Bool) {
        #expect(status.isLimited == expected)
    }
}
