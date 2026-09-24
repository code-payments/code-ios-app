//
//  MigratedEventsTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// What every event built by the shared contract sends, written as literals. These were
/// recorded from the native helpers before the move, and the move must not change them.
@MainActor
@Suite("Events built by the shared contract", .serialized)
struct MigratedEventsTests {

    init() {
        Analytics.tokenSymbolResolver = nil
    }

    // MARK: - Chat -

    @Test("Sent Message carries its chat type", arguments: [
        (ConversationType?.some(.contactDm), "Contact"),
        (.some(.tipDm), "Tip"),
        (.some(.group), "Group"),
        (nil, "Unknown"),
    ])
    func sentMessage(_ chatType: ConversationType?, _ expected: String) throws {
        let sent = Analytics.recordingSends { Analytics.sentMessage(chatType: chatType) }
        try expectEvent(sent, "Sent Message", ["Chat Type": expected])
    }

    @Test("A failed Sent Message carries the iOS error format once")
    func sentMessageError() throws {
        let error = NSError(domain: "D", code: 7)
        let sent = Analytics.recordingSends { Analytics.sentMessage(chatType: .group, error: error) }
        try expectEvent(sent, "Sent Message", [
            "Chat Type": "Group",
            "Error": "D.Error Domain=D Code=7 \"(null)\":7",
        ])
    }

    @Test("Message Received carries its chat type", arguments: [
        (ConversationType?.some(.contactDm), "Contact"),
        (.some(.tipDm), "Tip"),
        (.some(.group), "Group"),
        (nil, "Unknown"),
    ])
    func messageReceived(_ chatType: ConversationType?, _ expected: String) throws {
        let sent = Analytics.recordingSends { Analytics.messageReceived(chatType: chatType) }
        try expectEvent(sent, "Message Received", ["Chat Type": expected])
    }

    // MARK: - Transfer -

    @Test("Grab Bill Start has no properties")
    func grabBillStart() throws {
        let sent = Analytics.recordingSends { Analytics.grabBillStarted() }
        try expectEvent(sent, "Grab Bill Start", [:])
    }

    @Test("Give Bill Start has no properties")
    func giveBillStart() throws {
        let sent = Analytics.recordingSends { Analytics.giveBillStarted() }
        try expectEvent(sent, "Give Bill Start", [:])
    }

    // MARK: - Add Money -

    @Test("Add Money: Opened carries its source", arguments: [
        (Analytics.AddMoneySource.menu, "Menu"),
        (.giveShortfall, "Give Shortfall"),
        (.buyShortfall, "Buy Shortfall"),
        (.usernameShortfall, "Username Shortfall"),
        (.chat, "Chat"),
        (.scanner, "Scanner"),
        (.balance, "Balance"),
    ])
    func addMoneyOpened(_ source: Analytics.AddMoneySource, _ expected: String) throws {
        let sent = Analytics.recordingSends { Analytics.addMoneyOpened(source: source) }
        try expectEvent(sent, "Add Money: Opened", ["Source": expected])
    }

    @Test("Add Money: Address Copied carries the mint")
    func addMoneyAddressCopied() throws {
        let sent = Analytics.recordingSends { Analytics.addMoneyAddressCopied(mint: .jeffy) }
        try expectEvent(sent, "Add Money: Address Copied", [
            "Mint": "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25",
        ])
    }

    @Test("Add Money: Address Copied gains the token symbol")
    func addMoneyAddressCopiedSymbol() throws {
        Analytics.tokenSymbolResolver = { _ in "JEFF" }
        defer { Analytics.tokenSymbolResolver = nil }
        let sent = Analytics.recordingSends { Analytics.addMoneyAddressCopied(mint: .jeffy) }
        try expectEvent(sent, "Add Money: Address Copied", [
            "Mint": "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25",
            "Token Symbol": "JEFF",
        ])
    }

    // MARK: - Onramp -

    @Test("Onramp steps are named after the screen shown")
    func onrampStep() throws {
        let expected: [(OnrampStep, String)] = [
            (.enterPhone, "Onramp: Show Enter Phone"),
            (.confirmPhone, "Onramp: Show Confirm Phone"),
            (.enterEmail, "Onramp: Show Enter Email"),
            (.confirmEmail, "Onramp: Show Confirm Email"),
        ]
        for (step, name) in expected {
            let sent = Analytics.recordingSends { Analytics.onrampStep(step) }
            try expectEvent(sent, name, [:])
        }
    }

    // MARK: - Token Info -

    @Test("Token Info is named after where it opened from", arguments: [
        (Analytics.TokenInfoEvent.openedFromDeeplink, "Token Info: Opened From Deeplink"),
        (.openedFromWallet, "Token Info: Opened From Wallet"),
    ])
    func tokenInfoOpened(_ source: Analytics.TokenInfoEvent, _ expected: String) throws {
        let sent = Analytics.recordingSends { Analytics.tokenInfoOpened(from: source, mint: .jeffy) }
        try expectEvent(sent, expected, ["Mint": "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25"])
    }

    @Test("Token Info gains the token symbol")
    func tokenInfoOpenedSymbol() throws {
        Analytics.tokenSymbolResolver = { _ in "JEFF" }
        defer { Analytics.tokenSymbolResolver = nil }
        let sent = Analytics.recordingSends { Analytics.tokenInfoOpened(from: .openedFromWallet, mint: .jeffy) }
        try expectEvent(sent, "Token Info: Opened From Wallet", [
            "Mint": "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25",
            "Token Symbol": "JEFF",
        ])
    }

    // MARK: - Scan -

    @Test("Gallery Scan: Image Picked has no properties")
    func galleryImagePicked() throws {
        let sent = Analytics.recordingSends { Analytics.galleryScanStarted() }
        try expectEvent(sent, "Gallery Scan: Image Picked", [:])
    }

    @Test("Tip Card Scanned has no properties")
    func tipCardScanned() throws {
        let sent = Analytics.recordingSends { Analytics.tipCardScanned() }
        try expectEvent(sent, "Tip Card Scanned", [:])
    }

    @Test("Tip Card Presented has no properties")
    func tipCardPresented() throws {
        let sent = Analytics.recordingSends { Analytics.tipCardPresented() }
        try expectEvent(sent, "Tip Card Presented", [:])
    }

    // MARK: - Deeplink -

    @Test("Deeplink: Open carries the URL without its query or fragment")
    func deeplinkOpened() throws {
        let url = try #require(URL(string: "https://app.flipcash.com/c/abc?secret=1#entropy"))
        let sent = Analytics.recordingSends { Analytics.deeplinkOpened(url: url) }
        try expectEvent(sent, "Deeplink: Open", ["URL": "https://app.flipcash.com/c/abc"])
    }

    // MARK: - Display Name -

    @Test("Display name events carry their source", arguments: [
        (Analytics.DisplayNameSource.onboarding, false, "Display Name Set", "Onboarding"),
        (.myAccount, false, "Display Name Set", "My Account"),
        (.tipCardSetup, false, "Display Name Set", "Tip Card Setup"),
        (.onboarding, true, "Display Name Updated", "Onboarding"),
        (.myAccount, true, "Display Name Updated", "My Account"),
        (.tipCardSetup, true, "Display Name Updated", "Tip Card Setup"),
    ])
    func displayName(
        _ source: Analytics.DisplayNameSource,
        _ hadPreviousName: Bool,
        _ expectedName: String,
        _ expectedSource: String
    ) throws {
        let sent = Analytics.recordingSends {
            Analytics.displayNameSubmitted(source: source, hadPreviousName: hadPreviousName)
        }
        try expectEvent(sent, expectedName, ["Source": expectedSource])
    }

    // MARK: - Account -

    @Test("Entered Phone Number has no properties")
    func phoneNumberEntered() throws {
        let sent = Analytics.recordingSends { Analytics.phoneNumberEntered() }
        try expectEvent(sent, "Entered Phone Number", [:])
    }

    @Test("Verified Phone Number has no properties")
    func phoneNumberVerified() throws {
        let sent = Analytics.recordingSends { Analytics.phoneNumberVerified() }
        try expectEvent(sent, "Verified Phone Number", [:])
    }

    @Test("Linked Phone Number has no properties")
    func phoneNumberLinked() throws {
        let sent = Analytics.recordingSends { Analytics.phoneNumberLinked() }
        try expectEvent(sent, "Linked Phone Number", [:])
    }

    @Test("Complete Onboarding has no properties")
    func onboardingCompleted() throws {
        let sent = Analytics.recordingSends { Analytics.onboardingCompleted() }
        try expectEvent(sent, "Complete Onboarding", [:])
    }

    // MARK: - Buttons -

    @Test("Buttons are named after the button", arguments: [
        (Analytics.ButtonEvent.createAccount, "Button: Create Account"),
        (.saveAccessKey, "Button: Save Access Key"),
        (.wroteAccessKey, "Button: Wrote Access Key"),
        (.allowPush, "Button: Allow Push"),
        (.skipPush, "Button: Skip Push"),
        (.buyWithReserves, "Button: Buy With Reserves"),
        (.shareTokenInfo, "Button: Share Token Info"),
    ])
    func button(_ button: Analytics.ButtonEvent, _ expected: String) throws {
        let sent = Analytics.recordingSends { Analytics.buttonTapped(name: button) }
        try expectEvent(sent, expected, [:])
    }

    // MARK: - People -

    @Test("People counters increment their named property")
    func peopleCounters() {
        let increments = Analytics.recordingIncrements {
            Analytics.increment(.tips)
            Analytics.increment(.tipsValue, by: 2.5)
            Analytics.increment(.messages)
        }
        #expect(increments.map(\.property) == ["Tips Received", "Tips Received Value", "Messages Received"])
        #expect(increments.map(\.amount) == [1, 2.5, 1])
    }

    // MARK: - Helpers -

    /// Checks the single event sent: its name, its exact key set, and that every value is
    /// the given string.
    private func expectEvent(
        _ sent: [SentEvent],
        _ name: String,
        _ properties: [String: String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let event = try sent.single
        #expect(event.name == name, sourceLocation: sourceLocation)
        #expect(event.properties.keys.sorted() == properties.keys.sorted(), sourceLocation: sourceLocation)
        for (key, value) in properties {
            #expect(event.properties[key] as? String == value, "\(key)", sourceLocation: sourceLocation)
        }
    }
}
