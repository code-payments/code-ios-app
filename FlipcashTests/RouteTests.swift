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

    @Test("Chat route parses a base64url chat ID from both URL formats")
    func chatRoute() {
        // The server encodes the 32-byte ChatId with base64.URLEncoding (padded).
        let idData = Data((0..<32).map { UInt8($0) })
        let encoded = idData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        let deepLink = URL(string: "flipcash://chat/\(encoded)")!
        let universalLink = URL(string: "https://app.flipcash.com/chat/\(encoded)")!

        if case .chat(let id) = Route(url: deepLink)?.path {
            #expect(id.data == idData)
        } else {
            Issue.record("Deep link should parse as .chat with the decoded ID")
        }

        if case .chat(let id) = Route(url: universalLink)?.path {
            #expect(id.data == idData)
        } else {
            Issue.record("Universal link should parse as .chat with the decoded ID")
        }

        // Unpadded base64url also decodes
        let unpadded = encoded.replacingOccurrences(of: "=", with: "")
        let unpaddedLink = URL(string: "https://app.flipcash.com/chat/\(unpadded)")!

        if case .chat(let id) = Route(url: unpaddedLink)?.path {
            #expect(id.data == idData)
        } else {
            Issue.record("Unpadded base64url should parse as .chat with the decoded ID")
        }

        // Wrong length - both formats should return nil
        let shortID = Data((0..<16).map { UInt8($0) }).base64EncodedString()
        #expect(Route(url: URL(string: "flipcash://chat/\(shortID)")!) == nil)
        #expect(Route(url: URL(string: "https://app.flipcash.com/chat/\(shortID)")!) == nil)

        // Not base64 - both formats should return nil
        #expect(Route(url: URL(string: "flipcash://chat/not.valid.base64")!) == nil)
        #expect(Route(url: URL(string: "https://app.flipcash.com/chat/not.valid.base64")!) == nil)

        // Missing ID - both formats should return nil
        #expect(Route(url: URL(string: "flipcash://chat")!) == nil)
        #expect(Route(url: URL(string: "https://app.flipcash.com/chat")!) == nil)
    }

    // MARK: - Sheet Routes -
    //
    // The home-screen quick actions open sheets via these routes. The
    // `flipcash://` deep link and the universal link must parse to the same case.

    @Test(
        "Give route parses from both URL formats",
        arguments: ["flipcash://give", "https://app.flipcash.com/give"]
    )
    func giveRoute(urlString: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        if case .give = path {} else {
            Issue.record("\(urlString) should parse as .give")
        }
    }

    @Test(
        "Balance route parses from both URL formats",
        arguments: ["flipcash://balance", "https://app.flipcash.com/balance"]
    )
    func balanceRoute(urlString: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        if case .balance = path {} else {
            Issue.record("\(urlString) should parse as .balance")
        }
    }

    @Test(
        "Discover route parses from both URL formats",
        arguments: ["flipcash://discover", "https://app.flipcash.com/discover"]
    )
    func discoverRoute(urlString: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        if case .discover = path {} else {
            Issue.record("\(urlString) should parse as .discover")
        }
    }

    @Test(
        "Send route parses from both URL formats",
        arguments: ["flipcash://send", "https://app.flipcash.com/send"]
    )
    func sendRoute(urlString: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        if case .send = path {} else {
            Issue.record("\(urlString) should parse as .send")
        }
    }

    // MARK: - Wallet Callback URLs -

    @Test(
        "Plain /wallet is reserved for Phantom and parses as unknown",
        arguments: ["flipcash://wallet", "https://app.flipcash.com/wallet"]
    )
    func walletNamespaceReserved(urlString: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        if case .unknown = path {} else {
            Issue.record("\(urlString) should parse as .unknown")
        }
    }

    @Test("Phantom callback URLs parse as unknown", arguments: [
        "https://app.flipcash.com/wallet/walletConnected?nonce=abc&data=xyz",
        "https://app.flipcash.com/wallet/transactionSigned?nonce=abc&data=xyz",
        "https://app.flipcash.com/wallet/walletConnected?errorCode=4001",
        "flipcash://wallet/walletConnected?nonce=abc&data=xyz",
        "flipcash://wallet/transactionSigned?nonce=abc&data=xyz",
        "flipcash://wallet/walletConnected?errorCode=4001",
    ])
    func walletCallback(urlString: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        if case .unknown = path {} else {
            Issue.record("\(urlString) should parse as .unknown")
        }
    }

}
