//
//  DeepLinkControllerTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("DeepLinkController routing")
struct DeepLinkControllerTests {

    private let sessionAuthenticator = SessionAuthenticator(container: Container())

    private func makeController() -> DeepLinkController {
        DeepLinkController(sessionAuthenticator: sessionAuthenticator)
    }

    @Test("A recognized route resolves to an action, so open reports it handled")
    func recognizedRoute_isHandled() {
        #expect(makeController().open(URL(string: "flipcash://give")!) == true)
    }

    @Test("An ordinary web URL resolves to no action, so open reports it unhandled and the caller opens it externally")
    func ordinaryWebURL_isNotHandled() {
        #expect(makeController().open(URL(string: "https://apple.com")!) == false)
    }

    /// `Route` matches on path alone, so a foreign host's path can read as one of ours —
    /// `discord.gg/<invite>` as a handle, `evil.com/c/#/e=…` as a cash link. Chat text and scanned
    /// QR codes both arrive here, and neither came through the associated-domains entitlement.
    ///
    /// Asserted on `handle(open:)` rather than `open(_:)` so nothing executes: `.login` on a
    /// logged-out session switches the account to whatever seed the link carried, which is the
    /// reason this gate exists and not something to run in a test.
    @Test("A foreign host names no action, however much its path looks like one of ours",
          arguments: [
              "https://discord.gg/rattlepokemon",
              "https://t.me/somechannel",
              "https://github.com/flipcash",
              "https://example.com/3f2504e0-4f89-41d3-9a0c-0305e82c3301",
              "https://evil.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW",
              "https://evil.com/login#e=HQPkfAZjgpGGANQfUNPKvW",
              "https://send.flipcash.com.evil.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW",
          ])
    func foreignHost_namesNoAction(urlString: String) {
        #expect(makeController().handle(open: URL(string: urlString)!) == nil)
    }

    /// A jump wrapper is one of ours; the host it points at still has to be.
    @Test("A jump wrapper cannot smuggle a foreign host past the gate")
    func jumpWrapper_doesNotLaunderAForeignHost() throws {
        let inner = "https://send.flipcash.com.evil.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW"
        let wrapper = "https://jump.flipcash.com/#source=" + inner.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        )!

        #expect(makeController().handle(open: try #require(URL(string: wrapper))) == nil)
    }

    @Test("The hosts the app claims still name an action",
          arguments: [
              "https://send.flipcash.com/c/#/e=HQPkfAZjgpGGANQfUNPKvW",
              "https://app.flipcash.com/token/54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25",
              "https://flipcash.com/brandon",
              "https://flipcash.com/3f2504e0-4f89-41d3-9a0c-0305e82c3301",
          ])
    func claimedHost_namesAnAction(urlString: String) {
        #expect(makeController().handle(open: URL(string: urlString)!) != nil)
    }

    // MARK: - Person links -

    private static let userID = UUID(uuidString: "3f2504e0-4f89-41d3-9a0c-0305e82c3301")!

    @Test("A bare user id opens that user's profile, not the tipcard",
          arguments: [
              "https://flipcash.com/3f2504e0-4f89-41d3-9a0c-0305e82c3301",
              "https://app.flipcash.com/3f2504e0-4f89-41d3-9a0c-0305e82c3301",
          ])
    func bareUserID_opensProfile(urlString: String) throws {
        let kind = try #require(makeController().handle(open: URL(string: urlString)!)?.kind)
        guard case .profile(let identifier) = kind else {
            Issue.record("\(urlString) should dispatch .profile, got \(kind.analyticsName)")
            return
        }
        #expect(identifier == .userID(Self.userID))
    }

    @Test("A bare handle opens that user's profile, not the tipcard")
    func bareHandle_opensProfile() throws {
        let kind = try #require(makeController().handle(open: URL(string: "https://flipcash.com/Taylor")!)?.kind)
        guard case .profile(let identifier) = kind else {
            Issue.record("A handle link should dispatch .profile, got \(kind.analyticsName)")
            return
        }
        #expect(identifier == .username(try #require(Username("taylor"))))
    }

    @Test("The legacy /tip/ link still opens the tipcard")
    func legacyTipLink_opensTipcard() throws {
        let url = URL(string: "https://app.flipcash.com/tip/3f2504e0-4f89-41d3-9a0c-0305e82c3301")!
        let kind = try #require(makeController().handle(open: url)?.kind)
        guard case .tip(let userID) = kind else {
            Issue.record("/tip/ should dispatch .tip, got \(kind.analyticsName)")
            return
        }
        #expect(userID == Self.userID)
    }

    @Test("The viewer's own id or handle is known to be their own without a lookup")
    func ownLink_isOwn() throws {
        let me = try #require(Username("me"))
        #expect(DeepLinkAction.isOwnLink(.userID(Self.userID), selfUserID: Self.userID, selfUsername: me))
        #expect(DeepLinkAction.isOwnLink(.username(me), selfUserID: Self.userID, selfUsername: me))
    }

    @Test("Someone else's id or handle is not the viewer's own")
    func otherLink_isNotOwn() throws {
        let me = try #require(Username("me"))
        #expect(!DeepLinkAction.isOwnLink(.userID(UUID()), selfUserID: Self.userID, selfUsername: me))
        #expect(!DeepLinkAction.isOwnLink(.username(try #require(Username("taylor"))), selfUserID: Self.userID, selfUsername: me))
    }

    @Test("A handle can't be matched to the viewer before their own profile has loaded")
    func ownHandle_beforeProfileLoads_isNotOwn() throws {
        let me = try #require(Username("me"))
        #expect(!DeepLinkAction.isOwnLink(.username(me), selfUserID: Self.userID, selfUsername: nil))
    }

    @Test("A duplicate in-flight open is reported handled without re-processing")
    func duplicateInFlightOpen_isDeduped() {
        let controller = makeController()
        // The first open enters the in-flight set; its async cleanup can't run before the next
        // synchronous call, so the immediate duplicate is short-circuited to handled.
        _ = controller.open(URL(string: "https://apple.com")!)
        #expect(controller.open(URL(string: "https://apple.com")!) == true)
    }

    // `https://apple.com` names no action, so a processed open returns false and a deduped one
    // returns true — the return value tells the two apart.
    @Test("A repeat that lands after the first action finished is still deduped within the window")
    func repeatAfterCompletion_isDedupedWithinWindow() async throws {
        let controller = DeepLinkController(sessionAuthenticator: sessionAuthenticator, repeatWindow: .seconds(60))
        let url = URL(string: "https://apple.com")!
        _ = controller.open(url)
        // Let the first open's task run to completion before the repeat arrives.
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.open(url) == true)
    }

    @Test("The same URL is processed again once the window has passed")
    func repeatAfterWindow_isProcessed() async throws {
        let controller = DeepLinkController(sessionAuthenticator: sessionAuthenticator, repeatWindow: .milliseconds(1))
        let url = URL(string: "https://apple.com")!
        _ = controller.open(url)
        try await waitUntil { controller.open(url) == false }
    }
}
