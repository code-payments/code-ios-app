//
//  ConnectionFailureDialogTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Connection failure dialogs")
struct ConnectionFailureDialogTests {

    private let fallback = DialogItem.error(
        title: "Couldn't Send",
        subtitle: "We couldn't reach the network. Please try again."
    )

    private func path(
        _ status: NetworkPathState.Status,
        reason: NetworkPathState.UnsatisfiedReason?
    ) -> NetworkPathState {
        NetworkPathState(
            status: status,
            unsatisfiedReason: reason,
            interfaces: [],
            isExpensive: false,
            isConstrained: false,
            supportsIPv4: true,
            supportsIPv6: true,
            supportsDNS: true
        )
    }

    @Test("A cellular-denied path names the switch and links to Settings")
    func cellularDenied_pointsAtSettings() {
        let item = DialogItem.connectionFailure(fallback, path: path(.unsatisfied, reason: .cellularDenied))
        #expect(item.title == "Couldn't Send")
        #expect(item.subtitle?.contains("Cellular data is turned off for Flipcash") == true)
        #expect(item.actions.map(\.title).first == "Open Settings")
    }

    @Test("Any other unsatisfied path keeps the caller's dialog", arguments: [
        NetworkPathState.UnsatisfiedReason.notAvailable,
        .wifiDenied,
        .localNetworkDenied,
        .vpnInactive,
        .unknown,
    ])
    func otherReasons_keepFallback(reason: NetworkPathState.UnsatisfiedReason) {
        let item = DialogItem.connectionFailure(fallback, path: path(.unsatisfied, reason: reason))
        #expect(item.id == fallback.id)
    }

    @Test("A satisfied path keeps the caller's dialog")
    func satisfied_keepsFallback() {
        let item = DialogItem.connectionFailure(fallback, path: .unknown)
        #expect(item.id == fallback.id)
    }
}
