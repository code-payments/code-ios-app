//
//  SharedTrackTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Shared event send path", .serialized)
struct SharedTrackTests {

    @Test("Scalars reach Mixpanel as their own types")
    func scalarsKeepTheirTypes() throws {
        let sent = Analytics.recordingSends {
            Analytics.track(ScanEvents.shared.galleryFailed(timeMillis: 1500, exhausted: true))
        }
        let event = try sent.single
        #expect(event.name == "Gallery Scan: Failed")
        #expect(event.properties["Time"] as? Double == 1500)
        #expect(event.properties["Exhausted"] as? Bool == true)
    }

    @Test("Text reaches Mixpanel as a string")
    func textIsAString() throws {
        let sent = Analytics.recordingSends {
            Analytics.track(DeeplinkEvents.shared.open(url: "https://app.flipcash.com/c"))
        }
        #expect(try sent.single.properties["URL"] as? String == "https://app.flipcash.com/c")
    }

    @Test("An error uses the iOS format")
    func errorFormat() throws {
        let error = NSError(domain: "D", code: 7)
        let sent = Analytics.recordingSends {
            Analytics.track(ChatEvents.shared.sentMessage(chatType: .group, error: nil), error: error)
        }
        #expect(try sent.single.properties["Error"] as? String == "D.\(error):7")
    }

    @Test("A mint gains its token symbol")
    func tokenSymbol() throws {
        let previous = Analytics.tokenSymbolResolver
        Analytics.tokenSymbolResolver = { $0 == "M" ? "ABC" : nil }
        defer { Analytics.tokenSymbolResolver = previous }

        let sent = Analytics.recordingSends {
            Analytics.track(AddMoneyEvents.shared.addressCopied(mint: "M"))
        }
        let event = try sent.single
        #expect(event.properties["Mint"] as? String == "M")
        #expect(event.properties["Token Symbol"] as? String == "ABC")
    }
}
