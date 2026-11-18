//
//  CatalogueBatchEventsTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// The invite, moderation, search, money-flow and Gallery Scan events, written as literals.
@MainActor
@Suite("Catalogue batch events", .serialized)
struct CatalogueBatchEventsTests {

    init() {
        Analytics.tokenSymbolResolver = nil
    }

    private static let fiat = ExchangedFiat.compute(
        onChainAmount: TokenAmount(quarks: 5_000_000, mint: .usdf),
        rate: Rate(fx: 1, currency: .usd),
        supplyQuarks: nil
    )

    // MARK: - Invite links and join requests -

    @Test("Invite link events carry State, and the Error on failure")
    func inviteLinks() throws {
        let created = Analytics.recordingSends { Analytics.groupInviteLinkCreated(error: nil) }
        let createdEvent = try created.single
        #expect(createdEvent.name == "Group: Invite Link Created")
        #expect(createdEvent.properties["State"] as? String == "Success")
        #expect(createdEvent.properties["Error"] == nil)

        let revoked = Analytics.recordingSends { Analytics.groupInviteLinkRevoked(error: ErrorRevokeInvite.notFound) }
        let revokedEvent = try revoked.single
        #expect(revokedEvent.name == "Group: Invite Link Revoked")
        #expect(revokedEvent.properties["State"] as? String == "Failure")
        #expect(revokedEvent.properties["Error"] as? String == "NotFound")
    }

    @Test("Join request events carry State and Error")
    func joinRequests() throws {
        let approved = try Analytics.recordingSends { Analytics.groupJoinRequestApproved(error: ErrorAdmitLobbyMember.denied) }.single
        #expect(approved.name == "Group: Join Request Approved")
        #expect(approved.properties["Error"] as? String == "Denied")

        let denied = try Analytics.recordingSends { Analytics.groupJoinRequestDenied(error: nil) }.single
        #expect(denied.name == "Group: Join Request Denied")
        #expect(denied.properties["State"] as? String == "Success")
    }

    // MARK: - Moderation -

    @Test("Member Silenced carries the duration", arguments: [
        (Flipcash.SilenceDuration.oneHour, "1 Hour"),
        (Flipcash.SilenceDuration.eightHours, "8 Hours"),
        (Flipcash.SilenceDuration.oneWeek, "1 Week"),
        (Flipcash.SilenceDuration.forever, "Forever"),
    ])
    func silenced(_ duration: Flipcash.SilenceDuration, _ expected: String) throws {
        let event = try Analytics.recordingSends { Analytics.groupMemberSilenced(duration: duration, error: nil) }.single
        #expect(event.name == "Group: Member Silenced")
        #expect(event.properties["Duration"] as? String == expected)
    }

    @Test("Member Removed reports a moderation error by name")
    func removed() throws {
        let event = try Analytics.recordingSends { Analytics.groupMemberRemoved(error: ErrorBanUser.cannotRestrictCreator) }.single
        #expect(event.name == "Group: Member Removed")
        #expect(event.properties["Error"] as? String == "CannotRestrictCreator")
    }

    @Test("Invite, lobby and moderation errors report their name, not Network", arguments: [
        (ErrorCreateInvite.tooManyInvites as Error, "TooManyInvites"),
        (ErrorRevokeInvite.denied, "Denied"),
        (ErrorAdmitLobbyMember.notInLobby, "NotInLobby"),
        (ErrorDenyLobbyMember.notFound, "NotFound"),
        (ErrorSilenceUser.cannotRestrictCreator, "CannotRestrictCreator"),
        (ErrorBanUser.denied, "Denied"),
        (ErrorBanUser.transportFailure, "Network"),
    ])
    func moderationErrors(_ error: Error, _ expected: String) {
        #expect(Analytics.chatResult(error) == expected)
    }

    // MARK: - Search and Currency Info -

    @Test("Search events")
    func search() throws {
        let opened = try Analytics.recordingSends { Analytics.searchOpened() }.single
        #expect(opened.name == "Search: Opened")

        let tapped = try Analytics.recordingSends { Analytics.searchResultTapped(.currency) }.single
        #expect(tapped.name == "Search: Result Tapped")
        #expect(tapped.properties["Result Type"] as? String == "Currency")
    }

    @Test("Token Info from Search sends the catalogue name")
    func tokenInfoFromSearch() throws {
        let event = try Analytics.recordingSends { Analytics.tokenInfoOpened(from: .openedFromSearch, mint: .usdf) }.single
        #expect(event.name == "Token Info: Opened From Search")
        #expect(event.properties["Mint"] as? String == PublicKey.usdf.base58)
    }

    @Test("Currency Info tiles and More rows map to the catalogue values", arguments: [
        (CurrencyInfoActions.Tile.send, "Send"),
        (.buy, "Buy"),
        (.buyIn, "Buy In"),
        (.transactions, "Transactions"),
        (.more, "More"),
    ])
    func tiles(_ tile: CurrencyInfoActions.Tile, _ expected: String) throws {
        let event = try Analytics.recordingSends { Analytics.tokenInfoTileTapped(tile: tile, mint: .usdf) }.single
        #expect(event.name == "Token Info: Tile Tapped")
        #expect(event.properties["Tile"] as? String == expected)
        #expect(event.properties["Mint"] as? String == PublicKey.usdf.base58)
    }

    @Test("More option and community chat events")
    func moreAndCommunity() throws {
        let more = try Analytics.recordingSends { Analytics.tokenInfoMoreOptionPicked(row: .withdraw, mint: .usdf) }.single
        #expect(more.name == "Token Info: More Option Picked")
        #expect(more.properties["Option"] as? String == "Withdraw")

        let chat = try Analytics.recordingSends { Analytics.tokenInfoCommunityChatTapped(mint: .usdf) }.single
        #expect(chat.name == "Token Info: Community Chat Tapped")
    }

    // MARK: - Money flow -

    @Test("Sent Cash carries its Context, and the count for a Group Send")
    func sentCash() throws {
        let direct = try Analytics.recordingSends { Analytics.sentCash(exchangedFiat: Self.fiat, context: .direct, error: nil) }.single
        #expect(direct.name == "Sent Cash")
        #expect(direct.properties["Context"] as? String == "Direct")
        #expect(direct.properties["Recipient Count"] == nil)

        let group = try Analytics.recordingSends { Analytics.sentCash(exchangedFiat: Self.fiat, context: .groupSend, recipientCount: 4, error: nil) }.single
        #expect(group.properties["Context"] as? String == "Group Send")
        #expect(group.properties["Recipient Count"] as? Double == 4)

        let request = try Analytics.recordingSends { Analytics.sentCash(exchangedFiat: Self.fiat, context: .paymentRequest, error: nil) }.single
        #expect(request.properties["Context"] as? String == "Payment Request")
    }

    @Test("Sent Boost carries the chat type and a failure")
    func sentBoost() throws {
        let event = try Analytics.recordingSends { Analytics.sentBoost(chatType: .group, exchangedFiat: Self.fiat, error: ErrorSendMessage.denied) }.single
        #expect(event.name == "Sent Boost")
        #expect(event.properties["State"] as? String == "Failure")
        #expect(event.properties["Chat Type"] != nil)
    }

    @Test("Payment Request events")
    func paymentRequests() throws {
        let created = try Analytics.recordingSends {
            Analytics.paymentRequestCreated(payerCount: 3, amount: Self.fiat.nativeAmount, error: nil)
        }.single
        #expect(created.name == "Payment Request: Created")
        #expect(created.properties["Payer Count"] as? Double == 3)
        #expect(created.properties["State"] as? String == "Success")

        let closed = try Analytics.recordingSends { Analytics.paymentRequestClosed(error: nil) }.single
        #expect(closed.name == "Payment Request: Closed")
    }

    // MARK: - Gallery Scan -

    @Test("A found code is Gallery Scan: Succeeded, with the tier as 1 to 3 and the time in ms")
    func galleryFound() throws {
        let event = try Analytics.recordingSends {
            Analytics.galleryScanFoundCode(tier: .quadrant, zoom: 2, elapsed: 1.25)
        }.single
        #expect(event.name == "Gallery Scan: Succeeded")
        #expect(event.properties["Tier"] as? Double == 2)
        #expect(event.properties["Zoom"] as? Double == 2)
        #expect(event.properties["Time"] as? Double == 1250)
    }

    @Test("Nothing found is Gallery Scan: Failed; only a cancel stops early")
    func galleryNothing() throws {
        let exhausted = try Analytics.recordingSends { Analytics.galleryScanFoundNothing(reason: .exhausted, elapsed: 3) }.single
        #expect(exhausted.name == "Gallery Scan: Failed")
        #expect(exhausted.properties["Time"] as? Double == 3000)
        #expect(Analytics.GalleryScanMiss.cancelled.stoppedEarly)
        #expect(!Analytics.GalleryScanMiss.exhausted.stoppedEarly)
    }

    @Test("Gallery tiers map to 1, 2 and 3")
    func galleryTiers() {
        #expect(Analytics.galleryTier(.wholeImage) == 1)
        #expect(Analytics.galleryTier(.quadrant) == 2)
        #expect(Analytics.galleryTier(.window) == 3)
    }

    // MARK: - iOS-only events moved to the catalogue -

    @Test("Create Account and Auto-login complete carry no properties")
    func accountEvents() throws {
        let create = try Analytics.recordingSends { Analytics.createAccount() }.single
        #expect(create.name == "Create Account")
        #expect(create.properties.isEmpty)

        let login = try Analytics.recordingSends { Analytics.autoLoginComplete() }.single
        #expect(login.name == "Auto-login complete")
    }


    @Test("Currency Launch names the method in the event name")
    func currencyLaunch() throws {
        let event = try Analytics.recordingSends {
            Analytics.currencyLaunch(method: .currency, launchedMint: .jeffy, paymentMint: .usdf, exchangedFiat: Self.fiat, successful: true)
        }.single
        #expect(event.name == "Currency Launch With Currency")
        #expect(event.properties["State"] as? String == "Success")
    }
}

