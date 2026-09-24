//
//  WalletConnectionCallbackTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

/// Serialized because every test seeds and clears the one keychain slot the connected session lives in.
@MainActor
@Suite("WalletConnection callback gate", .serialized)
struct WalletConnectionCallbackTests {

    private static func seedSession() throws {
        let box = try WalletConnection.Box()
        Keychain.connectedWalletSession = ConnectedWalletSession(
            secretKey: box.secretKey,
            walletPublicKey: try PublicKey([UInt8](repeating: 3, count: 32)),
            sessionToken: "session-token",
            phantomEncryptionPublicKey: Data(repeating: 4, count: 32)
        )
    }

    private static func makeConnection() -> WalletConnection {
        WalletConnection(owner: .mock, rpc: MockSolanaRPC(), preferredLiquidityPool: { .unknown })
    }

    /// Chat links and scanned QR codes reach `didReceiveURL` too, so a shared first-party link
    /// carrying `errorCode` must not read as Phantom reporting a failure.
    @Test(
        "A URL that is not a Phantom callback leaves the wallet session alone",
        arguments: [
            "https://app.flipcash.com/?errorCode=5",
            "https://app.flipcash.com/token/54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25?errorCode=5",
            "https://app.flipcash.com/wallet?errorCode=5",
            "https://app.flipcash.com/wallet/transactionSigned/extra?errorCode=5",
            "https://jump.flipcash.com/?errorCode=5#source=https%3A%2F%2Fapp.flipcash.com%2F",
            "https://send.flipcash.com/wallet/transactionSigned?errorCode=5",
            "https://evil.com/wallet/transactionSigned?errorCode=5",
            "http://app.flipcash.com/wallet/transactionSigned?errorCode=5",
            "flipcash://wallet/transactionSigned?errorCode=5",
        ]
    )
    func nonCallbackURL_leavesSessionAlone(urlString: String) async throws {
        try Self.seedSession()
        defer { Keychain.connectedWalletSession = nil }
        let connection = Self.makeConnection()
        #expect(connection.session != nil)

        connection.didReceiveURL(url: URL(string: urlString)!)

        #expect(connection.session != nil)
        #expect(connection.isConnected)

        // The stream buffers every yield, so if the ignored URL had produced an event it would
        // arrive ahead of this real callback's.
        connection.didReceiveURL(url: URL(string: "https://app.flipcash.com/wallet/transactionSigned?errorCode=7")!)
        var events = connection.deeplinkEvents.makeAsyncIterator()
        let first = try #require(await events.next())
        switch first {
        case .failed(let code):
            #expect(code == "7")
        case .signed, .userCancelled:
            Issue.record("Expected only the real callback's failure, got \(first)")
        }
    }

    @Test(
        "A Phantom callback with a non-cancel error code drops the session and fails the deposit",
        arguments: [
            "https://app.flipcash.com/wallet/walletConnected?errorCode=5",
            "https://app.flipcash.com/wallet/transactionSigned?errorCode=5",
            "https://APP.flipcash.com/wallet/transactionSigned?errorCode=5",
        ]
    )
    func callbackURL_withErrorCode_isHandled(urlString: String) async throws {
        try Self.seedSession()
        defer { Keychain.connectedWalletSession = nil }
        let connection = Self.makeConnection()

        connection.didReceiveURL(url: URL(string: urlString)!)

        #expect(connection.session == nil)
        #expect(!connection.isConnected)
        var events = connection.deeplinkEvents.makeAsyncIterator()
        let first = try #require(await events.next())
        switch first {
        case .failed(let code):
            #expect(code == "5")
        case .signed, .userCancelled:
            Issue.record("Expected a failed event, got \(first)")
        }
    }

    @Test("A Phantom callback with the user-cancel code keeps the session and reports the cancel")
    func callbackURL_withUserCancel_keepsSession() async throws {
        try Self.seedSession()
        defer { Keychain.connectedWalletSession = nil }
        let connection = Self.makeConnection()

        connection.didReceiveURL(url: URL(string: "https://app.flipcash.com/wallet/transactionSigned?errorCode=4001")!)

        #expect(connection.session != nil)
        var events = connection.deeplinkEvents.makeAsyncIterator()
        let first = try #require(await events.next())
        switch first {
        case .userCancelled:
            break
        case .signed, .failed:
            Issue.record("Expected a user-cancel event, got \(first)")
        }
    }

    @Test("The redirect links sent to Phantom are the URLs the gate accepts")
    func redirectLinks_passTheGate() {
        #expect(WalletConnection.isWalletCallback(WalletConnection.walletConnectedURL))
        #expect(WalletConnection.isWalletCallback(WalletConnection.transactionSignedURL))
    }
}
