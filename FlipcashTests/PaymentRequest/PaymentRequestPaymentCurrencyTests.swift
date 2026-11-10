//
//  PaymentRequestPaymentCurrencyTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("PaymentRequestPayment currency selection")
struct PaymentRequestPaymentCurrencyTests {

    @Test("Picking a currency on the pay sheet becomes the user's selection for every send flow")
    func selectCurrency_writesUserPickBack() throws {
        let container = try SessionContainer.makeTest(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 100_000_000_000),
            SessionContainer.Holding(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: 1_000_000 * 10_000_000_000),
                quarks: 10 * 10_000_000_000
            ),
        ])
        defer { container.ratesController.selectedTokenMint = nil }
        container.ratesController.selectToken(.usdf, source: .automatic)
        let payment = PaymentRequestPayment(
            requestID: PaymentRequestID(data: Data([1])),
            sessionContainer: container
        )
        #expect(payment.selectedBalance?.stored.mint == .jeffy)

        let dollars = try #require(container.session.balances(
            for: container.ratesController.rateForBalanceCurrency()
        ).first { $0.stored.mint == .usdf })
        payment.selectCurrencyAction(exchangedBalance: dollars)

        #expect(payment.selectedBalance?.stored.mint == .usdf)
        #expect(container.ratesController.selectedTokenMint == .usdf)
        #expect(container.ratesController.isSelectedTokenUserPicked)
    }

    @Test("The pay and send pickers list the same balances, in the same order, as group send's")
    func paymentOptions_matchGroupSend() throws {
        let container = try SessionContainer.makeTest(holdings: [
            SessionContainer.Holding(mint: .usdf, quarks: 100_000_000_000),
            SessionContainer.Holding(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: 1_000_000 * 10_000_000_000),
                quarks: 10 * 10_000_000_000
            ),
        ])
        defer { container.ratesController.selectedTokenMint = nil }
        let groupSend = GroupSendViewModel(
            sessionContainer: container,
            conversationID: ConversationID(data: Data(repeating: 0x0B, count: 32))
        )
        let payment = PaymentRequestPayment(
            requestID: PaymentRequestID(data: Data([1])),
            sessionContainer: container
        )
        let send = SendAmountViewModel(
            sessionContainer: container,
            target: .contact(SendAmountViewModelTests.makeContact()),
            mint: nil
        )

        let expected = groupSend.paymentOptions.map(\.stored.mint)
        #expect(Set(expected) == [.usdf, .jeffy])
        #expect(payment.paymentOptions.map(\.stored.mint) == expected)
        #expect(send.paymentOptions.map(\.stored.mint) == expected)
    }
}

@MainActor
@Suite("PaymentRequestPayment without a balance")
struct PaymentRequestPaymentNoBalanceTests {

    private let requestID = PaymentRequestID(data: Data([1]))

    /// A store whose refetch returns a request with an unpaid share for `container`'s user.
    private func store(status: GroupPaymentRequest.Status, for container: SessionContainer) -> PaymentRequests {
        let request = GroupPaymentRequest(
            id: requestID,
            creator: UUID(),
            createdAt: .now.addingTimeInterval(-60),
            status: status,
            closedAt: nil,
            version: 1,
            chatID: ConversationID(data: Data(repeating: 0x0B, count: 32)),
            split: .init(
                text: .plaintext(title: "Dinner", description: ""),
                currency: "usd",
                endsAt: .now.addingTimeInterval(86_400),
                shares: [.init(userID: container.session.userID, nativeAmount: 10)]
            )
        )
        return PaymentRequests(getChatPage: { _, _, _ in [] }, getRequest: { _ in (request, Data(repeating: 7, count: 32)) })
    }

    @Test("The pay flow shows No Balance Yet and does not open the sheet when nothing is held")
    func start_noBalance_blocksSheet() async throws {
        let container = try SessionContainer.makeTest(holdings: [])
        let flow = PaymentRequestPayFlow()

        let result = await flow.start(
            requestID,
            sessionContainer: container,
            router: AppRouter(),
            requests: store(status: .open, for: container)
        )

        #expect(result == .noBalance)
        #expect(flow.isPaying == false)
        #expect(container.session.dialogItem?.title == "No Balance Yet")
    }

    @Test("A closed request with no balance reads Request Closed, not No Balance Yet")
    func start_closedNoBalance_showsRequestClosed() async throws {
        let container = try SessionContainer.makeTest(holdings: [])
        let flow = PaymentRequestPayFlow()

        let result = await flow.start(
            requestID,
            sessionContainer: container,
            router: AppRouter(),
            requests: store(status: .closed, for: container)
        )

        #expect(result == .closed)
        #expect(flow.isPaying == false)
        #expect(container.session.dialogItem?.title == "Request Closed")
    }

    @Test("Submitting with no selected balance shows insufficient funds, not Couldn't Send")
    func submit_nilSelectedBalance_showsInsufficientFunds() async throws {
        let container = try SessionContainer.makeTest(holdings: [])
        let payment = PaymentRequestPayment(
            requestID: PaymentRequestID(data: Data([1])),
            sessionContainer: container
        )
        #expect(payment.selectedBalance == nil)

        let outcome = await payment.submit()

        #expect(outcome == .failed)
        #expect(container.session.dialogItem?.title == "You Need More Cash")
    }
}

@MainActor
@Suite("PaymentRequestPayment sheet snapshot")
struct PaymentRequestPaymentSheetSnapshotTests {

    private let requestID = PaymentRequestID(data: Data([2]))

    /// What the server returns on the next refetch.
    @MainActor
    private final class Server {
        var isPaid = false
    }

    private func request(for userID: UserID, paid: Bool) -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: requestID,
            creator: UUID(),
            createdAt: .now.addingTimeInterval(-60),
            status: .open,
            closedAt: nil,
            version: paid ? 2 : 1,
            chatID: ConversationID(data: Data(repeating: 0x0C, count: 32)),
            split: .init(
                text: .plaintext(title: "Dinner", description: ""),
                currency: "usd",
                endsAt: .now.addingTimeInterval(86_400),
                shares: [.init(
                    userID: userID,
                    nativeAmount: 10,
                    paidAt: paid ? .now : nil,
                    settlement: paid ? .intent(Data(repeating: 9, count: 32)) : nil
                )]
            )
        )
    }

    @Test("The sheet keeps the share it opened with after a refetch reads it paid")
    func sheetSnapshot_survivesShareReadingPaid() async throws {
        let container = try SessionContainer.makeTest(holdings: [])
        let userID = container.session.userID
        let server = Server()
        let requests = PaymentRequests(getChatPage: { _, _, _ in [] }, getRequest: { _ in
            (request(for: userID, paid: server.isPaid), Data(repeating: 7, count: 32))
        })
        let payment = PaymentRequestPayment(requestID: requestID, sessionContainer: container, requests: requests)

        #expect(await payment.prepare() == .ready)
        let opened = try #require(payment.sheetSnapshot)

        server.isPaid = true
        _ = try await requests.refresh(requestID)

        #expect(payment.share == nil)
        #expect(payment.sheetSnapshot == opened)
        #expect(opened.share.nativeAmount == 10)
        #expect(opened.share.isPaid == false)
    }
}
