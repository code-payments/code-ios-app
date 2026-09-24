import Foundation
import Testing
import FlipcashUI
@testable import Flipcash

@Suite struct ExternalLinkCheckTests {

    private func check(_ string: String) throws -> ExternalLinkCheck {
        ExternalLinkCheck(url: try #require(URL(string: string)))
    }

    @Test(arguments: Route.flipcashHosts.sorted())
    func firstPartyHostOpens(host: String) throws {
        #expect(try check("https://\(host)/somehandle") == .open)
    }

    @Test func firstPartyHostOpensInAnyCase() throws {
        #expect(try check("https://App.FlipCash.com/somehandle") == .open)
    }

    @Test func customSchemeOpens() throws {
        #expect(try check("flipcash://chat/123") == .open)
    }

    @Test func schemeWithoutHostOpens() throws {
        #expect(try check("mailto:support@flipcash.com") == .open)
    }

    @Test func hostThatEndsWithOursWarns() throws {
        #expect(try check("https://evilflipcash.com/login") == .warn(host: "evilflipcash.com"))
    }

    @Test func hostThatStartsWithOursWarns() throws {
        #expect(try check("https://flipcash.com.evil.tld/login") == .warn(host: "flipcash.com.evil.tld"))
    }

    @Test func trailingDotWarns() throws {
        #expect(try check("https://flipcash.com./login") == .warn(host: "flipcash.com."))
    }

    @Test func userInfoDoesNotStandInForTheHost() throws {
        #expect(try check("https://flipcash.com@evil.tld/") == .warn(host: "evil.tld"))
    }

    @Test func punycodeHostWarnsInPunycode() throws {
        // `xn--flipcsh-6fg.com` is `flipcаsh.com` with a Cyrillic `а`.
        #expect(try check("https://xn--flipcsh-6fg.com/login") == .warn(host: "xn--flipcsh-6fg.com"))
    }

    @Test func unicodeHostIsShownInPunycode() throws {
        #expect(try check("https://flipcаsh.com/login") == .warn(host: "xn--flipcsh-6fg.com"))
    }

    @Test func hostIsLowercased() throws {
        #expect(try check("https://X.com/flipcash") == .warn(host: "x.com"))
    }

    @Test func onlyTheHostIsShown() throws {
        #expect(try check("https://x.com:443/flipcash?utm=a#top") == .warn(host: "x.com"))
    }

    @Test func shownHostIsAlwaysASCII() throws {
        for string in ["https://flipcаsh.com/", "https://bücher.de/", "https://例え.jp/"] {
            guard case .warn(let host) = try check(string) else {
                Issue.record("\(string) did not warn")
                continue
            }
            let isASCII = host.allSatisfy(\.isASCII)
            #expect(isASCII, "\(host)")
        }
    }
}

@MainActor
@Suite struct LeavingFlipcashDialogTests {

    @Test func warningNamesTheHost() {
        let item = DialogItem.leavingFlipcash(host: "x.com") {}
        #expect(item.title == "You're leaving Flipcash")
        #expect(item.subtitle == "This link opens x.com. Flipcash will never ask for your Access Key on a website.")
        #expect(item.actions.map(\.title) == ["Cancel", "Open Link"])
        #expect(item.actions.map(\.kind) == [.standard, .subtle])
    }
}

@Suite struct SocialProfileURLTests {

    @Test func handleBecomesThePath() {
        #expect(URL.socialProfile(host: "x.com", handle: "flipcash")?.absoluteString == "https://x.com/flipcash")
    }

    @Test func spaceIsEncoded() {
        #expect(URL.socialProfile(host: "x.com", handle: "flip cash")?.absoluteString == "https://x.com/flip%20cash")
    }

    @Test func queryAndFragmentStayInThePath() {
        let url = URL.socialProfile(host: "t.me", handle: "a?b#c")
        #expect(url?.host() == "t.me")
        #expect(url?.query() == nil)
        #expect(url?.fragment() == nil)
    }

    @Test func emptyHandleHasNoURL() {
        #expect(URL.socialProfile(host: "x.com", handle: "") == nil)
    }

    @Test func slashHasNoURL() {
        #expect(URL.socialProfile(host: "discord.gg", handle: "../evil") == nil)
    }
}
