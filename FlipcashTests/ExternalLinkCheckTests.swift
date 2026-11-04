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

    // MARK: - Trusted hosts

    private func check(_ string: String, trusting hosts: Set<String>) throws -> ExternalLinkCheck {
        ExternalLinkCheck(url: try #require(URL(string: string)), trustedHosts: hosts)
    }

    @Test func trustedHostOpens() throws {
        #expect(try check("https://x.com/flipcash", trusting: ["x.com"]) == .open)
    }

    @Test func trustedHostOpensInAnyCase() throws {
        #expect(try check("https://X.com/flipcash", trusting: ["x.com"]) == .open)
    }

    @Test func trustedHostDoesNotCoverSubdomain() throws {
        #expect(try check("https://mail.x.com/inbox", trusting: ["x.com"]) == .warn(host: "mail.x.com"))
    }

    @Test func trustedSubdomainDoesNotCoverParent() throws {
        #expect(try check("https://x.com/", trusting: ["mail.x.com"]) == .warn(host: "x.com"))
    }

    @Test func trustedHostDoesNotCoverLookalikeSuffix() throws {
        #expect(try check("https://x.com.evil.tld/", trusting: ["x.com"]) == .warn(host: "x.com.evil.tld"))
    }

    @Test func homographDoesNotMatchTrustedASCIIHost() throws {
        guard case .warn(let shown) = try check("https://flipcаsh.io/", trusting: ["flipcash.io"]) else {
            Issue.record("homograph did not warn")
            return
        }
        #expect(shown.hasPrefix("xn--"))
        #expect(try check("https://flipcаsh.io/", trusting: [shown]) == .open)
    }
}

@MainActor
@Suite struct LeavingFlipcashDialogTests {

    private let defaults = UserDefaults(suiteName: "trusted-websites-\(UUID())")!

    private func dialog(
        host: String = "x.com",
        label: String? = nil,
        opened: @escaping () -> Void = {}
    ) -> (DialogItem, TrustedWebsites) {
        let store = TrustedWebsites(defaults: defaults)
        return (DialogItem.leavingFlipcash(host: host, label: label, trustedWebsites: store, open: opened), store)
    }

    @Test func warningNamesTheHost() {
        let (item, _) = dialog()
        #expect(item.style == .standard)
        #expect(item.title == "You're Leaving Flipcash")
        #expect(item.subtitle == "This will open x.com. Never share your Access Key with a website")
        #expect(item.actions.map(\.title) == ["Open Website", "Cancel"])
        #expect(item.actions.map(\.kind) == [.standard, .subtle])
        #expect(item.checkbox == DialogCheckbox(label: "Don't ask again for x.com"))
    }

    @Test func maskedLinkQuotesItsLabelBesideTheHost() {
        let (item, _) = dialog(label: "my site")
        #expect(item.title == "You're Leaving Flipcash")
        #expect(item.subtitle == "“my site” will open x.com. Never share your Access Key with a website.")
        #expect(item.checkbox == DialogCheckbox(label: "Don't ask again for x.com"))
    }

    @Test func punycodeHostIsTheLabel() {
        let (item, _) = dialog(host: "xn--flipcsh-2fg.io")
        #expect(item.checkbox?.label == "Don't ask again for xn--flipcsh-2fg.io")
    }

    @Test func openWebsiteCheckedTrustsTheHost() {
        var opened = false
        let (item, store) = dialog { opened = true }
        item.actions[0].perform(isChecked: true)
        #expect(opened)
        #expect(store.hosts == ["x.com"])
    }

    @Test func openWebsiteUncheckedSavesNothing() {
        var opened = false
        let (item, store) = dialog { opened = true }
        item.actions[0].perform(isChecked: false)
        #expect(opened)
        #expect(store.entries.isEmpty)
    }

    @Test func cancelCheckedSavesNothing() {
        var opened = false
        let (item, store) = dialog { opened = true }
        item.actions[1].perform(isChecked: true)
        #expect(!opened)
        #expect(store.entries.isEmpty)
    }

    @Test func dismissSavesNothing() {
        let (item, store) = dialog()
        item.onDismiss?()
        #expect(store.entries.isEmpty)
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
