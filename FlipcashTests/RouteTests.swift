//
//  RouteTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
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

    @Test("A group invite link round-trips: the built URL parses back to the same chat")
    func groupInviteLinkRoundTrip() {
        // A group's ChatId is a 16-byte UUID, so its link carries the dashed form rather than the
        // base64url a 32-byte DM id encodes to.
        let uuid = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
        let conversationID = ConversationID(uuidString: uuid.uuidString)!

        let url = URL.groupChatInvite(for: conversationID)
        // Lowercased, because `linkPathComponent` is — one spelling, so two clients that build the
        // same link produce the same string. Parsing stays case-insensitive.
        #expect(url.absoluteString == "https://app.flipcash.com/chat/3f2504e0-4f89-41d3-9a0c-0305e82c3301")

        if case .chat(let parsed) = Route(url: url)?.path {
            #expect(parsed == conversationID)
        } else {
            Issue.record("A built invite link should parse back as .chat")
        }

        // The same id over the custom scheme, which is what a push tap re-enters through.
        let deepLink = URL(string: "flipcash://chat/\(conversationID.linkPathComponent)")!
        if case .chat(let parsed) = Route(url: deepLink)?.path {
            #expect(parsed == conversationID)
        } else {
            Issue.record("A group deep link should parse as .chat")
        }
    }

    @Test("A group id keeps its send-cash path, and a 16-byte id that isn't a UUID still fails")
    func groupSendCashAndMalformed() {
        let conversationID = ConversationID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
        let url = URL(string: "https://app.flipcash.com/chat/\(conversationID.linkPathComponent)/send")!

        if case .chatSendCash(let parsed) = Route(url: url)?.path {
            #expect(parsed == conversationID)
        } else {
            Issue.record("A group /chat/{uuid}/send should parse as .chatSendCash")
        }

        // Neither a UUID nor 32 base64url bytes.
        #expect(Route(url: URL(string: "https://app.flipcash.com/chat/3F2504E0-4F89-41D3")!) == nil)
    }

    @Test("Chat send-cash route parses /chat/{id}/send to .chatSendCash")
    func chatSendCashRoute() {
        let idData = Data((0..<32).map { UInt8($0) })
        let encoded = ConversationID(data: idData).base64URLEncoded

        // /chat/{id}/send → .chatSendCash
        let deepLink = URL(string: "flipcash://chat/\(encoded)/send")!
        let universalLink = URL(string: "https://app.flipcash.com/chat/\(encoded)/send")!

        if case .chatSendCash(let id) = Route(url: deepLink)?.path {
            #expect(id.data == idData)
        } else {
            Issue.record("Deep link /chat/{id}/send should parse as .chatSendCash")
        }

        if case .chatSendCash(let id) = Route(url: universalLink)?.path {
            #expect(id.data == idData)
        } else {
            Issue.record("Universal link /chat/{id}/send should parse as .chatSendCash")
        }
    }

    @Test("Plain /chat/{id} still parses as .chat, not .chatSendCash")
    func chatRouteUnaffectedBySendCashPath() {
        let idData = Data((0..<32).map { UInt8($0) })
        let encoded = ConversationID(data: idData).base64URLEncoded

        if case .chat(let id) = Route(url: URL(string: "flipcash://chat/\(encoded)")!)?.path {
            #expect(id.data == idData)
        } else {
            Issue.record("Plain /chat/{id} should still parse as .chat")
        }
    }

    // MARK: - Sheet Routes -
    //
    // The home-screen quick actions open sheets via these routes, and they emit
    // the custom scheme (`QuickActionsController`). The universal-link forms are
    // deliberately NOT routes: `app.flipcash.com/<username>` puts handles in
    // that namespace, and a claimed `discover` that opened the Discover tab
    // would be a link that goes somewhere other than the person it names.

    @Test("Give route parses from the custom scheme")
    func giveRoute_customScheme() throws {
        let path = try #require(Route(url: URL(string: "flipcash://give")!)?.path)
        if case .give = path {} else {
            Issue.record("flipcash://give should parse as .give")
        }
    }

    @Test("Balance route parses from the custom scheme")
    func balanceRoute_customScheme() throws {
        let path = try #require(Route(url: URL(string: "flipcash://balance")!)?.path)
        if case .balance = path {} else {
            Issue.record("flipcash://balance should parse as .balance")
        }
    }

    @Test("Discover route parses from the custom scheme")
    func discoverRoute_customScheme() throws {
        let path = try #require(Route(url: URL(string: "flipcash://discover")!)?.path)
        if case .discover = path {} else {
            Issue.record("flipcash://discover should parse as .discover")
        }
    }

    @Test(
        "Quick-action names are ordinary handles on the web",
        arguments: [
            ("https://app.flipcash.com/give", "give"),
            ("https://app.flipcash.com/balance", "balance"),
            ("https://app.flipcash.com/discover", "discover"),
        ]
    )
    func quickActionNames_universalLink_areHandles(urlString: String, handle: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        guard case .username(let username) = path else {
            Issue.record("\(urlString) should parse as .username, not a quick action")
            return
        }
        // The server's reserved list decides whether these are claimable; the
        // client only decides that they aren't quick actions off the custom scheme.
        #expect(username.value == handle)
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

    @Test("Tip route parses the user id from every host and scheme", arguments: [
        "https://flipcash.com/11111111-2222-3333-4444-555555555555",
        "https://app.flipcash.com/11111111-2222-3333-4444-555555555555",
        "flipcash://11111111-2222-3333-4444-555555555555",
        // The `/tip/` form links already shared still carry.
        "https://app.flipcash.com/tip/11111111-2222-3333-4444-555555555555",
        "flipcash://tip/11111111-2222-3333-4444-555555555555",
    ])
    func tipRoute(urlString: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        guard case .tip(let userID) = path else {
            Issue.record("\(urlString) should parse as .tip")
            return
        }
        #expect(userID == UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
    }

    @Test("Tip route rejects a missing or malformed user id", arguments: [
        "https://app.flipcash.com/tip",
        "https://app.flipcash.com/tip/not-a-uuid",
        "flipcash://tip/",
    ])
    func tipRouteMalformed(urlString: String) {
        #expect(Route(url: URL(string: urlString)!) == nil)
    }

    @Test("A root segment that only resembles a uuid stays unknown")
    func tipRoute_partialUUID_isUnknown() throws {
        let path = try #require(Route(url: URL(string: "https://flipcash.com/11111111-2222")!)?.path)
        if case .unknown = path {} else {
            Issue.record("A truncated uuid should parse as .unknown")
        }
    }

    // MARK: - Vanity Handle URLs -

    @Test("A vanity link parses the handle from every host and scheme", arguments: [
        "https://app.flipcash.com/taylor",
        "https://flipcash.com/taylor",
        "flipcash://taylor",
    ])
    func usernameRoute(urlString: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        guard case .username(let username) = path else {
            Issue.record("\(urlString) should parse as .username")
            return
        }
        #expect(username.value == "taylor")
    }

    @Test("A capitalized handle parses as the lowercase one it names", arguments: [
        "https://app.flipcash.com/Taylor",
        "https://app.flipcash.com/TAYLOR",
    ])
    func usernameRoute_capitalized_lowercased(urlString: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        guard case .username(let username) = path else {
            Issue.record("\(urlString) should parse as .username")
            return
        }
        #expect(username.value == "taylor")
    }

    @Test("The handle bounds hold at both ends", arguments: [
        ("https://app.flipcash.com/te", "te"),
        ("https://app.flipcash.com/abcdefghijklmno", "abcdefghijklmno"),
        ("https://app.flipcash.com/a_1", "a_1"),
    ])
    func usernameRoute_bounds(urlString: String, handle: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        guard case .username(let username) = path else {
            Issue.record("\(urlString) should parse as .username")
            return
        }
        #expect(username.value == handle)
    }

    @Test("A segment that can't be a handle stays unknown", arguments: [
        // One character, sixteen characters, and a hyphen — the three ways the
        // handle pattern is missed.
        "https://app.flipcash.com/t",
        "https://app.flipcash.com/abcdefghijklmnop",
        "https://app.flipcash.com/not-a-handle",
        // A handle is the whole path or it isn't a handle.
        "https://app.flipcash.com/taylor/photos",
    ])
    func usernameRoute_malformed_isUnknown(urlString: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        if case .unknown = path {} else {
            Issue.record("\(urlString) should parse as .unknown, not a handle")
        }
    }

    @Test("Named routes still win over the handle fallback", arguments: [
        "https://app.flipcash.com/login",
        "https://app.flipcash.com/cash",
        "https://app.flipcash.com/verify",
        "https://app.flipcash.com/wallet",
    ])
    func usernameRoute_doesNotShadowNamedRoutes(urlString: String) throws {
        let path = try #require(Route(url: URL(string: urlString)!)?.path)
        if case .username = path {
            Issue.record("\(urlString) should not parse as a handle")
        }
    }
}
