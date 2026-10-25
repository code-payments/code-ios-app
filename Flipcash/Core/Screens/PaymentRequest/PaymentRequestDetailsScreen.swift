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
    @Environment(\.dismiss) private var dismiss

    let requestID: PaymentRequestID

    @State private var dialogItem: DialogItem?
    /// A confirm queued behind an options sheet, shown once that sheet is gone.
    @State private var queuedDialog: DialogItem?
    /// Whether the last fetch carried an intent ID; the ID itself stays with ``PaymentRequestPayment``.
    @State private var hasPaymentIntent = false
    @State private var payment: PaymentRequestPayment?
    @State private var isPreparing = false
    @State private var isPaying = false
    @State private var isUpdating = false

    var body: some View {
        NavigationStack {
            // The status line counts down, so redraw at least once a minute.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let content = content(at: context.date) {
                    loaded(content)
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
                    CloseButton(action: { dismiss() })
                }
            }
        }
        .task(id: requestID) { await load() }
        .dialog(item: $dialogItem)
        .sheet(isPresented: $isPaying) {
            if let payment, let creator = payment.request?.creator {
                PaymentRequestPaySheet(
                    payment: payment,
                    payee: member(creator),
                    payeeID: creator,
                    amount: payAmount(payment)
                )
            }
        }
    }

    // MARK: - Content -

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
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            if let sendTitle = content.sendTitle {
                CodeButton(isLoading: isPreparing, style: .filled, title: sendTitle) {
                    pay()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private func header(_ content: PaymentRequestDetailsContent) -> some View {
        let creator = sessionContainer.paymentRequests.request(requestID)?.creator
        return VStack(alignment: .leading, spacing: 16) {
            Text(content.title)
                .font(.appDisplayCompact)
                .foregroundStyle(Color.textMain)
                .fixedSize(horizontal: false, vertical: true)
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
                Text(content.statusLine)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func shareRow(_ row: PaymentRequestDetailsContent.Row) -> some View {
        Button {
            switch row.action {
            case .markPaid: presentMarkPaidOptions(row)
            case .none:     break
            }
        } label: {
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
                }
                Spacer(minLength: 8)
                Text(row.amount)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 64)
            .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(row.action == .none || isUpdating)
        .accessibilityElement(children: .combine)
    }

    /// The viewer's reading of the request, or nil until it and its title are loaded.
    private func content(at now: Date) -> PaymentRequestDetailsContent? {
        let requests = sessionContainer.paymentRequests
        guard let request = requests.request(requestID), let text = requests.text(of: request) else { return nil }
        return PaymentRequestDetailsContent(
            request: request,
            title: text.title,
            viewer: session.userID,
            hasPaymentIntent: hasPaymentIntent,
            copy: PaymentRequestCopy(session.displayCurrency),
            now: now,
            name: { member($0).map(ConversationLoadCoordinator.attributionName(for:)) ?? "Someone" }
        )
    }

    private func member(_ userID: UserID) -> ConversationMember? {
        guard let request = sessionContainer.paymentRequests.request(requestID), let chatID = request.chatID else { return nil }
        return sessionContainer.groupRosters
            .members(for: chatID, creator: request.creator)
            .first { $0.userID == userID }
    }

    private func payAmount(_ payment: PaymentRequestPayment) -> String {
        guard let request = payment.request, let share = payment.share else { return "" }
        return PaymentRequestCopy(session.displayCurrency).shareText(share, of: request)
    }

    // MARK: - Actions -

    private func load() async {
        let requests = sessionContainer.paymentRequests
        do {
            hasPaymentIntent = try await requests.refresh(requestID) != nil
        } catch {
            hasPaymentIntent = false
        }
        guard let chatID = requests.request(requestID)?.chatID else { return }
        await requests.loadSeal(for: chatID)
        await sessionContainer.groupRosters.refresh(chatID)
    }

    /// Refetches for the intent ID right before the swipe sheet, as the spec requires.
    private func pay() {
        Task {
            isPreparing = true
            defer { isPreparing = false }
            let payment = self.payment ?? PaymentRequestPayment(requestID: requestID, sessionContainer: sessionContainer)
            self.payment = payment
            switch await payment.prepare() {
            case .ready:
                isPaying = true
            case .nothingToPay, .closed, .failed:
                hasPaymentIntent = false
            }
        }
    }

    private func presentCloseOptions() {
        present(.options {
            DialogAction.destructive("Close Request") {
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
            DialogAction.destructive("Close Request") {
                Task { await update { try await $0.close(requestID) } }
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

/// The swipe-to-send sheet for the viewer's share: the creator, the amount, the token picker.
private struct PaymentRequestPaySheet: View {

    @Environment(\.dismiss) private var dismiss

    let payment: PaymentRequestPayment
    let payee: ConversationMember?
    let payeeID: UserID
    let amount: String

    @State private var didSucceed = false
    @State private var isShowingTokenSelection = false

    var body: some View {
        PartialSheet(background: .clear) {
            VStack(spacing: 25) {
                VStack(spacing: 8) {
                    PaymentRequestAvatar(userID: payeeID, member: payee, size: 56)
                    Text(payee.map(ConversationLoadCoordinator.attributionName(for:)) ?? "")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                    if let handle = payee?.username?.handle {
                        Text("@\(handle)")
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
                    TokenSelectorButton(selectedBalance: payment.selectedBalance) {
                        isShowingTokenSelection = true
                    }
                    .id(payment.selectedBalance?.stored.mint)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .padding(.top, 4)
                }
                SwipeControl(text: "Swipe to Send") {
                    switch await payment.submit() {
                    case .success:
                        didSucceed = true
                    case .failed:
                        throw PaymentRequestPayDismissed()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, bottomPadding)
        }
        // Hold the success checkmark briefly, then return to the details, now showing the row paid.
        .task(id: didSucceed) {
            guard didSucceed else { return }
            try? await Task.delay(seconds: 1)
            guard !Task.isCancelled else { return }
            dismiss()
        }
        .sheet(isPresented: $isShowingTokenSelection) {
            SelectCurrencyScreen(isPresented: $isShowingTokenSelection) { balance in
                payment.selectCurrencyAction(exchangedBalance: balance)
            }
        }
    }

    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 20 - reserved)
    }
}
