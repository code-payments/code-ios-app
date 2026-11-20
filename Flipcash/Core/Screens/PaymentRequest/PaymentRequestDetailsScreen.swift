//
//  PaymentRequestDetailsScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Request details: who asked, how much is paid, and one row per share, with paying, closing and
/// marking a share paid for the viewers allowed to.
struct PaymentRequestDetailsScreen: View {

    @Environment(Session.self) private var session
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(VerificationCoordinator.self) private var verificationCoordinator

    let requestID: PaymentRequestID
    /// Whether the screen is pushed onto an existing navigation stack, which then supplies the back
    /// button in place of the close button.
    var isPushed = false
    /// Whether the screen runs its Pay button once as it opens, for a Pay tapped in the chat on a
    /// collection no balance funds (1.1, 2.1).
    var paysOnOpen = false

    @State private var dialogItem: DialogItem?
    /// A confirm queued behind an options sheet, shown once that sheet is gone.
    @State private var queuedDialog: DialogItem?
    /// Whether the last fetch carried an intent ID; the ID itself stays with ``PaymentRequestPayment``.
    @State private var hasPaymentIntent = false
    @State private var payFlow = PaymentRequestPayFlow()
    @State private var isUpdating = false
    @State private var verificationViewModel: OnrampVerification?
    @State private var didPayOnOpen = false

    var body: some View {
        Group {
            if isPushed {
                screen
            } else {
                NavigationStack { screen }
            }
        }
        // Like the chat, details refetch on a 45 s poll while on screen in the foreground.
        .task(id: PaymentRequestDetailsPoll(requestID: requestID, isActive: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await load()
            var retries = 0
            while !Task.isCancelled {
                // Still loading after a failed read retries sooner than the poll.
                if sessionContainer.paymentRequests.isSettling(request: requestID) {
                    try? await Task.sleep(for: PaymentRequests.retryDelay(attempt: retries))
                    retries += 1
                } else {
                    try? await Task.sleep(for: PaymentRequests.pollInterval)
                    retries = 0
                }
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
        // The Request button reads the plan, so the payment exists before the first tap.
        .task(id: requestID) {
            payFlow.attach(requestID, sessionContainer: sessionContainer)
            if paysOnOpen, !didPayOnOpen {
                didPayOnOpen = true
                pay(topUp: payFlow.inPlaceTopUp(for: requestID))
            }
        }
        .onChange(of: payFlow.payment?.isFinishing == true) { _, isFinishing in
            if isFinishing { payFlow.holdFinishing() }
        }
        .dialog(item: $dialogItem)
        .sheet(item: $verificationViewModel.cancellingOnDismiss()) { viewModel in
            VerifyInfoScreen(viewModel: viewModel)
        }
        .paymentRequestPaySheet(payFlow)
    }

    private var screen: some View {
        // The status line counts down, so redraw at least once a minute.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if payFlow.showsFinishing {
                // Money the Request button added is landing; 1.3 draws this full screen.
                PaymentRequestFinishing()
                    .frame(maxHeight: .infinity)
            } else if isUnavailableCollection {
                unavailable
            } else if let content = content(at: context.date) {
                loaded(content)
            } else if sessionContainer.paymentRequests.unavailable.contains(requestID) {
                // DENIED or NOT_FOUND, for example after the viewer left the group.
                unavailable
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.backgroundMain)
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if content(at: .now)?.canClose == true {
                    Button {
                        presentCloseOptions()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.appBarButton)
                            .foregroundStyle(Color.textMain)
                    }
                    .accessibilityLabel("Options")
                }
                if !isPushed {
                    CloseButton(action: { dismiss() })
                }
            }
        }
        // Nothing leaves the screen while the payment finishes.
        .toolbar(payFlow.showsFinishing ? .hidden : .automatic, for: .navigationBar)
        .navigationBarBackButtonHidden(payFlow.showsFinishing)
        .interactiveDismissDisabled(payFlow.showsFinishing)
    }

    // MARK: - Content -

    private var isUnavailableCollection: Bool {
        let requests = sessionContainer.paymentRequests
        return requests.request(requestID)?.collection != nil && requests.unavailable.contains(requestID)
    }

    private var unavailable: some View {
        Text("This request is no longer available.")
            .font(.appTextMedium)
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loaded(_ content: PaymentRequestDetailsContent) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header(content)
                    VStack(spacing: 8) {
                        ForEach(content.rows) { row in
                            shareRow(row)
                        }
                    }
                }
                // With no rows and no Pay button nothing else is full width, and the scroll view
                // would shrink to the header's width.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .softScrollEdge(for: [.top, .bottom])
            .overlay {
                // Centred in the body, between the header and the Pay button, like frame 3.1.
                if let emptyLine = content.emptyLine {
                    Text(emptyLine)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            if let payTitle = content.payTitle {
                let topUp = payFlow.inPlaceTopUp(for: requestID)
                let isBusy = payFlow.isPreparing || payFlow.isToppingUp
                VStack(spacing: 16) {
                    Button {
                        pay(topUp: topUp)
                    } label: {
                        ButtonStateLabel(topUp?.title ?? payTitle, state: isBusy ? .loading : .normal)
                    }
                    .buttonStyle(.filled)
                    .disabled(isBusy)
                    // A top-up opens Apple Pay straight from this button, so it is told apart from Pay.
                    .accessibilityIdentifier(topUp == nil ? "payment-request-pay-button" : "payment-request-topup-button")
                    if let footnote = topUp?.footnote {
                        Text(footnote)
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
                .bottomEdgePadding()
            }
        }
    }

    private func header(_ content: PaymentRequestDetailsContent) -> some View {
        let creator = sessionContainer.paymentRequests.request(requestID)?.creator
        return VStack(alignment: .leading, spacing: 16) {
            if let title = content.title {
                Text(title)
                    .font(.appDisplayCompact)
                    .foregroundStyle(Color.textMain)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if let creator {
                    PaymentRequestAvatar(userID: creator, member: member(creator), size: 24)
                }
                Text(content.requestedBy)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(content.amounts)
                    .font(.appDisplayXS)
                    .foregroundStyle(Color.textMain)
                if !content.statusLine.isEmpty {
                    Text(content.statusLine)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A row with nothing to do is a plain view: a disabled button would dim the whole row.
    @ViewBuilder
    private func shareRow(_ row: PaymentRequestDetailsContent.Row) -> some View {
        switch row.action {
        case .markPaid:
            Button {
                presentMarkPaidOptions(row)
            } label: {
                shareRowContent(row)
            }
            .buttonStyle(.plain)
            .disabled(isUpdating)
            .accessibilityElement(children: .combine)
        case .none:
            shareRowContent(row)
                .accessibilityElement(children: .combine)
        }
    }

    private func shareRowContent(_ row: PaymentRequestDetailsContent.Row) -> some View {
        HStack(spacing: 12) {
            PaymentRequestAvatar(userID: row.userID, member: member(row.userID), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Text(row.status)
                    .font(.appTextSmall)
                    .foregroundStyle(row.isPaid ? Color.textSuccess : Color.textSecondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            Text(row.amount)
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 64)
        .background(Color.paymentRequestRowFill, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
        .requestMotion(value: row.isPaid)
    }

    /// The viewer's reading of the request, or nil until it and its title are loaded. A collection
    /// has no title, so it reads as soon as it is held.
    private func content(at now: Date) -> PaymentRequestDetailsContent? {
        let requests = sessionContainer.paymentRequests
        guard let request = requests.request(requestID) else { return nil }
        let copy = PaymentRequestCopy(session.displayCurrency)
        let name: (UserID) -> String = { member($0).map(ConversationLoadCoordinator.attributionName(for:)) ?? "Someone" }
        return PaymentRequestDetailsContent.reading(
            request,
            in: requests,
            viewer: session.userID,
            hasPaymentIntent: hasPaymentIntent,
            copy: copy,
            now: now,
            name: name
        )
    }

    private func member(_ userID: UserID) -> ConversationMember? {
        guard let request = sessionContainer.paymentRequests.request(requestID), let chatID = request.chatID else { return nil }
        return sessionContainer.groupRosters
            .members(for: chatID, creator: request.creator)
            .first { $0.userID == userID }
    }

    // MARK: - Actions -

    private func load() async {
        let requests = sessionContainer.paymentRequests
        await refresh()
        guard let chatID = requests.request(requestID)?.chatID else { return }
        await sessionContainer.groupRosters.refresh(chatID)
    }

    private func refresh() async {
        do {
            hasPaymentIntent = try await sessionContainer.paymentRequests.refreshDetails(requestID) != nil
        } catch {
            hasPaymentIntent = false
        }
    }

    /// Refetches for the intent ID right before the swipe sheet, as the spec requires. When no
    /// balance funds a collection, `topUp` is what the button showed, and the tap adds that with
    /// Apple Pay and pays, with no sheet.
    private func pay(topUp: CollectionPaymentSheetContent.RequestTopUp?) {
        guard !payFlow.isToppingUp else { return }
        Task {
            let result = await payFlow.payFromRequestScreen(
                requestID,
                topUp: topUp,
                sessionContainer: sessionContainer,
                router: router,
                verified: { await verificationCoordinator.verified(for: session, bind: { verificationViewModel = $0 }) },
                refreshed: { await refresh() }
            )
            guard case .prepared(let preparation) = result else { return }
            switch preparation {
            case .ready, .noBalance, .fundedByTopUp:
                break
            case .nothingToPay, .closed, .failed:
                hasPaymentIntent = false
            }
        }
    }

    private func presentCloseOptions() {
        present(.options {
            DialogAction.standard("Close Request") {
                queuedDialog = closeConfirm()
            }
            DialogAction.cancel()
        })
    }

    private func closeConfirm() -> DialogItem {
        .info(
            title: "Close Request?",
            subtitle: "This will stop payments. Anyone who hasn't paid will be marked Didn't pay. Payments already made won't be affected."
        ) {
            DialogAction.standard("Close Request") {
                Task { await close() }
            }
            DialogAction.cancel()
        }
    }

    private func presentMarkPaidOptions(_ row: PaymentRequestDetailsContent.Row) {
        present(.options(title: row.name, subtitle: "\(row.amount) · \(row.status)") {
            DialogAction.standard("Mark as Paid") {
                queuedDialog = markPaidConfirm(row)
            }
            DialogAction.cancel()
        })
    }

    private func markPaidConfirm(_ row: PaymentRequestDetailsContent.Row) -> DialogItem {
        let firstName = row.name.split(separator: " ").first.map(String.init) ?? row.name
        return .info(
            title: "Mark \(firstName) as Paid?",
            subtitle: "Use this if \(firstName) paid you outside Flipcash. No money will be sent. This action cannot be reversed."
        ) {
            DialogAction.standard("Mark as Paid") {
                Task { await update { try await $0.markPaid(requestID, userID: row.userID) } }
            }
            DialogAction.cancel()
        }
    }

    /// Shows `item`, then whatever its action queued once it has left the screen.
    private func present(_ item: DialogItem) {
        dialogItem = item.onDismiss {
            guard let next = queuedDialog else { return }
            queuedDialog = nil
            dialogItem = next
        }
    }

    /// Runs a creator action; the store takes the server's response, and a failure refetches.
    private func close() async {
        await update { requests in
            do {
                try await requests.close(requestID)
                Analytics.paymentRequestClosed(error: nil)
            } catch {
                Analytics.paymentRequestClosed(error: error)
                throw error
            }
        }
    }

    private func update(_ action: (PaymentRequests) async throws -> Void) async {
        isUpdating = true
        defer { isUpdating = false }
        let requests = sessionContainer.paymentRequests
        do {
            try await action(requests)
        } catch {
            ErrorReporting.captureError(error, reason: "Payment request update failed")
            _ = try? await requests.refresh(requestID)
            session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We couldn't update this request. Please try again."
            )
        }
    }
}

/// A member's avatar, loading their picture on first draw.
private struct PaymentRequestAvatar: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let userID: UserID
    let member: ConversationMember?
    let size: CGFloat

    var body: some View {
        ContactAvatarView(
            id: userID.uuidString,
            displayName: member.map(ConversationLoadCoordinator.attributionName(for:)) ?? "",
            imageData: sessionContainer.profileAvatars.data(for: userID),
            blurhash: member?.profilePicture?.thumbnailBlurhash,
            size: size
        )
        .task(id: userID) {
            await sessionContainer.profileAvatars.load(userID: userID, picture: member?.profilePicture)
        }
    }
}

private struct PaymentRequestPayDismissed: Error {}

// MARK: - Pay flow -

/// Paying a share from wherever it starts: refetches the request for its intent ID, then shows the
/// swipe sheet when the share is still payable.
@MainActor
@Observable
final class PaymentRequestPayFlow {

    private(set) var isPreparing = false
    var isPaying = false
    private(set) var payment: PaymentRequestPayment?
    /// True from a tap on the Request screen's top-up button until its run, and the refetch after
    /// a payment, are done. A second tap meanwhile does nothing.
    private(set) var isToppingUp = false
    /// Keeps "Finishing Payment" up once it has shown, until the run ends, so the unpaid row
    /// doesn't flash back between the payment landing and the refetch.
    private(set) var holdsFinishing = false

    /// What the Request screen draws in place of its body while money it added lands (1.3).
    var showsFinishing: Bool {
        isToppingUp && (payment?.isFinishing == true || holdsFinishing)
    }

    /// What happened to a tap on the Request screen's top-up button.
    enum TopUpInPlaceResult: Equatable {
        /// It stopped before Apple Pay, or the sheet opened: what preparing found.
        case prepared(PaymentRequestPayment.Preparation)
        /// The user backed out of verifying the contact Coinbase needs; nothing was ordered.
        case notVerified
        /// Money was added, or a top-up an earlier tap ordered was waited on, and the payment came to this.
        case paid(PaymentRequestPayment.Outcome)
        /// An earlier tap's run is still going.
        case busy
    }

    /// Builds the payment for `requestID` ahead of a tap, so the Request screen's button can read
    /// how the payment would be funded.
    func attach(_ requestID: PaymentRequestID, sessionContainer: SessionContainer) {
        _ = payment(for: requestID, sessionContainer: sessionContainer)
    }

    /// The Request screen's button when no balance funds the collection, so the button adds the
    /// money itself (1.1, 2.1); nil when a balance funds any of it and Pay opens the sheet.
    func inPlaceTopUp(for requestID: PaymentRequestID) -> CollectionPaymentSheetContent.RequestTopUp? {
        guard let payment, payment.requestID == requestID, payment.fundsCollection else { return nil }
        return payment.fundingSheet?.requestTopUp
    }

    private func payment(
        for requestID: PaymentRequestID,
        sessionContainer: SessionContainer,
        requests: PaymentRequests? = nil,
        injected: PaymentRequestPayment? = nil
    ) -> PaymentRequestPayment {
        let payment = injected
            ?? self.payment.flatMap { $0.requestID == requestID ? $0 : nil }
            ?? PaymentRequestPayment(requestID: requestID, sessionContainer: sessionContainer, requests: requests)
        self.payment = payment
        return payment
    }

    /// Prepares to pay the viewer's share of `requestID` and shows the sheet when it is payable.
    /// A payable share the viewer has nothing to pay with gets the "No Balance Yet" dialog instead of
    /// the sheet; a collection no balance funds opens nothing and returns
    /// ``PaymentRequestPayment/Preparation/fundedByTopUp``, for the Request screen's button to add
    /// the money and pay; a closed request still reads "Request Closed". `requests` replaces the
    /// session's store and `payment` the payment the flow would build, for tests.
    @discardableResult
    func start(
        _ requestID: PaymentRequestID,
        sessionContainer: SessionContainer,
        router: AppRouter,
        requests: PaymentRequests? = nil,
        payment injected: PaymentRequestPayment? = nil
    ) async -> PaymentRequestPayment.Preparation {
        guard !isPreparing, !isToppingUp else { return .failed }
        isPreparing = true
        defer { isPreparing = false }
        let payment = payment(for: requestID, sessionContainer: sessionContainer, requests: requests, injected: injected)
        let preparation = await payment.prepare()
        guard preparation == .ready else { return preparation }
        return present(payment, sessionContainer: sessionContainer, router: router)
    }

    /// The Request screen's button for a collection no balance funds, which showed adding
    /// `topUpMicros`: refetches as ``start`` does, verifies the contact Coinbase needs, then adds
    /// that amount with Apple Pay and pays, with no sheet (1.1-1.4, 2.1). It runs the sheet's
    /// top-up, so a top-up an earlier tap ordered is waited on and never ordered again, and the
    /// send limit is checked before Apple Pay opens. When the plan has moved since the button drew,
    /// the sheet opens instead: on the swipe if a balance now funds part of it, on the short state
    /// if the top-up changed. `refreshed` refetches the screen after a payment lands.
    func topUpInPlace(
        _ requestID: PaymentRequestID,
        topUpMicros: Int64,
        sessionContainer: SessionContainer,
        router: AppRouter,
        verified: @MainActor () async -> Bool,
        refreshed: @MainActor () async -> Void,
        requests: PaymentRequests? = nil,
        payment injected: PaymentRequestPayment? = nil
    ) async -> TopUpInPlaceResult {
        guard !isPreparing, !isToppingUp else { return .busy }
        isToppingUp = true
        defer {
            isToppingUp = false
            holdsFinishing = false
        }
        let payment = payment(for: requestID, sessionContainer: sessionContainer, requests: requests, injected: injected)
        let preparation = await payment.prepare()
        guard preparation == .ready else { return .prepared(preparation) }
        guard payment.fundsCollection, payment.fundingSheet?.requestTopUp != nil else {
            return .prepared(present(payment, sessionContainer: sessionContainer, router: router))
        }
        guard await verified() else { return .notVerified }
        let outcome = await payment.addAndPay(topUpMicros: topUpMicros)
        switch outcome {
        case .success:
            holdsFinishing = true
            await refreshed()
        case .short:
            isPaying = true
        case .failed:
            break
        }
        return .paid(outcome)
    }

    /// A tap on the Request screen's button, which showed `topUp`, or Pay when nil: adds the money
    /// and pays with no sheet when no balance funds the collection, as ``topUpInPlace`` does, and
    /// otherwise opens the sheet as ``start`` does. A button that showed Pay over a plan no balance
    /// funds any more adds the money all the same, at the amount the refetched plan needs.
    func payFromRequestScreen(
        _ requestID: PaymentRequestID,
        topUp: CollectionPaymentSheetContent.RequestTopUp?,
        sessionContainer: SessionContainer,
        router: AppRouter,
        verified: @MainActor () async -> Bool,
        refreshed: @MainActor () async -> Void,
        requests: PaymentRequests? = nil,
        payment injected: PaymentRequestPayment? = nil
    ) async -> TopUpInPlaceResult {
        let topUpMicros: Int64
        if let topUp {
            topUpMicros = topUp.micros
        } else {
            let preparation = await start(requestID, sessionContainer: sessionContainer, router: router, requests: requests, payment: injected)
            guard preparation == .fundedByTopUp, let fresh = inPlaceTopUp(for: requestID) else {
                return .prepared(preparation)
            }
            topUpMicros = fresh.micros
        }
        return await topUpInPlace(
            requestID,
            topUpMicros: topUpMicros,
            sessionContainer: sessionContainer,
            router: router,
            verified: verified,
            refreshed: refreshed,
            requests: requests,
            payment: injected
        )
    }

    /// Called as "Finishing Payment" shows, so it stays up through the refetch after the payment.
    func holdFinishing() {
        if isToppingUp { holdsFinishing = true }
    }

    /// Opens the sheet for a payable share, or the "No Balance Yet" dialog when there's nothing to
    /// pay with. A collection no balance funds opens neither, since its Request button pays (1.1, 2.1).
    private func present(_ payment: PaymentRequestPayment, sessionContainer: SessionContainer, router: AppRouter) -> PaymentRequestPayment.Preparation {
        if payment.fundsCollection, payment.fundingSheet?.requestTopUp != nil {
            return .fundedByTopUp
        }
        let session = sessionContainer.session
        let rate = sessionContainer.ratesController.rateForBalanceCurrency()
        // A collection that conversions fund can add Dollars from the sheet, so an empty balance
        // opens it on the short state instead.
        if !payment.fundsCollection, let dialog = giveCashGate(session: session, rate: rate)
            .blockingDialog(router: router, addMoneySource: .chat, context: .payRequest) {
            session.dialogItem = dialog
            return .noBalance
        }
        isPaying = true
        return .ready
    }
}

extension PaymentRequestPaySheetPresenter {
    /// The swipe sheet's amount: a split share as the chat words it, a collection's fixed amount in full.
    fileprivate func sheetAmount(_ snapshot: PaymentRequestPayment.SheetSnapshot) -> String {
        let copy = PaymentRequestCopy(session.displayCurrency)
        switch snapshot.payable {
        case .share(let share):
            return copy.shareText(share, of: snapshot.request)
        case .fixed:
            return copy.collectionAmount(snapshot.request)?.formatted() ?? ""
        }
    }
}

extension View {
    /// Shows `flow`'s swipe-to-send sheet while it is paying.
    func paymentRequestPaySheet(_ flow: PaymentRequestPayFlow) -> some View {
        modifier(PaymentRequestPaySheetPresenter(flow: flow))
    }
}

private struct PaymentRequestPaySheetPresenter: ViewModifier {

    @Bindable var flow: PaymentRequestPayFlow

    @Environment(Session.self) private var session
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router

    /// Add More Cash tapped while the swipe sheet was up; routed once the sheet has dismissed.
    @State private var pendingDeposit: PublicKey?

    func body(content: Content) -> some View {
        content
            .onChange(of: flow.payment?.depositMint) { _, mint in
                guard let mint else { return }
                flow.payment?.depositMint = nil
                if flow.isPaying {
                    // The router can't dismiss this local sheet, so close it and navigate after.
                    pendingDeposit = mint
                    flow.isPaying = false
                } else {
                    router.navigate(to: .currencyInfoForDeposit(mint))
                }
            }
            .sheet(isPresented: $flow.isPaying, onDismiss: {
                guard let mint = pendingDeposit else { return }
                pendingDeposit = nil
                router.navigate(to: .currencyInfoForDeposit(mint))
            }) {
            // The share reads paid once the payment lands, so the sheet renders from what it opened
            // with and stays up through its success state.
            if let payment = flow.payment, let snapshot = payment.sheetSnapshot, let creator = snapshot.request.creator {
                let request = snapshot.request
                PaymentRequestPaySheet(
                    payment: payment,
                    payee: request.chatID.flatMap { chatID in
                        sessionContainer.groupRosters
                            .members(for: chatID, creator: creator)
                            .first { $0.userID == creator }
                    },
                    payeeID: creator,
                    amount: sheetAmount(snapshot)
                )
                .task {
                    // Opened from the chat's strip, nothing else has loaded the roster that names the payee.
                    if let chatID = request.chatID, !sessionContainer.groupRosters.isLoaded(chatID) {
                        await sessionContainer.groupRosters.refresh(chatID)
                    }
                }
            }
        }
    }
}

/// The swipe-to-send sheet for the viewer's share: the creator, the amount, the token picker.
private struct PaymentRequestPaySheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    @Environment(VerificationCoordinator.self) private var verificationCoordinator

    let payment: PaymentRequestPayment
    let payee: ConversationMember?
    let payeeID: UserID
    let amount: String

    @State private var didSucceed = false
    @State private var isShowingTokenSelection = false
    @State private var isShowingDetails = false
    @State private var isAdding = false
    @State private var verificationViewModel: OnrampVerification?

    var body: some View {
        Group {
            // A collection that conversions fund draws its paying currency, fee line and Payment Details.
            if payment.fundsCollection {
                collectionSheet
            } else {
                PartialSheet(background: .clear) {
                    Group {
                        if payment.isFinishing {
                            finishingContent
                        } else {
                            payContent(feeLine: nil, topUp: nil)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 30)
                    .padding(.bottom, bottomPadding)
                }
            }
        }
        // A top-up an earlier attempt ordered, say before the app was closed, is waited on and paid
        // from as the sheet opens, with no second order.
        .task {
            guard payment.hasPendingTopUp else { return }
            await finishTopUp { await payment.resumePendingTopUp() ?? .failed }
        }
        .sheet(item: $verificationViewModel.cancellingOnDismiss()) { vm in
            VerifyInfoScreen(viewModel: vm)
        }
        // Hold the success checkmark briefly, then return to the details, now showing the row paid.
        .task(id: didSucceed) {
            guard didSucceed else { return }
            try? await Task.sleep(for: PaymentSuccess.hold)
            guard !Task.isCancelled else { return }
            dismiss()
        }
        .sheet(isPresented: $isShowingTokenSelection) {
            let options = payment.paymentOptions
            let selectedMint = shownBalance?.stored.mint ?? .usdf
            if payment.fundsCollection {
                CollectionCurrencyPickerSheet(options: options, selectedMint: selectedMint) { mint in
                    select(mint, in: options)
                }
            } else {
                CurrencyPickerSheet(options: options, selectedMint: selectedMint) { mint in
                    select(mint, in: options)
                }
            }
        }
    }

    /// The pay content, with Payment Details pushed over it inside the same sheet from the fee or
    /// short line's ⓘ. Its back chevron slides the pay content back as it was left.
    private var collectionSheet: some View {
        let funding = payment.fundingSheet
        let page = CollectionPaySheetPage(
            wantsDetails: isShowingDetails,
            isFinishing: payment.isFinishing,
            content: funding
        )
        return PartialSheet(background: .clear) {
            Group {
                switch page {
                case .finishing:
                    finishingContent
                        .padding(.horizontal, 20)
                        .padding(.top, 30)
                case .pay, .details:
                    CollectionPaySheetPager(progress: page.pagerProgress) {
                        payContent(feeLine: funding?.feeLine, topUp: funding?.topUp)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.top, 30)
                            .allowsHitTesting(page == .pay)
                            .accessibilityHidden(page != .pay)
                        if let funding, !funding.detailsEntries.isEmpty {
                            CollectionPaymentDetailsView(
                                content: funding,
                                imageURL: payment.currencyImageURL,
                                onBack: { showDetails(false) }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .allowsHitTesting(page == .details)
                            .accessibilityHidden(page != .details)
                        }
                    }
                    .clipShape(CollectionPaySheetSides())
                }
            }
            .padding(.bottom, bottomPadding)
        }
        // A plan that stops converting and isn't short has no line to open details from; don't
        // reopen them when one returns.
        .onChange(of: funding?.detailsEntries.isEmpty ?? true) { _, hasNoEntry in
            if hasNoEntry { isShowingDetails = false }
        }
    }

    private func showDetails(_ shows: Bool) {
        withAnimation(.smooth(duration: 0.3)) { isShowingDetails = shows }
    }

    private func select(_ mint: PublicKey, in options: [ExchangedBalance]) {
        if let balance = options.first(where: { $0.stored.mint == mint }) {
            payment.selectCurrencyAction(exchangedBalance: balance)
        }
        isShowingTokenSelection = false
    }

    /// The pill's currency: the paying currency for a funded collection, else the selection.
    private var shownBalance: ExchangedBalance? {
        payment.fundsCollection ? payment.payingBalance : payment.selectedBalance
    }

    private func payContent(feeLine: String?, topUp: CollectionPaymentSheetContent.TopUp?) -> some View {
        VStack(spacing: 25) {
            VStack(spacing: 8) {
                PaymentRequestAvatar(userID: payeeID, member: payee, size: 56)
                Text(payee.map(ConversationLoadCoordinator.attributionName(for:)) ?? "")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                if !payment.fundsCollection, let handle = payee?.username?.handle {
                    Text(handle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            VStack(spacing: 8) {
                Text(amount)
                    .font(.appDisplayLarge)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if let feeLine {
                    CollectionPaymentInfoLine(text: feeLine) { showDetails(true) }
                }
                TokenSelectorButton(selectedBalance: shownBalance, showsChevron: !payment.fundsCollection) {
                    isShowingTokenSelection = true
                }
                .id(shownBalance?.stored.mint)
                .buttonStyle(TokenChipStyle())
                .padding(.top, 4)
            }
            if let topUp {
                VStack(spacing: 16) {
                    // Opens Payment Details as the fee line does (7.3).
                    CollectionPaymentInfoLine(text: topUp.shortBy, font: .appTextMedium) { showDetails(true) }
                    Button { addAndPay(topUp) } label: {
                        if isAdding {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Text(topUp.button)
                        }
                    }
                    .buttonStyle(.filled)
                    .disabled(isAdding)
                    Text(topUp.footnote)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                SwipeControl(text: "Swipe to Pay") {
                    switch await payment.submit() {
                    case .success:
                        didSucceed = true
                    case .failed, .short:
                        // A short plan redraws the sheet on its short state.
                        throw PaymentRequestPayDismissed()
                    }
                }
            }
        }
    }

    private var finishingContent: some View {
        PaymentRequestFinishing()
            .padding(.vertical, 40)
    }

    /// The Add button: verifies the contact Coinbase needs if it isn't yet, then adds the amount the
    /// button shows and pays.
    private func addAndPay(_ topUp: CollectionPaymentSheetContent.TopUp) {
        guard !isAdding else { return }
        verificationCoordinator.runGated(for: session, bind: { verificationViewModel = $0 }) {
            Task { await finishTopUp { await payment.addAndPay(topUpMicros: topUp.micros) } }
        }
    }

    private func finishTopUp(_ run: () async -> PaymentRequestPayment.Outcome) async {
        guard !isAdding else { return }
        isAdding = true
        defer { isAdding = false }
        if await run() == .success { didSucceed = true }
    }

    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 20 - reserved)
    }
}

/// "Finishing Payment" while the added Dollars land and the payment runs: in the sheet (4.4, 7.5,
/// 8.4), or in place of the Request screen when its own button added the money (1.3).
private struct PaymentRequestFinishing: View {
    var body: some View {
        VStack(spacing: 12) {
            LoadingView(color: .textMain, style: .large)
                .padding(.bottom, 8)
            Text("Finishing Payment")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
            Text("This usually takes about 10 seconds")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension VerificationCoordinator {
    /// ``runGated(for:bind:perform:)`` as a value: true once the contact Coinbase needs is
    /// verified, false when the user backs out or another verification is already up.
    func verified(for session: Session, bind: @MainActor @escaping (OnrampVerification?) -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            let gate = VerificationGateResult(continuation)
            runGated(for: session, bind: { viewModel in
                if viewModel != nil { gate.isShowing = true }
                bind(viewModel)
                if viewModel == nil { gate.resume(false) }
            }, perform: {
                gate.resume(true)
            })
            // runGated does nothing at all while another verification is up.
            if !gate.isShowing { gate.resume(false) }
        }
    }
}

/// Resumes a verification wait once, whichever of runGated's callbacks comes first.
@MainActor
private final class VerificationGateResult {
    var isShowing = false
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ verified: Bool) {
        continuation?.resume(returning: verified)
        continuation = nil
    }
}
