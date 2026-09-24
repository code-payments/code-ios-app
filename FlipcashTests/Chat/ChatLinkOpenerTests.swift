//
//  ChatLinkOpenerTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import Flipcash

@MainActor
@Suite("ChatLinkOpener")
struct ChatLinkOpenerTests {

    @MainActor
    private final class Spy {
        var deepLinked: [URL] = []
        var external: [URL] = []
        var deepLinkResult = true

        var opener: ChatLinkOpener {
            ChatLinkOpener(
                openDeepLink: { self.deepLinked.append($0); return self.deepLinkResult },
                openExternally: { self.external.append($0) }
            )
        }
    }

    @Test("A foreign host never reaches the deep-link handler, whatever its path looks like",
          arguments: [
              "https://example.com/login",
              "https://evil.tld/login/#e=HQPkfAZjgpGGANQfUNPKvW",
              "https://evil.tld/somehandle",
              "https://evil.tld/c/#/e=HQPkfAZjgpGGANQfUNPKvW",
              "https://evilflipcash.com/somehandle",
              "https://app.flipcash.com.evil.tld/somehandle",
              "https://evil.tld/wallet/walletConnected?errorCode=1",
          ])
    func foreignHost_opensExternally(urlString: String) throws {
        let url = try #require(URL(string: urlString))
        let spy = Spy()

        spy.opener.open(url)

        #expect(spy.deepLinked.isEmpty)
        #expect(spy.external == [url])
    }

    @Test("One of our hosts goes to the deep-link handler and stays in the app",
          arguments: [
              "https://app.flipcash.com/somehandle",
              "https://flipcash.com/somehandle",
              "https://send.flipcash.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW",
          ])
    func ourHost_isDeepLinked(urlString: String) throws {
        let url = try #require(URL(string: urlString))
        let spy = Spy()

        spy.opener.open(url)

        #expect(spy.deepLinked == [url])
        #expect(spy.external.isEmpty)
    }

    @Test("One of our links that names no action falls back to the browser")
    func ourHost_unhandled_opensExternally() throws {
        let url = try #require(URL(string: "https://flipcash.com/terms"))
        let spy = Spy()
        spy.deepLinkResult = false

        spy.opener.open(url)

        #expect(spy.deepLinked == [url])
        #expect(spy.external == [url])
    }
}
