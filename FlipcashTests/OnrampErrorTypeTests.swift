//
//  OnrampErrorTypeTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

@Suite("OnrampErrorResponse.ErrorType")
struct OnrampErrorTypeTests {

    typealias ErrorType = OnrampErrorResponse.ErrorType

    // MARK: - init(coinbaseCode:)

    @Test(
        "init(coinbaseCode:) maps the raw Coinbase code to the matching case",
        arguments: [
            ("ERROR_CODE_GUEST_INVALID_CARD",    ErrorType.invalidCard),
            ("ERROR_CODE_GUEST_CARD_NOT_DEBIT",  .invalidCardNotDebit),
            ("ERROR_CODE_ASSET_NOT_TRADABLE",    .assetNotTradable),
            ("GUEST_INVALID_CARD",               .invalidCard),
            ("ASSET_NOT_TRADABLE",               .assetNotTradable),
            ("error_code_guest_invalid_card",    .invalidCard),
            ("ERROR_CODE_NONEXISTENT",           .unknown),
            ("",                                 .unknown),
        ]
    )
    func decodesCoinbaseCode(_ code: String, _ expected: ErrorType) {
        #expect(ErrorType(coinbaseCode: code) == expected)
    }

    // MARK: - Copy equivalence

    @Test(
        "Equivalent ErrorType cases share both title and subtitle",
        arguments: [
            (ErrorType.invalidCardNotDebit, ErrorType.invalidCard),
            (.assetNotTradable,             .networkNotTradable),
            (.cardHardDeclined,             .cardSoftDeclined),
            (.guestTransactionBuyFailed,    .cardSoftDeclined),
            (.internal,                     .transactionFailed),
            (.invalidRequest,               .guestTransactionSendFailed),
            (.permissionDenied,             .unknown),
        ]
    )
    func casesShareCopy(_ subject: ErrorType, _ reference: ErrorType) {
        #expect(subject.title == reference.title)
        #expect(subject.subtitle == reference.subtitle)
    }

    // MARK: - Copy anchors

    @Test("invalidCard surfaces as Debit Cards Only")
    func invalidCardAnchor() {
        #expect(ErrorType.invalidCard.title == "Debit Cards Only")
    }

    @Test("assetNotTradable surfaces as a regional availability issue, not a card decline")
    func assetNotTradableAnchor() {
        #expect(ErrorType.assetNotTradable.title == "Your Region Isn't Supported")
    }

    @Test("Bank-declined cases direct the user to contact their bank")
    func bankDeclineSubtitleAnchor() {
        #expect(ErrorType.cardSoftDeclined.subtitle.contains("contact your bank"))
    }

    @Test("cardRiskDeclined shares the Card Declined title but keeps its own remediation")
    func cardRiskDeclinedTitleSharedSubtitleDistinct() {
        #expect(ErrorType.cardRiskDeclined.title == ErrorType.cardSoftDeclined.title)
        #expect(ErrorType.cardRiskDeclined.title == "Card Declined")
        #expect(ErrorType.cardRiskDeclined.subtitle != ErrorType.cardSoftDeclined.subtitle)
    }

    @Test("Server-side failures direct the user to wait for Coinbase to investigate")
    func serverFailureSubtitleAnchor() {
        #expect(ErrorType.transactionFailed.subtitle.contains("Coinbase team has been notified"))
    }

    @Test("Send-path failures explain the refund and ask the user to retry later")
    func sendFailureSubtitleAnchor() {
        #expect(ErrorType.guestTransactionSendFailed.subtitle.contains("working with the Coinbase team"))
    }

    @Test("unknown and permissionDenied direct the user to support email")
    func supportEmailSubtitleAnchor() {
        #expect(ErrorType.unknown.subtitle.contains("support@flipcash.com"))
    }
}
