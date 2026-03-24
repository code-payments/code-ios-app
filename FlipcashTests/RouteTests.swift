//
//  RouteTests.swift
//  FlipcashTests
//
//  Created by Claude on 2025-02-03.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Route Parsing")
struct RouteTests {

    @Test("Login route parses from both URL formats")
    func loginRoute() {
        let deepLink = URL(string: "flipcash://login#e=HQPkfAZjgpGGANQfUNPKvW")!
        let universalLink = URL(string: "https://app.flipcash.com/login#e=HQPkfAZjgpGGANQfUNPKvW")!

        let deepRoute = Route(url: deepLink)
        let universalRoute = Route(url: universalLink)

        #expect(deepRoute != nil)
        #expect(universalRoute != nil)

        if case .login = deepRoute?.path {} else {
            Issue.record("Deep link should parse as .login")
        }

        if case .login = universalRoute?.path {} else {
            Issue.record("Universal link should parse as .login")
        }
    }

    @Test("Cash route parses from both URL formats")
    func cashRoute() {
        let deepLink = URL(string: "flipcash://c#e=HQPkfAZjgpGGANQfUNPKvW")!
        let universalLink = URL(string: "https://send.flipcash.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW")!

        let deepRoute = Route(url: deepLink)
        let universalRoute = Route(url: universalLink)

        #expect(deepRoute != nil)
        #expect(universalRoute != nil)

        if case .cash = deepRoute?.path {} else {
            Issue.record("Deep link should parse as .cash")
        }

        if case .cash = universalRoute?.path {} else {
            Issue.record("Universal link should parse as .cash")
        }
    }

    @Test("Verify email route parses from both URL formats")
    func verifyEmailRoute() {
        let deepLink = URL(string: "flipcash://verify?code=123&email=test@example.com")!
        let universalLink = URL(string: "https://app.flipcash.com/verify?code=123&email=test@example.com")!

        let deepRoute = Route(url: deepLink)
        let universalRoute = Route(url: universalLink)

        #expect(deepRoute != nil)
        #expect(universalRoute != nil)

        if case .verifyEmail = deepRoute?.path {
            #expect(deepRoute?.properties["code"] == "123")
            #expect(deepRoute?.properties["email"] == "test@example.com")
        } else {
            Issue.record("Deep link should parse as .verifyEmail")
        }

        if case .verifyEmail = universalRoute?.path {
            #expect(universalRoute?.properties["code"] == "123")
            #expect(universalRoute?.properties["email"] == "test@example.com")
        } else {
            Issue.record("Universal link should parse as .verifyEmail")
        }
    }

    @Test("Token route parses from both URL formats")
    func tokenRoute() {
        let mint = "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25"

        // Valid mint - both formats should work
        let deepLink = URL(string: "flipcash://token/\(mint)")!
        let universalLink = URL(string: "https://app.flipcash.com/token/\(mint)")!

        let deepRoute = Route(url: deepLink)
        let universalRoute = Route(url: universalLink)

        #expect(deepRoute != nil)
        #expect(universalRoute != nil)

        if case .token(let parsedMint) = deepRoute?.path {
            #expect(parsedMint.base58 == mint)
        } else {
            Issue.record("Deep link should parse as .token with mint")
        }

        if case .token(let parsedMint) = universalRoute?.path {
            #expect(parsedMint.base58 == mint)
        } else {
            Issue.record("Universal link should parse as .token with mint")
        }

        // Invalid mint - both formats should return nil
        let invalidDeepLink = URL(string: "flipcash://token/invalid-mint")!
        let invalidUniversalLink = URL(string: "https://app.flipcash.com/token/invalid-mint")!

        #expect(Route(url: invalidDeepLink) == nil)
        #expect(Route(url: invalidUniversalLink) == nil)

        // Missing mint - both formats should return nil
        let noMintDeepLink = URL(string: "flipcash://token")!
        let noMintUniversalLink = URL(string: "https://app.flipcash.com/token")!

        #expect(Route(url: noMintDeepLink) == nil)
        #expect(Route(url: noMintUniversalLink) == nil)
    }

    // MARK: - Wallet Callback URLs -

    @Test("Wallet callback universal links parse as unknown routes")
    func walletCallbackUniversalLinks() {
        // Wallet callback URLs (from Phantom) parse as .unknown routes.
        // DeepLinkController returns nil action for .unknown, which means
        // the interface reset condition must handle nil action correctly
        // (see interfaceResetWithNilAction test).

        let walletConnected = URL(string: "https://app.flipcash.com/wallet/walletConnected?nonce=abc&data=xyz")!
        let transactionSigned = URL(string: "https://app.flipcash.com/wallet/transactionSigned?nonce=abc&data=xyz")!
        let walletError = URL(string: "https://app.flipcash.com/wallet/walletConnected?errorCode=4001")!

        if case .unknown = Route(url: walletConnected)?.path {} else {
            Issue.record("walletConnected should parse as .unknown")
        }
        if case .unknown = Route(url: transactionSigned)?.path {} else {
            Issue.record("transactionSigned should parse as .unknown")
        }
        if case .unknown = Route(url: walletError)?.path {} else {
            Issue.record("walletError should parse as .unknown")
        }
    }

    @Test("Wallet callback deep links parse as unknown routes")
    func walletCallbackDeepLinks() {
        let walletConnected = URL(string: "flipcash://wallet/walletConnected?nonce=abc&data=xyz")!
        let transactionSigned = URL(string: "flipcash://wallet/transactionSigned?nonce=abc&data=xyz")!
        let walletError = URL(string: "flipcash://wallet/walletConnected?errorCode=4001")!

        if case .unknown = Route(url: walletConnected)?.path {} else {
            Issue.record("walletConnected deep link should parse as .unknown")
        }
        if case .unknown = Route(url: transactionSigned)?.path {} else {
            Issue.record("transactionSigned deep link should parse as .unknown")
        }
        if case .unknown = Route(url: walletError)?.path {} else {
            Issue.record("walletError deep link should parse as .unknown")
        }
    }

    // MARK: - Interface Reset Condition -

    @Test("Nil action (wallet callback) does not reset interface")
    @MainActor func interfaceResetWithNilAction() {
        // Wallet callback URLs return nil action from DeepLinkController.
        // The interface must NOT be reset — the URL was already handled
        // by WalletConnection.didReceiveURL as a side effect.
        //
        // Regression guard for a8b43188 where `== false` was changed
        // to `?? false`, inverting the nil case.

        let result = AppDelegate.shouldResetInterface(
            hasBeenBackgrounded: true,
            action: nil,
            preventUserInterfaceReset: false
        )

        #expect(result == false, "nil action must not trigger interface reset")
    }

    @Test("Normal deep link resets interface when backgrounded")
    @MainActor func interfaceResetWithNormalDeepLink() {
        // A normal deep link (cash link, login) with default
        // preventUserInterfaceReset should reset the UI.

        let action = DeepLinkAction(
            kind: .accessKey(.mock),
            sessionAuthenticator: .mock
        )

        let result = AppDelegate.shouldResetInterface(
            hasBeenBackgrounded: true,
            action: action,
            preventUserInterfaceReset: false
        )

        #expect(result == true, "normal deep link should trigger reset when backgrounded")
    }

    @Test("Action with preventUserInterfaceReset does not reset")
    @MainActor func interfaceResetWithPreventFlag() {
        // Email verification mid-flow sets preventUserInterfaceReset
        // to avoid destroying the onboarding state.

        var action = DeepLinkAction(
            kind: .accessKey(.mock),
            sessionAuthenticator: .mock
        )
        action.preventUserInterfaceReset = true

        let result = AppDelegate.shouldResetInterface(
            hasBeenBackgrounded: true,
            action: action,
            preventUserInterfaceReset: false
        )

        #expect(result == false, "action with preventUserInterfaceReset must not reset")
    }

    @Test("QR deep link parameter prevents reset")
    @MainActor func interfaceResetWithQRParameter() {
        // QR code scans pass preventUserInterfaceReset: true as a
        // parameter to keep the camera active after scanning.

        let action = DeepLinkAction(
            kind: .accessKey(.mock),
            sessionAuthenticator: .mock
        )

        let result = AppDelegate.shouldResetInterface(
            hasBeenBackgrounded: true,
            action: action,
            preventUserInterfaceReset: true
        )

        #expect(result == false, "QR parameter must prevent reset")
    }

    @Test("No reset when app has not been backgrounded")
    @MainActor func interfaceResetWithoutBackgrounding() {
        let action = DeepLinkAction(
            kind: .accessKey(.mock),
            sessionAuthenticator: .mock
        )

        let result = AppDelegate.shouldResetInterface(
            hasBeenBackgrounded: false,
            action: action,
            preventUserInterfaceReset: false
        )

        #expect(result == false, "must not reset if app was never backgrounded")
    }
}
