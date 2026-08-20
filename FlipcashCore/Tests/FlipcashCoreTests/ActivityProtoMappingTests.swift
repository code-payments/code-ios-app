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

    // MARK: Kind mapping — payload-less variants + nil (indirectlySentCrypto has its own test)

    @Test("Notification metadata maps to Activity.Kind with no carried metadata", arguments: [
        (
            Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata.directlySentCrypto(Flipcash_Activity_V1_DirectlySentCryptoNotificationMetadata()),
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
        (
            .swappedCrypto(Flipcash_Activity_V1_SwappedCryptoNotificationMetadata()),
            .swapped,
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

    @Test("indirectlySentCrypto metadata maps to Kind.cashLink AND populates CashLinkMetadata")
    func kindSentCashLink() throws {
        var sent = Flipcash_Activity_V1_IndirectlySentCryptoNotificationMetadata()
        sent.vault.value = Self.vaultBytes
        sent.canInitiateCancelAction = true

        let activity = try Activity(baseNotification(metadata: .indirectlySentCrypto(sent)))
        let expectedVault = try PublicKey(Self.vaultBytes)

        #expect(activity.kind == .cashLink)
        #expect(activity.metadata == .cashLink(.init(vault: expectedVault, canCancel: true)))
    }

    @Test("swappedCrypto maps to Kind.swapped AND populates SwapMetadata")
    func kindSwapped() throws {
        let fromMintBytes = Data(repeating: 7, count: 32)
        let toMintBytes   = Data(repeating: 9, count: 32)

        var swapped = Flipcash_Activity_V1_SwappedCryptoNotificationMetadata()
        swapped.from.mint.value   = fromMintBytes
        swapped.from.quarks       = 5_000_000
        swapped.from.nativeAmount = 5.0
        swapped.from.currency     = "usd"

        var toAmount = Flipcash_Common_V1_CryptoPaymentAmount()
        toAmount.mint.value   = toMintBytes
        toAmount.quarks       = 100_000_000
        toAmount.nativeAmount = 4.95
        toAmount.currency     = "usd"
        swapped.to = .toAmount(toAmount)

        swapped.fee.nativeAmount = 0.05
        swapped.fee.currency     = "usd"
        swapped.swapState        = .succeeded

        let activity = try Activity(baseNotification(metadata: .swappedCrypto(swapped)))

        #expect(activity.kind == .swapped)
        guard case .swap(let meta)? = activity.metadata else {
            Issue.record("expected .swap metadata")
            return
        }
        #expect(meta.fromMint == (try PublicKey(fromMintBytes)))
        #expect(meta.fromQuarks == 5_000_000)
        #expect(meta.fromFiat.doubleValue == 5.0)
        #expect(meta.toMint == (try PublicKey(toMintBytes)))
        #expect(meta.toQuarks == 100_000_000)
        #expect(meta.toFiat?.doubleValue == 4.95)
        #expect(meta.fee.doubleValue == 0.05)
        #expect(meta.state == .succeeded)
    }

    @Test("swappedCrypto with only a destination mint leaves the To amount nil")
    func kindSwappedPendingDestination() throws {
        var swapped = Flipcash_Activity_V1_SwappedCryptoNotificationMetadata()
        swapped.from.mint.value   = Self.mintBytes
        swapped.from.quarks       = 1
        swapped.from.nativeAmount = 1.0
        swapped.from.currency     = "usd"
        swapped.toMint.value      = Self.vaultBytes
        swapped.fee.nativeAmount  = 0.01
        swapped.fee.currency      = "usd"
        swapped.swapState         = .pending

        let activity = try Activity(baseNotification(metadata: .swappedCrypto(swapped)))

        #expect(activity.kind == .swapped)
        guard case .swap(let meta)? = activity.metadata else {
            Issue.record("expected .swap metadata")
            return
        }
        #expect(meta.toQuarks == nil)
        #expect(meta.toFiat == nil)
        #expect(meta.state == .pending)
    }

    @Test("Missing additionalMetadata maps to Kind.unknown with no Metadata")
    func kindUnknownWhenAbsent() throws {
        let activity = try Activity(baseNotification(metadata: nil))
        #expect(activity.kind == .unknown)
        #expect(activity.metadata == nil)
    }

    // MARK: Text substitutions

    @Test("Title renders positional placeholders using each substitution's fallback")
    func titleAppliesSubstitutionFallbacks() throws {
        var proto = baseNotification()
        proto.localizedText = "You received cash from {0}"
        proto.textSubstitutions = [
            .with {
                $0.fallback = "+15551234567"
                $0.phoneNumberToContactName = .with { $0.value = "+15551234567" }
            },
        ]

        let activity = try Activity(proto)
        #expect(activity.title == "You received cash from +15551234567")
    }

    @Test("Substitutions map phone and user-id kinds")
    func substitutionKindsMap() throws {
        let userUUID = UUID()
        var proto = baseNotification()
        proto.localizedText = "{0} and {1}"
        proto.textSubstitutions = [
            .with {
                $0.fallback = "+15551234567"
                $0.phoneNumberToContactName = .with { $0.value = "+15551234567" }
            },
            .with {
                $0.fallback = "Alice"
                $0.userIDToDisplayName = .with { $0.value = userUUID.data }
            },
        ]

        let activity = try Activity(proto)
        #expect(activity.textSubstitutions == [
            .phoneNumber(e164: "+15551234567", fallback: "+15551234567"),
            .userID(userUUID, fallback: "Alice"),
        ])
    }

    // MARK: Invalid payment amount

    // proto3 always materialises `paymentAmount` as a default
    // `CryptoPaymentAmount` (currency=""), so the failure surfaces at currency
    // lookup. Pin the specific error type so a future refactor that reorders
    // the validation inside `Activity.init` fails this test instead of silently
    // throwing from a different site.

    @Test("Default-empty CryptoPaymentAmount fails at currency lookup with CurrencyCode.Error")
    func emptyCurrencyInPaymentAmountThrows() {
        var proto = Flipcash_Activity_V1_Notification()
        proto.id.value = Self.notificationId
        proto.localizedText = "no amount"
        #expect(throws: CurrencyCode.Error.self) {
            _ = try Activity(proto)
        }
    }

    // MARK: Swap notifications without a top-level payment amount

    // The contract documents `payment_amount` as absent for multi-mint
    // operations — those amounts are carried in `additional_metadata` instead.
    // A swap notification must therefore still map with no top-level amount.

    @Test("swappedCrypto without a top-level paymentAmount still maps, deriving the amount from the From leg")
    func swappedWithoutPaymentAmount() throws {
        let fromMintBytes = Data(repeating: 7, count: 32)
        let toMintBytes   = Data(repeating: 9, count: 32)

        var swapped = Flipcash_Activity_V1_SwappedCryptoNotificationMetadata()
        swapped.from.mint.value   = fromMintBytes
        swapped.from.quarks       = 5_000_000
        swapped.from.nativeAmount = 5.0
        swapped.from.currency     = "usd"

        var toAmount = Flipcash_Common_V1_CryptoPaymentAmount()
        toAmount.mint.value   = toMintBytes
        toAmount.quarks       = 100_000_000
        toAmount.nativeAmount = 4.95
        toAmount.currency     = "usd"
        swapped.to = .toAmount(toAmount)

        swapped.fee.nativeAmount = 0.05
        swapped.fee.currency     = "usd"
        swapped.swapState        = .succeeded

        var proto = Flipcash_Activity_V1_Notification()
        proto.id.value      = Self.notificationId
        proto.localizedText = "Converted"
        proto.state         = .completed
        proto.additionalMetadata = .swappedCrypto(swapped)
        // Deliberately no `proto.paymentAmount`.

        let activity = try Activity(proto)

        #expect(activity.kind == .swapped)
        #expect(activity.exchangedFiat.mint == (try PublicKey(fromMintBytes)))
        #expect(activity.exchangedFiat.onChainAmount.quarks == 5_000_000)
        #expect(activity.exchangedFiat.nativeAmount.value == Decimal(5.0))
        #expect(activity.swapMetadata?.toQuarks == 100_000_000)
    }

    @Test("A pending swap without a top-level paymentAmount still maps")
    func pendingSwapWithoutPaymentAmount() throws {
        var swapped = Flipcash_Activity_V1_SwappedCryptoNotificationMetadata()
        swapped.from.mint.value   = Self.mintBytes
        swapped.from.quarks       = 1_000_000
        swapped.from.nativeAmount = 1.0
        swapped.from.currency     = "usd"
        swapped.toMint.value      = Self.vaultBytes
        swapped.fee.nativeAmount  = 0.01
        swapped.fee.currency      = "usd"
        swapped.swapState         = .pending

        var proto = Flipcash_Activity_V1_Notification()
        proto.id.value      = Self.notificationId
        proto.localizedText = "Converting"
        proto.state         = .pending
        proto.additionalMetadata = .swappedCrypto(swapped)

        let activity = try Activity(proto)

        #expect(activity.kind == .swapped)
        #expect(activity.state == .pending)
        #expect(activity.exchangedFiat.mint == (try PublicKey(Self.mintBytes)))
        #expect(activity.swapMetadata?.state == .pending)
    }
}
