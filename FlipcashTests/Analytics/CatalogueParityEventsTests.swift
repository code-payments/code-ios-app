//
//  CatalogueParityEventsTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// Catalogue events iOS sends to match Android, written as the catalogue spells them.
@MainActor
@Suite("Catalogue parity events", .serialized)
struct CatalogueParityEventsTests {

    init() {
        Analytics.tokenSymbolResolver = nil
    }

    private static let fiat = ExchangedFiat.compute(
        onChainAmount: TokenAmount(quarks: 5_000_000, mint: .usdf),
        rate: Rate(fx: 1, currency: .usd),
        supplyQuarks: nil
    )

    // MARK: - Buttons and onramp -

    @Test("Buy With Coinbase and Buy With Phantom buttons", arguments: [
        (Analytics.ButtonEvent.buyWithCoinbase, "Button: Buy With Coinbase"),
        (.buyWithPhantom, "Button: Buy With Phantom"),
    ])
    func buyWithButtons(_ button: Analytics.ButtonEvent, _ expected: String) throws {
        let event = try Analytics.recordingSends { Analytics.buttonTapped(name: button) }.single
        #expect(event.name == expected)
    }

    @Test("The verification intro is Onramp: Show Verification Info")
    func onrampShowInfo() throws {
        let event = try Analytics.recordingSends { Analytics.onrampStep(.showInfo) }.single
        #expect(event.name == "Onramp: Show Verification Info")
    }

    // MARK: - Token Purchase With Coinbase -

    @Test("A placed Coinbase order is Token Purchase With Coinbase, with the mint and amount")
    func coinbasePurchase() throws {
        let event = try Analytics.recordingSends {
            CoinbaseDepositOperation.trackPurchase(Self.fiat, error: nil)
        }.single
        #expect(event.name == "Token Purchase With Coinbase")
        #expect(event.properties["Mint"] as? String == PublicKey.usdf.base58)
        #expect(event.properties["Fiat"] as? Double == 5)
        #expect(event.properties["USDC"] as? Double == 5)
        #expect(event.properties["Quarks"] as? Double == 5_000_000)
        #expect(event.properties["Currency"] != nil)
        #expect(event.properties["Error"] == nil)
    }

    @Test("A failed Coinbase order carries the error")
    func coinbasePurchaseFailed() throws {
        let event = try Analytics.recordingSends {
            CoinbaseDepositOperation.trackPurchase(Self.fiat, error: NSError(domain: "D", code: 7))
        }.single
        #expect(event.name == "Token Purchase With Coinbase")
        #expect(event.properties["Error"] != nil)
    }

    @Test("A cancel or a missing contact sends no Token Purchase")
    func coinbasePurchaseSkipped() {
        let cancelled = Analytics.recordingSends {
            CoinbaseDepositOperation.trackPurchase(Self.fiat, error: CancellationError())
        }
        #expect(cancelled.isEmpty)

        let unverified = Analytics.recordingSends {
            CoinbaseDepositOperation.trackPurchase(Self.fiat, error: DepositError.requirementUnsatisfied(.verifiedContact))
        }
        #expect(unverified.isEmpty)
    }

    // MARK: - Deeplink: Parse failure -

    @Test("A scanned non-Flipcash code is Deeplink: Parse with the stripped URL as the Error")
    func parseFailed() throws {
        let url = URL(string: "https://google.com/search?q=secret#frag")!
        let event = try Analytics.recordingSends { Analytics.deeplinkParseFailed(url: url) }.single
        #expect(event.name == "Deeplink: Parse")
        #expect(event.properties["Error"] as? String == "Failed to parse deeplink => https://google.com/search")
    }

    @Test("Only a code that is no Flipcash route counts as unparseable", arguments: [
        ("https://google.com", true),
        ("https://evil.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW", true),
        ("https://app.flipcash.com/token/54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25", false),
        ("https://app.flipcash.com/login#e=HQPkfAZjgpGGANQfUNPKvW", false),
    ])
    func unparseable(_ string: String, _ expected: Bool) {
        #expect(ScanViewModel.isUnparseableQR(url: URL(string: string)!) == expected)
    }
}
