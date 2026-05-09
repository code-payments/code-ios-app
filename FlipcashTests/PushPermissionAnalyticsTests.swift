//
//  PushPermissionAnalyticsTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import UserNotifications
@testable import Flipcash

@Suite("Push Permission Analytics")
struct PushPermissionAnalyticsTests {

    @Test(
        "previousIfDenied returns previous only on transition into .denied",
        arguments: [
            (UNAuthorizationStatus?.none,         UNAuthorizationStatus.denied,        UNAuthorizationStatus?.none),
            (.some(.authorized),                  .authorized,                         nil),
            (.some(.authorized),                  .denied,                             .authorized),
            (.some(.notDetermined),               .denied,                             .notDetermined),
            (.some(.provisional),                 .denied,                             .provisional),
            (.some(.denied),                      .authorized,                         nil),
            (.some(.denied),                      .notDetermined,                      nil),
            (.some(.authorized),                  .provisional,                        nil),
        ] as [(UNAuthorizationStatus?, UNAuthorizationStatus, UNAuthorizationStatus?)]
    )
    func previousIfDenied(
        previous: UNAuthorizationStatus?,
        current: UNAuthorizationStatus,
        expected: UNAuthorizationStatus?
    ) {
        #expect(current.previousIfDenied(from: previous) == expected)
    }

    @Test(
        "analyticsName covers every known UNAuthorizationStatus case",
        arguments: [
            (UNAuthorizationStatus.notDetermined, "notDetermined"),
            (.denied,                             "denied"),
            (.authorized,                         "authorized"),
            (.provisional,                        "provisional"),
            (.ephemeral,                          "ephemeral"),
        ]
    )
    func analyticsName(status: UNAuthorizationStatus, expected: String) {
        #expect(status.analyticsName == expected)
    }
}
