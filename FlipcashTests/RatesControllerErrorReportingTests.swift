//
//  RatesControllerErrorReportingTests.swift
//  Flipcash
//
//  The tip-deeplink "Rate Unavailable" breadcrumb records `exchangeRateUnavailable`.
//  It must classify `.info` — a self-healing cold-start rate race is worth visibility
//  but must never page Slack. Guards against a drift to `.error`.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("RatesController.Error reporting level")
struct RatesControllerErrorReportingTests {

    @Test("exchangeRateUnavailable reports at .info (breadcrumb, never a Slack page)")
    func exchangeRateUnavailableIsInfo() {
        #expect(RatesController.Error.exchangeRateUnavailable.reportingLevel == .info)
    }
}
