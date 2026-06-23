//
//  RecipientContactAccessTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Contacts
import Testing
@testable import Flipcash

@Suite("Recipient contact access mapping")
struct RecipientContactAccessTests {

    @Test("Reachable authorization statuses map to the picker's access mode", arguments: [
        (CNAuthorizationStatus.authorized, RecipientContactAccess.full),
        (.limited, .limited),
        (.denied, .denied),
        (.restricted, .denied),
    ])
    func mapsReachableStatus(_ status: CNAuthorizationStatus, _ expected: RecipientContactAccess) {
        #expect(RecipientContactAccess(status) == expected)
    }

    @Test("notDetermined isn't picker-reachable — it routes to the priming screen")
    func notDeterminedIsNil() {
        #expect(RecipientContactAccess(.notDetermined) == nil)
    }
}
