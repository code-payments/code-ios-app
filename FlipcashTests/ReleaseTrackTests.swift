//
//  ReleaseTrackTests.swift
//  FlipcashTests
//

import StoreKit
import Testing
@testable import Flipcash

@Suite("Release track shown in the version footer")
struct ReleaseTrackTests {

    @Test("A debug build is development, whatever StoreKit says", arguments: [nil, .sandbox, .production, .xcode] as [AppStore.Environment?])
    func debugIsDevelopment(environment: AppStore.Environment?) {
        #expect(ReleaseTrack.name(isDebug: true, environment: environment) == "development")
    }

    @Test("TestFlight is beta")
    func testFlightIsBeta() {
        #expect(ReleaseTrack.name(isDebug: false, environment: .sandbox) == "beta")
    }

    @Test("The App Store, an Xcode install, and an unknown environment show no track", arguments: [nil, .production, .xcode] as [AppStore.Environment?])
    func otherwiseNoTrack(environment: AppStore.Environment?) {
        #expect(ReleaseTrack.name(isDebug: false, environment: environment) == nil)
    }
}
