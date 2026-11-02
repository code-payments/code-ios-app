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

    // MARK: - Amount block -

    /// The catalogue's `amount` group for `fiat`: Fiat, Currency, USDC, Quarks, Exchange Rate, Mint.
    private func expectAmount(_ event: SentEvent, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(event.properties["Fiat"] as? Double == 5, sourceLocation: sourceLocation)
        #expect(event.properties["Currency"] as? String == "usd", sourceLocation: sourceLocation)
        #expect(event.properties["USDC"] as? Double == 5, sourceLocation: sourceLocation)
        #expect(event.properties["Quarks"] as? Double == 5_000_000, sourceLocation: sourceLocation)
        #expect(event.properties["Exchange Rate"] as? Double == 1, sourceLocation: sourceLocation)
        #expect(event.properties["Mint"] as? String == PublicKey.usdf.base58, sourceLocation: sourceLocation)
    }

    @Test("Transfer outcomes carry State and the amount group", arguments: [
        (Analytics.TransferEvent.withdrawal, "Withdrawal"),
        (.sentTip, "Sent Tip"),
        (.sendCashLink, "Send Cash Link"),
        (.receiveCashLink, "Receive Cash Link"),
        (.grabBill, "Grab Bill"),
        (.giveBill, "Give Bill"),
    ])
    func transferAmount(_ event: Analytics.TransferEvent, _ expected: String) throws {
        let sent = try Analytics.recordingSends {
            Analytics.transfer(event: event, exchangedFiat: Self.fiat, grabTime: nil, successful: true, error: nil)
        }.single
        #expect(sent.name == expected)
        #expect(sent.properties["State"] as? String == "Success")
        expectAmount(sent)
    }

    @Test("Withdrawal carries the amount group")
    func withdrawal() throws {
        let sent = try Analytics.recordingSends {
            Analytics.withdrawal(exchangedFiat: Self.fiat, successful: true, error: nil)
        }.single
        #expect(sent.name == "Withdrawal")
        expectAmount(sent)
    }

    @Test("Grab Bill sends Grab Time in ms")
    func grabTime() throws {
        let sent = try Analytics.recordingSends {
            Analytics.transfer(event: .grabBill, exchangedFiat: Self.fiat, grabTime: 1.25, successful: true, error: nil)
        }.single
        #expect(sent.properties["Grab Time"] as? Double == 1250)
    }

    @Test("A failed grab with only the fiat sends Fiat, Currency, USDC and Quarks")
    func grabFailedFiatOnly() throws {
        let sent = try Analytics.recordingSends {
            Analytics.transfer(event: .grabBill, fiat: Self.fiat.nativeAmount, successful: false, error: NSError(domain: "D", code: 1))
        }.single
        #expect(sent.properties["State"] as? String == "Failure")
        #expect(sent.properties["Fiat"] as? Double == 5)
        #expect(sent.properties["USDC"] as? Double == 5)
        #expect(sent.properties["Quarks"] as? Double == 5_000_000)
        #expect(sent.properties["Exchange Rate"] == nil)
        #expect(sent.properties["Error"] != nil)
    }

    @Test("A failed Receive Cash Link with no amount sends none")
    func receiveCashLinkFailed() throws {
        let sent = try Analytics.recordingSends {
            Analytics.transfer(event: .receiveCashLink, exchangedFiat: nil, grabTime: nil, successful: false, error: NSError(domain: "D", code: 1))
        }.single
        #expect(sent.properties["State"] as? String == "Failure")
        #expect(sent.properties["Fiat"] == nil)
        #expect(sent.properties["USDC"] == nil)
    }

    @Test("Tip Received carries the chat type and the amount group")
    func tipReceived() throws {
        let sent = try Analytics.recordingSends { Analytics.tipReceived(chatType: .tipDm, exchangedFiat: Self.fiat) }.single
        #expect(sent.name == "Tip Received")
        #expect(sent.properties["Chat Type"] as? String == "Tip")
        expectAmount(sent)
    }

    @Test("Add Money steps carry the method and the amount group")
    func addMoneyAmount() throws {
        let confirmed = try Analytics.recordingSends { Analytics.addMoneyAmountConfirmed(method: .coinbase, exchangedFiat: Self.fiat) }.single
        #expect(confirmed.name == "Add Money: Amount Confirmed")
        #expect(confirmed.properties["Method"] as? String == "Coinbase")
        expectAmount(confirmed)

        let invoked = try Analytics.recordingSends { Analytics.addMoneyPaymentInvoked(method: .phantom, exchangedFiat: Self.fiat) }.single
        #expect(invoked.name == "Add Money: Payment Invoked")
        expectAmount(invoked)

        let result = try Analytics.recordingSends { Analytics.addMoney(method: .coinbase, exchangedFiat: Self.fiat, successful: true, error: nil) }.single
        #expect(result.name == "Add Money")
        #expect(result.properties["State"] as? String == "Success")
        expectAmount(result)

        let phantomFailed = try Analytics.recordingSends {
            Analytics.addMoney(method: .phantom, exchangedFiat: nil, successful: false, error: NSError(domain: "D", code: 1))
        }.single
        #expect(phantomFailed.properties["State"] as? String == "Failure")
        #expect(phantomFailed.properties["Fiat"] == nil)
    }

    // MARK: - Swap submit -

    @Test("A submitted buy is Token Purchase With its method, with the bought mint", arguments: [
        (SwapType.buyWithReserves, "Token Purchase With Reserves"),
        (.buyWithCurrency, "Token Purchase With Currency"),
    ])
    func buySubmit(_ swapType: SwapType, _ expected: String) throws {
        let sent = try Analytics.recordingSends {
            SwapCompletionReporter.trackSubmit(swapType: swapType, mint: .jeffy, amount: Self.fiat, fee: Self.fiat, error: nil)
        }.single
        #expect(sent.name == expected)
        #expect(sent.properties["Mint"] as? String == PublicKey.jeffy.base58)
        #expect(sent.properties["Fiat"] as? Double == 5)
        #expect(sent.properties["USDC"] as? Double == 5)
        #expect(sent.properties["State"] == nil)
        #expect(sent.properties["Payment Mint"] == nil)
    }

    @Test("A submitted convert is Token Sell of the source, with the fee")
    func convertSubmit() throws {
        let sent = try Analytics.recordingSends {
            SwapCompletionReporter.trackSubmit(swapType: .convert, mint: .jeffy, amount: Self.fiat, fee: Self.fiat, error: NSError(domain: "D", code: 1))
        }.single
        #expect(sent.name == "Token Sell")
        #expect(sent.properties["Mint"] as? String == PublicKey.jeffy.base58)
        #expect(sent.properties["Fee"] as? Double == 5)
        #expect(sent.properties["Error"] != nil)
    }

    @Test("A cancelled submit sends nothing")
    func cancelledSubmit() {
        let sent = Analytics.recordingSends {
            SwapCompletionReporter.trackSubmit(swapType: .buyWithReserves, mint: .jeffy, amount: Self.fiat, fee: Self.fiat, error: CancellationError())
        }
        #expect(sent.isEmpty)
    }

    // MARK: - Wallet -

    @Test("Wallet events carry Provider Phantom")
    func walletProvider() throws {
        let sent = Analytics.recordingSends {
            Analytics.walletConnected()
            Analytics.walletCancelled()
            Analytics.walletTransactionsFailed()
        }
        #expect(sent.map(\.name) == ["Wallet: Connect", "Wallet: Cancel", "Wallet: Transactions Failed"])
        #expect(sent.allSatisfy { $0.properties["Provider"] as? String == "Phantom" })
    }

    @Test("Request Amount sends the USDC amount's group in USD")
    func walletRequestAmount() throws {
        let sent = try Analytics.recordingSends {
            Analytics.walletRequestAmount(amount: WalletConnection.usdValue(of: TokenAmount(quarks: 5_000_000, mint: .usdc)))
        }.single
        #expect(sent.name == "Wallet: Request Amount")
        #expect(sent.properties["Provider"] as? String == "Phantom")
        #expect(sent.properties["Fiat"] as? Double == 5)
        #expect(sent.properties["Currency"] as? String == "usd")
        #expect(sent.properties["USDC"] as? Double == 5)
        #expect(sent.properties["Quarks"] as? Double == 5_000_000)
    }

    @Test("Only Phantom's user reject (4001) is Wallet: Cancel", arguments: [
        ("4001", true),
        ("-32603", false),
        ("4100", false),
    ])
    func walletCancel(_ code: String, _ isCancel: Bool) {
        defer { Keychain.connectedWalletSession = nil }
        let connection = WalletConnection(owner: .mock, rpc: MockSolanaRPC(), preferredLiquidityPool: { .unknown })
        let sent = Analytics.recordingSends {
            connection.didReceiveURL(url: URL(string: "https://app.flipcash.com/wallet/transactionSigned?errorCode=\(code)")!)
        }
        #expect(sent.map(\.name) == (isCancel ? ["Wallet: Cancel"] : []))
    }

    @Test("An expired blockhash is not a failed wallet transaction", arguments: [
        ("Transaction simulation failed: Blockhash not found", true),
        ("BlockhashNotFound", true),
        ("Transaction simulation failed: Error processing Instruction 2", false),
        (nil, false),
    ] as [(String?, Bool)])
    func blockhashNotFound(_ message: String?, _ expected: Bool) {
        #expect(PhantomDepositOperation.isBlockhashNotFound(message: message) == expected)
    }
}
