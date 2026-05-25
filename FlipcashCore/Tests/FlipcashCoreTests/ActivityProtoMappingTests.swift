//
//  ActivityProtoMappingTests.swift
//  FlipcashCore
//

import Foundation
import SwiftProtobuf
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("Activity proto → model mapping")
struct ActivityProtoMappingTests {

    private static let notificationId = Data((0..<32).map { Byte($0) })
    private static let mintBytes = Data(repeating: 1, count: 32)
    private static let vaultBytes = Data(repeating: 42, count: 32)

    private static func basePaymentAmount() -> Flipcash_Common_V1_CryptoPaymentAmount {
        var amount = Flipcash_Common_V1_CryptoPaymentAmount()
        amount.currency = "usd"
        amount.nativeAmount = 5.0
        amount.quarks = 5_000_000
        amount.mint.value = Self.mintBytes
        return amount
    }

    private func baseNotification(
        state: Flipcash_Activity_V1_NotificationState = .completed,
        metadata: Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata? = nil,
        timestampSeconds: Int64 = 1_700_000_000,
    ) -> Flipcash_Activity_V1_Notification {
        var proto = Flipcash_Activity_V1_Notification()
        proto.id.value = Self.notificationId
        proto.localizedText = "Test notification"
        var ts = SwiftProtobuf.Google_Protobuf_Timestamp()
        ts.seconds = timestampSeconds
        proto.ts = ts
        proto.state = state
        proto.paymentAmount = Self.basePaymentAmount()
        if let metadata { proto.additionalMetadata = metadata }
        return proto
    }

    // MARK: Top-level fields

    @Test("Localized text and timestamp pass through")
    func textAndTimestamp() throws {
        let proto = baseNotification(timestampSeconds: 1_700_000_000)
        let activity = try Activity(proto)
        #expect(activity.title == "Test notification")
        #expect(activity.date == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Activity id is decoded from the proto bytes")
    func idDecoded() throws {
        let proto = baseNotification()
        let activity = try Activity(proto)
        #expect(activity.id.bytes == [Byte](Self.notificationId))
    }

    // MARK: State mapping
    //
    // `Flipcash_Activity_V1_NotificationState` is not `Sendable`, so it can't be
    // passed via @Test arguments — three small tests instead of parameterization.

    @Test("NOTIFICATION_STATE_UNKNOWN maps to .unknown")
    func stateUnknown() throws {
        let activity = try Activity(baseNotification(state: .unknown))
        #expect(activity.state == .unknown)
    }

    @Test("NOTIFICATION_STATE_PENDING maps to .pending")
    func statePending() throws {
        let activity = try Activity(baseNotification(state: .pending))
        #expect(activity.state == .pending)
    }

    @Test("NOTIFICATION_STATE_COMPLETED maps to .completed")
    func stateCompleted() throws {
        let activity = try Activity(baseNotification(state: .completed))
        #expect(activity.state == .completed)
    }

    // MARK: Kind mapping — payload-less variants + nil (sentCrypto has its own test)

    @Test("Notification metadata maps to Activity.Kind with no carried metadata", arguments: [
        (
            Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata.gaveCrypto(Flipcash_Activity_V1_GaveCryptoNotificationMetadata()),
            Activity.Kind.gave,
        ),
        (
            .receivedCrypto(Flipcash_Activity_V1_ReceivedCryptoNotificationMetadata()),
            .received,
        ),
        (
            .withdrewCrypto(Flipcash_Activity_V1_WithdrewCryptoNotificationMetadata()),
            .withdrew,
        ),
        (
            .depositedCrypto(Flipcash_Activity_V1_DepositedCryptoNotificationMetadata()),
            .deposited,
        ),
        (
            .boughtCrypto(Flipcash_Activity_V1_BoughtCryptoNotificationMetadata()),
            .bought,
        ),
        (
            .soldCrypto(Flipcash_Activity_V1_SoldCryptoNotificationMetadata()),
            .sold,
        ),
    ] as [(Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata, Activity.Kind)])
    func kindMappingWithoutPayload(
        metadata: Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata,
        expected: Activity.Kind,
    ) throws {
        let activity = try Activity(baseNotification(metadata: metadata))
        #expect(activity.kind == expected)
        #expect(activity.metadata == nil)
    }

    @Test("sentCrypto metadata maps to Kind.cashLink AND populates CashLinkMetadata")
    func kindSentCashLink() throws {
        var sent = Flipcash_Activity_V1_SentCryptoNotificationMetadata()
        sent.vault.value = Self.vaultBytes
        sent.canInitiateCancelAction = true

        let activity = try Activity(baseNotification(metadata: .sentCrypto(sent)))
        let expectedVault = try PublicKey(Self.vaultBytes)

        #expect(activity.kind == .cashLink)
        #expect(activity.metadata == .cashLink(.init(vault: expectedVault, canCancel: true)))
    }

    @Test("Missing additionalMetadata maps to Kind.unknown with no Metadata")
    func kindUnknownWhenAbsent() throws {
        let activity = try Activity(baseNotification(metadata: nil))
        #expect(activity.kind == .unknown)
        #expect(activity.metadata == nil)
    }

    // MARK: Missing payment amount

    @Test("Notification without a payment amount throws")
    func missingPaymentAmountThrows() {
        var proto = Flipcash_Activity_V1_Notification()
        proto.id.value = Self.notificationId
        proto.localizedText = "no amount"
        #expect(throws: (any Error).self) {
            _ = try Activity(proto)
        }
    }
}
