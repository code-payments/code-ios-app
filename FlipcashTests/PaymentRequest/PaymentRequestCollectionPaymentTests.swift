//
//  PaymentRequestCollectionPaymentTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("PaymentRequestPayment for a collection")
struct PaymentRequestCollectionPaymentTests {

    private let requestID = PaymentRequestID(data: Data([3]))
    private let chat = ConversationID(data: Data(repeating: 0x0D, count: 32))
    private let intentID = Data(repeating: 7, count: 32)

    /// What the server answers: the intent ID read's result, and whether the viewer reads as paid.
    @MainActor
    private final class Server {
        var intentResult: Result<Data, ErrorGetPaymentIntentID>
        var isPaid = false
        var intentReads = 0
        var detailReads = 0

        init(intentResult: Result<Data, ErrorGetPaymentIntentID>) {
            self.intentResult = intentResult
        }
    }

    private func collection(amount: Double, status: GroupPaymentRequest.Status = .open) -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: requestID,
            creator: UUID(),
            createdAt: .now.addingTimeInterval(-60),
            status: status,
            closedAt: nil,
            version: 1,
            chatID: chat,
            split: nil,
            collection: .init(text: nil, currency: "usd", endsAt: nil, paymentAmount: .fixed(.init(nativeAmount: amount))),
            payerSummary: .init(payerCount: 0, paidCount: 0, nativeAmountDue: 0, nativeAmountPaid: 0)
        )
    }

    private func store(_ server: Server, amount: Double, viewer: UserID) -> PaymentRequests {
        let request = collection(amount: amount)
        return PaymentRequests(
            getChatPage: { _, _, _ in [] },
            getRequest: { _ in
                server.detailReads += 1
                let caller = server.isPaid
                    ? GroupPaymentRequest.Payer(userID: viewer, nativeAmountDue: 0, nativeAmountPaid: amount, status: .paid(paidAt: .now, settlement: .intent(Data(repeating: 9, count: 32))))
                    : nil
                return (request, nil, caller)
            },
            getPaymentIntentID: { _ in
                server.intentReads += 1
                return try server.intentResult.get()
            },
            getPaidPayers: { _, _ in ([], 1) },
            showsCollections: { true }
        )
    }

    /// A payment over `server`, with the request already held as Request details holds it.
    private func payment(
        _ server: Server,
        amount: Double,
        submissionTimeout: Duration = PaymentRequestPayment.submissionTimeout
    ) async throws -> (PaymentRequestPayment, PaymentRequests, FakeRequestPayer, SessionContainer) {
        let container = try await SendAmountViewModelTests.makeReadyToSendContainer()
        container.ratesController.selectToken(.usdf, source: .user)
        let requests = store(server, amount: amount, viewer: container.session.userID)
        try await requests.refreshDetails(requestID)
        let payer = FakeRequestPayer()
        let payment = PaymentRequestPayment(
            requestID: requestID,
            sessionContainer: container,
            requests: requests,
            payer: payer,
            resolver: payer,
            // Paying without Group Money's funding; PaymentRequestCollectionFundingTests covers it.
            fundsCollections: { false },
            submissionTimeout: submissionTimeout
        )
        return (payment, requests, payer, container)
    }

    @Test("A collection pays exactly its fixed amount in its currency, under the issued intent ID and the request's ID")
    func submit_paysFixedAmount() async throws {
        let server = Server(intentResult: .success(intentID))
        let (payment, _, payer, _) = try await payment(server, amount: 10)

        #expect(await payment.prepare() == .ready)
        #expect(payment.sheetSnapshot?.payable == .fixed(nativeAmount: 10))
        #expect(await payment.submit() == .success)

        let sent = try #require(payer.payments.first)
        #expect(payer.payments.count == 1)
        #expect(sent.amount.nativeAmount == FiatAmount(value: 10, currency: .usd))
        #expect(sent.intentID == (try PublicKey(intentID)))
        #expect(sent.paymentRequestID == requestID)
        #expect(sent.chatID == chat)
    }

    @Test("A balance short of the fixed amount sends nothing rather than a capped part of it")
    func submit_shortBalance_neverUnderpays() async throws {
        let server = Server(intentResult: .success(intentID))
        let (payment, _, payer, container) = try await payment(server, amount: 150)

        #expect(await payment.prepare() == .ready)
        #expect(await payment.submit() == .failed)

        #expect(payer.payments.isEmpty)
        #expect(container.session.dialogItem?.title == "You're $50.00 Short")
    }

    @Test("NOT_OPEN shows Request Closed and opens no sheet")
    func prepare_notOpen_showsRequestClosed() async throws {
        let server = Server(intentResult: .failure(.notOpen))
        let (payment, _, _, container) = try await payment(server, amount: 10)

        #expect(await payment.prepare() == .closed)
        #expect(payment.sheetSnapshot == nil)
        #expect(container.session.dialogItem?.title == "Request Closed")
    }

    @Test("ALREADY_PAID and NOT_A_PAYER open no sheet and show no dialog", arguments: [ErrorGetPaymentIntentID.alreadyPaid, .notAPayer])
    func prepare_nothingToPay(_ error: ErrorGetPaymentIntentID) async throws {
        let server = Server(intentResult: .failure(error))
        let (payment, _, _, container) = try await payment(server, amount: 10)

        #expect(await payment.prepare() == .nothingToPay)
        #expect(payment.sheetSnapshot == nil)
        #expect(container.session.dialogItem == nil)
    }

    @Test("DENIED and NOT_FOUND mark the request unavailable and open no sheet", arguments: [ErrorGetPaymentIntentID.denied, .notFound])
    func prepare_unavailable(_ error: ErrorGetPaymentIntentID) async throws {
        let server = Server(intentResult: .failure(error))
        let (payment, requests, _, _) = try await payment(server, amount: 10)

        #expect(await payment.prepare() == .nothingToPay)
        #expect(payment.sheetSnapshot == nil)
        #expect(requests.unavailable.contains(requestID))
    }

    @Test("A retry after an unknown outcome reads the intent ID again and stops on ALREADY_PAID without paying twice")
    func submit_retryAfterUnknownOutcome_stopsOnAlreadyPaid() async throws {
        let server = Server(intentResult: .success(intentID))
        let (payment, _, payer, _) = try await payment(server, amount: 10)
        #expect(await payment.prepare() == .ready)

        // The send's outcome is unknown, and it landed.
        payer.failure = URLError(.timedOut)
        server.isPaid = true
        #expect(await payment.submit() == .failed)
        #expect(payer.payments.count == 1)

        payer.failure = nil
        server.intentResult = .failure(.alreadyPaid)
        let readsBeforeRetry = server.intentReads
        #expect(await payment.submit() == .success)

        #expect(server.intentReads == readsBeforeRetry + 1)
        #expect(payer.payments.count == 1)
    }

    @Test("A payment submission waits 60 seconds before its outcome counts as unknown")
    func submissionTimeoutIsSixtySeconds() {
        #expect(PaymentRequestPayment.submissionTimeout == .seconds(60))
    }

    @Test("A submission that never answers unlocks the sheet at its deadline, shows Payment Not Confirmed, refetches, and sends nothing more")
    func submit_neverAnswers_unlocksAtDeadline() async throws {
        let server = Server(intentResult: .success(intentID))
        let (payment, _, payer, container) = try await payment(server, amount: 10, submissionTimeout: .milliseconds(200))
        #expect(await payment.prepare() == .ready)
        payer.holdsPayments = true
        defer { payer.answerHeldPayments() }
        var lockedMidPay = false
        payer.whilePaying = { lockedMidPay = payment.blocksDismiss }
        let intentReadsBefore = server.intentReads
        let detailReadsBefore = server.detailReads

        let submission = Task { await payment.submit() }
        try await waitUntil(timeout: .seconds(10)) { !payment.blocksDismiss && !payer.payments.isEmpty }

        #expect(lockedMidPay)
        #expect(await submission.value == .failed)
        #expect(container.session.dialogItem?.title == "Payment Not Confirmed")
        #expect(container.session.dialogItem?.subtitle == "We couldn’t confirm your payment yet. Check back shortly. You won’t be charged twice.")
        try await waitUntil(timeout: .seconds(10)) { server.detailReads > detailReadsBefore }

        // The server answers late; nothing is sent again, and the intent ID isn't read, until a tap.
        payer.answerHeldPayments()
        await Task.yield()
        #expect(payer.payments.count == 1)
        #expect(server.intentReads == intentReadsBefore)
    }

    @Test("The tap after a submission that never answered reads the intent ID again and stops on ALREADY_PAID when the first landed")
    func submit_afterNeverAnswered_stopsOnAlreadyPaid() async throws {
        let server = Server(intentResult: .success(intentID))
        let (payment, _, payer, _) = try await payment(server, amount: 10, submissionTimeout: .milliseconds(200))
        #expect(await payment.prepare() == .ready)
        payer.holdsPayments = true
        defer { payer.answerHeldPayments() }

        let submission = Task { await payment.submit() }
        try await waitUntil(timeout: .seconds(10)) { !payment.blocksDismiss && !payer.payments.isEmpty }
        #expect(await submission.value == .failed)

        // The first payment landed after all.
        payer.holdsPayments = false
        server.isPaid = true
        server.intentResult = .failure(.alreadyPaid)
        let readsBeforeRetry = server.intentReads
        #expect(await payment.submit() == .success)

        #expect(server.intentReads == readsBeforeRetry + 1)
        #expect(payer.payments.count == 1)
    }

    @Test("The intent ID reaches no log line through the read, a failed send, or the retry")
    func intentIDIsNeverLogged() async throws {
        let issued = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let server = Server(intentResult: .success(issued))
        let (payment, _, payer, _) = try await payment(server, amount: 10)

        #expect(await payment.prepare() == .ready)
        payer.failure = URLError(.timedOut)
        #expect(await payment.submit() == .failed)
        payer.failure = nil
        #expect(await payment.submit() == .success)

        let forms = [issued.hexString(), issued.base64EncodedString(), try PublicKey(issued).base58]
        let leaked = LogStore.shared.recentEntries().filter { line in forms.contains { line.contains($0) } }
        #expect(leaked.isEmpty)
    }
}

@MainActor
final class FakeRequestPayer: RequestedPaying, RecipientResolving {

    struct Payment {
        let amount: ExchangedFiat
        let chatID: ConversationID
        let paymentRequestID: PaymentRequestID
        let intentID: PublicKey
    }

    private(set) var payments: [Payment] = []
    var failure: (any Error)?
    /// Runs inside the payment, before it returns or throws.
    var whilePaying: (() -> Void)?
    /// When set, a payment doesn't answer until ``answerHeldPayments()``, and ignores cancellation
    /// meanwhile, as a submission the server never answers does.
    var holdsPayments = false
    private var held: [CheckedContinuation<Void, Never>] = []

    func payRequestShare(
        amount: ExchangedFiat,
        verifiedState: VerifiedState,
        to creatorOwner: PublicKey,
        chatID: ConversationID,
        paymentRequestID: PaymentRequestID,
        intentID: PublicKey
    ) async throws {
        payments.append(Payment(amount: amount, chatID: chatID, paymentRequestID: paymentRequestID, intentID: intentID))
        whilePaying?()
        if holdsPayments {
            await withCheckedContinuation { held.append($0) }
        }
        if let failure { throw failure }
    }

    /// Lets every held payment answer.
    func answerHeldPayments() {
        let answering = held
        held = []
        answering.forEach { $0.resume() }
    }

    func resolveContact(e164: String) async throws -> PublicKey {
        .mock
    }

    func resolveUserID(_ userID: UserID) async throws -> PublicKey {
        .mock
    }
}

@MainActor
@Suite("PaymentRequestDetailsContent for a collection")
struct PaymentRequestCollectionDetailsTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let creator = UUID()
    private let viewer = UUID()
    private let copy = PaymentRequestCopy(displayCurrency: .usd, rates: [:])

    private func collection(
        status: GroupPaymentRequest.Status = .open,
        paid: Double = 0,
        amount: GroupPaymentRequest.Collection.PaymentAmount? = .fixed(.init(nativeAmount: 10))
    ) -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: PaymentRequestID(data: Data([4])),
            creator: creator,
            createdAt: now.addingTimeInterval(-60),
            status: status,
            closedAt: nil,
            version: 1,
            chatID: ConversationID(data: Data(repeating: 0x0E, count: 32)),
            split: nil,
            collection: .init(text: nil, currency: "usd", endsAt: nil, paymentAmount: amount),
            payerSummary: .init(payerCount: 0, paidCount: 0, nativeAmountDue: 0, nativeAmountPaid: paid)
        )
    }

    private func paid(_ userID: UserID, _ amount: Double) -> GroupPaymentRequest.Payer {
        .init(userID: userID, nativeAmountDue: 0, nativeAmountPaid: amount, status: .paid(paidAt: now, settlement: .intent(Data(repeating: 9, count: 32))))
    }

    private func content(
        _ request: GroupPaymentRequest,
        payers: [GroupPaymentRequest.Payer]? = [],
        viewerHasPaid: Bool? = false,
        as viewer: UserID? = nil
    ) -> PaymentRequestDetailsContent? {
        PaymentRequestDetailsContent(
            collection: request,
            paidPayers: payers,
            viewerHasPaid: viewerHasPaid,
            viewer: viewer ?? self.viewer,
            copy: copy,
            now: now,
            name: { $0 == self.creator ? "Alex" : "Jordan" }
        )
    }

    @Test("Nobody paid yet reads $0 paid · $10.00 each, no title, no status, and No payments yet")
    func header_nobodyPaid() throws {
        let content = try #require(content(collection()))

        #expect(content.title == nil)
        #expect(content.requestedBy == "Requested by Alex")
        #expect(content.amounts == "$0 paid · $10.00 each")
        #expect(content.statusLine == "")
        #expect(content.rows.isEmpty)
        #expect(content.emptyLine == "No payments yet")
    }

    @Test("Paid payers read as rows with their amount and the viewer named You")
    func rows_paidPayers() throws {
        let other = UUID()
        let content = try #require(content(collection(paid: 22), payers: [paid(viewer, 11), paid(other, 11)], viewerHasPaid: true))

        #expect(content.amounts == "$22.00 paid · $10.00 each")
        #expect(content.rows.map(\.name) == ["You", "Jordan"])
        #expect(content.rows.map(\.amount) == ["$11.00", "$11.00"])
        #expect(content.rows.allSatisfy { $0.status == "✓ Paid" && $0.action == .none })
        #expect(content.emptyLine == nil)
    }

    @Test("No row list read yet shows neither rows nor No payments yet")
    func rows_notReadYet() throws {
        let content = try #require(content(collection(), payers: nil))

        #expect(content.rows.isEmpty)
        #expect(content.emptyLine == nil)
    }

    @Test("A member who hasn't paid an open collection sees Pay $10.00")
    func pay_openUnpaidMember() throws {
        #expect(try #require(content(collection())).payTitle == "Pay $10.00")
    }

    @Test("Pay hides until a read says the viewer hasn't paid, once they have, for the creator, and once closed")
    func pay_hidden() throws {
        #expect(try #require(content(collection(), viewerHasPaid: nil)).payTitle == nil)
        #expect(try #require(content(collection(), viewerHasPaid: true)).payTitle == nil)
        #expect(try #require(content(collection(), as: creator)).payTitle == nil)
        #expect(try #require(content(collection(status: .closed))).payTitle == nil)
    }

    @Test("A closed collection reads Closed, and its creator can't close it again")
    func closed() throws {
        let content = try #require(content(collection(status: .closed), as: creator))

        #expect(content.statusLine == "Closed")
        #expect(content.requestedBy == "Requested by you")
        #expect(content.canClose == false)
    }

    @Test("The creator of an open collection can close it")
    func creator_canClose() throws {
        #expect(try #require(content(collection(), as: creator)).canClose)
    }

    @Test("An amount kind this build doesn't know draws no details and no Pay")
    func unknownAmountKind() {
        #expect(content(collection(amount: nil)) == nil)
    }
}
