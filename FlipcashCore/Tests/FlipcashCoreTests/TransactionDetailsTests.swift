//
//  TransactionDetailsTests.swift
//  FlipcashCore
//

import Foundation
import Testing
@testable import FlipcashCore

/// The details mapper's readings of an activity — which kind, which status, which
/// actions.
///
/// Mirrors Android's `TransactionDetailsMapperTest`: the row and the details
/// screen read the same entry through the same helpers, and the failure worth
/// catching is the two disagreeing about what the entry was.
@Suite("Transaction details mapping")
struct TransactionDetailsTests {

    private let counterparty = Activity.Counterparty.user(UUID())
    private let vault = try! PublicKey(base58: "11111111111111111111111111111111")

    private func activity(
        kind: Activity.Kind,
        title: String = "Sent",
        state: Activity.State = .completed,
        metadata: Activity.Metadata? = nil,
        counterparty: Activity.Counterparty? = nil,
        amount: ExchangedFiat? = nil,
    ) -> Activity {
        Activity(
            id: .jeffy,
            state: state,
            kind: kind,
            title: title,
            exchangedFiat: amount ?? Self.usd(20),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            metadata: metadata,
            counterparty: counterparty,
        )
    }

    private static func usd(_ value: Decimal, mint: PublicKey = .usdf) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: TokenAmount(wholeTokens: value, mint: mint),
            nativeAmount: .usd(value),
            currencyRate: .oneToOne,
        )
    }

    private func swapMetadata(
        toFiat: FiatAmount? = .usd(19),
        fee: FiatAmount = .usd(1),
        state: Activity.SwapMetadata.State = .succeeded,
    ) -> Activity.Metadata {
        .swap(
            Activity.SwapMetadata(
                fromMint: .usdf,
                fromQuarks: 20_000_000,
                fromFiat: .usd(20),
                toMint: .jeffy,
                toQuarks: toFiat == nil ? nil : 19_000_000,
                toFiat: toFiat,
                fee: fee,
                state: state,
            )
        )
    }

    // MARK: - Kind

    @Test("The verb separates a tip from a plain send")
    func verbSeparatesTipFromSend() {
        let tipped = TransactionDetails(activity: activity(kind: .gave, title: "Tipped", counterparty: counterparty))
        let sent = TransactionDetails(activity: activity(kind: .gave, title: "Sent", counterparty: counterparty))

        #expect(tipped.kind == .tipped)
        #expect(sent.kind == .sent)
    }

    @Test("A send with nobody named is a bill handed over, not a send")
    func sendWithNoCounterpartyIsCash() {
        let details = TransactionDetails(activity: activity(kind: .gave))

        #expect(details.kind == .gaveCash)
        // Nobody to head the screen with, so the kind's own heading stands.
        #expect(details.heading == nil)
        #expect(details.title == "You gave cash")
        #expect(details.subtitle == "In Person")
    }

    @Test("A receive with nobody named is cash taken in person")
    func receiveWithNoCounterpartyIsCash() {
        let details = TransactionDetails(activity: activity(kind: .received, title: "Received"))

        #expect(details.kind == .receivedCash)
        #expect(details.subtitle == "In Person")
    }

    @Test("A resolved counterparty heads the screen")
    func resolvedCounterpartyHeadsTheScreen() {
        let details = TransactionDetails(
            activity: activity(kind: .received, title: "Received", counterparty: counterparty),
            counterpartyName: "Sally The Streamer",
        )

        #expect(details.kind == .received)
        #expect(details.heading == "Sally The Streamer")
        #expect(details.title == "Sally The Streamer")
        #expect(details.subtitle == nil)
        #expect(details.signPrefix == "+")
    }

    @Test("An unresolved name leaves the heading to the kind, but still opens the chat")
    func unresolvedNameFallsBackToTheKind() {
        // Unlike Android, the chat action rides on the counterparty's id rather
        // than a resolved profile: the conversation screen derives its own header
        // from the id, so a name that hasn't landed yet doesn't withhold it.
        let details = TransactionDetails(activity: activity(kind: .received, title: "Received", counterparty: counterparty))

        #expect(details.heading == nil)
        #expect(details.title == "You received")
        #expect(details.canViewInChat)
    }

    @Test("A phone-number counterparty has no conversation to open")
    func phoneCounterpartyHasNoChat() {
        let details = TransactionDetails(activity: activity(kind: .gave, counterparty: .phone("+15551234567")))

        #expect(details.kind == .sent)
        #expect(details.canViewInChat == false)
    }

    // MARK: - Actions

    @Test("Only an open cash link can be cancelled")
    func onlyAnOpenCashLinkCanBeCancelled() {
        func cashLink(canCancel: Bool, state: Activity.State) -> TransactionDetails {
            TransactionDetails(
                activity: activity(
                    kind: .cashLink,
                    state: state,
                    metadata: .cashLink(Activity.CashLinkMetadata(vault: vault, canCancel: canCancel)),
                )
            )
        }

        let open = cashLink(canCancel: true, state: .pending)

        #expect(open.kind == .sentCashLink)
        #expect(open.canCancel)
        #expect(cashLink(canCancel: false, state: .pending).canCancel == false)
        // Claimed: the link is spent, whatever the cancel flag still says.
        #expect(cashLink(canCancel: true, state: .completed).canCancel == false)
        #expect(TransactionDetails(activity: activity(kind: .gave, counterparty: counterparty)).canCancel == false)
    }

    // MARK: - Conversions

    @Test("A convert names both mints and draws both sides")
    func convertNamesBothMints() {
        let details = TransactionDetails(
            activity: activity(kind: .swapped, title: "Converted", metadata: swapMetadata()),
            fromTokenName: "Dollars",
            toTokenName: "Jeffy",
        )

        #expect(details.kind == .convert)
        #expect(details.subtitle == "Dollars → Jeffy")
        #expect(details.fee == .usd(1))
        #expect(details.received == .usd(19))
        #expect(details.status == .completed)
        // Unlike Android, a conversion renders unsigned: the row it opens from
        // shows the source leg without a sign, and the two must agree.
        #expect(details.signPrefix == nil)
    }

    @Test("A half-resolved conversion pair says nothing rather than half of it")
    func halfResolvedConversionHasNoSubtitle() {
        let details = TransactionDetails(
            activity: activity(kind: .swapped, title: "Converted", metadata: swapMetadata()),
            fromTokenName: "Dollars",
        )

        #expect(details.subtitle == nil)
    }

    @Test("A failed swap fails the entry, whatever the notification says")
    func failedSwapFailsTheEntry() {
        // The entry itself completes as soon as the source side is debited.
        let details = TransactionDetails(
            activity: activity(
                kind: .swapped,
                title: "Converted",
                state: .completed,
                metadata: swapMetadata(toFiat: nil, fee: .usd(0), state: .failed),
            )
        )

        #expect(details.status == .failed)
        #expect(details.received == nil)
    }

    @Test("A pending swap is pending even once the entry has settled")
    func pendingSwapIsPending() {
        let details = TransactionDetails(
            activity: activity(
                kind: .swapped,
                title: "Converted",
                state: .completed,
                metadata: swapMetadata(toFiat: nil, state: .pending),
            )
        )

        #expect(details.status == .pending)
    }

    // MARK: - Status

    @Test("A pending entry reads as pending")
    func pendingEntryReadsAsPending() {
        let details = TransactionDetails(activity: activity(kind: .deposited, title: "Deposited", state: .pending))

        #expect(details.kind == .deposit)
        #expect(details.status == .pending)
        #expect(details.signPrefix == "+")
    }

    // MARK: - Receipt

    @Test("The copied id is the entry's base58 id")
    func copiedIdIsBase58() {
        let entry = activity(kind: .deposited, title: "Deposited")

        #expect(TransactionDetails(activity: entry).id == entry.id.base58)
    }

    @Test("The receipt reads the amount the entry settled at")
    func receiptReadsTheSettledAmount() {
        let amount = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 1_500_000, mint: .usdf),
            nativeAmount: FiatAmount(value: 2_100, currency: .cad),
            currencyRate: Rate(fx: 1.4, currency: .cad),
        )
        let details = TransactionDetails(activity: activity(kind: .bought, title: "Bought", amount: amount))

        #expect(details.currency == .cad)
        #expect(details.exchangeRate == 1.4)
        #expect(details.tokenAmount == amount.onChainAmount)
    }

    @Test("A withdrawal has no second line to draw")
    func withdrawalHasNoSubtitle() {
        // The feed carries no destination address, so there is nothing to put
        // under the heading until it does.
        let details = TransactionDetails(activity: activity(kind: .withdrew, title: "Withdrew"))

        #expect(details.kind == .withdraw)
        #expect(details.subtitle == nil)
        #expect(details.signPrefix == "-")
    }
}
