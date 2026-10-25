//
//  PaymentRequestFlow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

// MARK: - Money actions -

/// The sheet a private group's send-cash button opens: send money as today, or request it.
struct MoneyActionsSheet: View {

    @Environment(\.dismiss) private var dismiss

    let sendMoney: () -> Void
    let requestMoney: () -> Void

    var body: some View {
        PartialSheet {
            VStack(alignment: .leading, spacing: 0) {
                Text("Money")
                    .font(.appTitle)
                    .foregroundStyle(Color.textMain)
                    .padding(.bottom, 16)

                row(symbol: "arrow.up", title: "Send Money", subtitle: "Send money to someone in the group, or multiple people") {
                    dismiss()
                    sendMoney()
                }
                row(symbol: "arrow.down", title: "Request Money", subtitle: "Collect money from people in the group") {
                    dismiss()
                    requestMoney()
                }

                CodeButton(style: .subtle, title: "Dismiss") { dismiss() }
                    .padding(.top, 8)
            }
            .padding(20)
        }
    }

    private func row(symbol: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 24)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.textMain)
            .padding(.vertical, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Flow -

private enum PaymentRequestStep: Hashable {
    case amount
    case summary
    case selectPeople
}

/// Request Money in a private group: the history, then New Request's amount, summary and confirm.
struct PaymentRequestFlow: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let conversationID: ConversationID

    var body: some View {
        PaymentRequestFlowContent(sessionContainer: sessionContainer, conversationID: conversationID)
    }
}

private struct PaymentRequestFlowContent: View {

    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PaymentRequestCreateViewModel
    @State private var history: PaymentRequestHistory
    @State private var path: [PaymentRequestStep] = []

    init(sessionContainer: SessionContainer, conversationID: ConversationID) {
        _viewModel = State(initialValue: PaymentRequestCreateViewModel(
            sessionContainer: sessionContainer,
            conversationID: conversationID
        ))
        _history = State(initialValue: PaymentRequestHistory(
            requests: sessionContainer.paymentRequests,
            conversationID: conversationID
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            PaymentRequestHistoryScreen(history: history) {
                viewModel.startNewRequest()
                path.append(.amount)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(action: { dismiss() })
                }
            }
            .navigationDestination(for: PaymentRequestStep.self) { step in
                switch step {
                case .amount:
                    PaymentRequestAmountScreen(viewModel: viewModel) {
                        path.append(.summary)
                    }
                case .summary:
                    PaymentRequestSummaryScreen(viewModel: viewModel, selectPeople: {
                        path.append(.selectPeople)
                    }, sent: { dismiss() })
                case .selectPeople:
                    PaymentRequestSelectPeopleScreen(viewModel: viewModel) {
                        path.removeLast()
                    }
                }
            }
        }
    }
}

// MARK: - History -

/// Request Money history for one chat: its open requests, then its resolved ones a page at a time.
@MainActor
@Observable
final class PaymentRequestHistory {

    static let resolvedPageSize = 20

    private(set) var openIDs: [PaymentRequestID] = []
    private(set) var resolvedIDs: [PaymentRequestID] = []
    private(set) var hasMoreResolved = true
    private(set) var isLoading = false

    let conversationID: ConversationID
    let requests: PaymentRequests

    @ObservationIgnored private var resolvedToken: Data?

    init(requests: PaymentRequests, conversationID: ConversationID) {
        self.requests = requests
        self.conversationID = conversationID
    }

    /// Open requests, nearest deadline first.
    var open: [GroupPaymentRequest] {
        openIDs.compactMap(requests.request).sorted {
            ($0.split?.endsAt ?? .distantFuture) < ($1.split?.endsAt ?? .distantFuture)
        }
    }

    /// Resolved requests, most recently ended first.
    var resolved: [GroupPaymentRequest] {
        resolvedIDs.compactMap(requests.request).sorted {
            ($0.effectiveClosedAt(at: .now) ?? .distantPast) > ($1.effectiveClosedAt(at: .now) ?? .distantPast)
        }
    }

    /// Reads every OPEN request and the first RESOLVED page, starting the resolved list over.
    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var ids: [PaymentRequestID] = []
            var token: Data?
            repeat {
                let page = try await requests.page(conversationID, section: .open, pageSize: PaymentRequests.openPageSize, after: token)
                ids += page.ids
                token = page.nextPagingToken
            } while token != nil
            openIDs = ids

            let first = try await requests.page(conversationID, section: .resolved, pageSize: Self.resolvedPageSize, after: nil)
            resolvedIDs = first.ids
            resolvedToken = first.nextPagingToken
            hasMoreResolved = first.nextPagingToken != nil
        } catch {
            logger.warning("Failed to load payment request history", metadata: ["error": "\(error)"])
        }
    }

    /// Reads the next RESOLVED page, if there is one and no read is running.
    func loadMoreResolved() async {
        guard hasMoreResolved, !isLoading, let token = resolvedToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await requests.page(conversationID, section: .resolved, pageSize: Self.resolvedPageSize, after: token)
            resolvedIDs += page.ids.filter { !resolvedIDs.contains($0) }
            resolvedToken = page.nextPagingToken
            hasMoreResolved = page.nextPagingToken != nil
        } catch {
            logger.warning("Failed to load more payment request history", metadata: ["error": "\(error)"])
        }
    }
}

private let logger = Logger(label: "flipcash.payment-request-history")

private struct PaymentRequestHistoryScreen: View {

    @Environment(Session.self) private var session

    let history: PaymentRequestHistory
    let newRequest: () -> Void

    @State private var selection: PaymentRequestSelection?

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    CodeButton(style: .filled, title: "New Request", action: newRequest)
                        .padding(.bottom, 12)

                    if !history.open.isEmpty {
                        header("Open Requests")
                        ForEach(history.open, id: \.id) { row($0) }
                    }
                    if !history.resolved.isEmpty {
                        header("Previous Requests")
                            .padding(.top, history.open.isEmpty ? 0 : 12)
                        ForEach(history.resolved, id: \.id) { request in
                            row(request)
                                .task {
                                    guard request.id == history.resolved.last?.id else { return }
                                    await history.loadMoreResolved()
                                }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Request Money")
        .navigationBarTitleDisplayMode(.inline)
        .task { await history.reload() }
        .fullScreenCover(item: $selection) { selection in
            PaymentRequestDetailsScreen(requestID: selection.id)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.appTextSmall)
            .foregroundStyle(Color.textSecondary)
    }

    private func row(_ request: GroupPaymentRequest) -> some View {
        let copy = PaymentRequestCopy(session.displayCurrency)
        return Button {
            selection = PaymentRequestSelection(id: request.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(history.requests.text(of: request)?.title ?? "Request")
                            .font(.appTextLarge)
                            .foregroundStyle(Color.textMain)
                            .lineLimit(1)
                        if let createdAt = request.createdAt {
                            Text(createdAt.formatted(.dateTime.month(.wide).day()))
                                .font(.appTextSmall)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Text(copy.historyAmounts(request))
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(16)
            .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Amount -

private struct PaymentRequestAmountScreen: View {

    @Bindable var viewModel: PaymentRequestCreateViewModel
    let next: () -> Void

    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .currency,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .hidden,
                actionState: .constant(.normal),
                actionEnabled: { _ in viewModel.canContinue },
                action: next,
                actionTitle: "Next"
            )
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle("Amount Per Person")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Summary -

private struct PaymentRequestSummaryScreen: View {

    @Bindable var viewModel: PaymentRequestCreateViewModel
    let selectPeople: () -> Void
    let sent: () -> Void

    @State private var isEditingName = false
    @State private var isPickingDeadline = false
    @State private var dialogItem: DialogItem?

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.amount?.formatted() ?? "")
                                .font(.appDisplayMedium)
                                .foregroundStyle(Color.textMain)
                            Text("per person")
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.bottom, 8)

                        summaryRow(label: "Name", value: viewModel.title, secondLine: nil) {
                            isEditingName = true
                        }
                        summaryRow(label: "People", value: viewModel.peopleValue, secondLine: viewModel.peopleSecondLine, action: selectPeople)
                        summaryRow(
                            label: "Timing",
                            value: viewModel.deadline.summaryValue(),
                            secondLine: "Request automatically closes after"
                        ) {
                            isPickingDeadline = true
                        }
                    }
                    .padding(20)
                }

                CodeButton(
                    isLoading: viewModel.isSending,
                    style: .filled,
                    title: viewModel.sendButtonTitle,
                    disabled: !viewModel.canSend
                ) {
                    viewModel.prepareConfirm()
                    dialogItem = confirm()
                }
                .padding(20)
            }
        }
        .navigationTitle("New Request")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.conversationID) {
            await viewModel.refreshMembers()
        }
        .sheet(isPresented: $isEditingName) {
            PaymentRequestNameEditor(title: viewModel.title) { viewModel.title = $0 }
        }
        .sheet(isPresented: $isPickingDeadline) {
            PaymentRequestDeadlineSheet(deadline: $viewModel.deadline)
        }
        .dialog(item: $dialogItem)
    }

    private func summaryRow(label: String, value: String, secondLine: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                    Text(value)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                    if let secondLine {
                        Text(secondLine)
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to change")
    }

    private func confirm() -> DialogItem {
        .info(title: "Send Request?", subtitle: "You will receive and hold the money collected") {
            DialogAction.standard("Send Request") {
                Task { await send() }
            }
            DialogAction.cancel()
        }
    }

    private func send() async {
        switch await viewModel.send() {
        case .sent:
            sent()
        case .failed(let copy):
            dialogItem = .alert(title: copy.title, subtitle: copy.subtitle) {
                DialogAction.okay(kind: .standard)
            }
        }
    }
}

// MARK: - Name -

private struct PaymentRequestNameEditor: View {

    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @FocusState private var isFocused: Bool

    let save: (String) -> Void

    init(title: String, save: @escaping (String) -> Void) {
        _text = State(initialValue: title)
        self.save = save
    }

    private var validated: String? { PaymentRequestTitleValidator().validate(text) }

    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $text)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(done)
                        .padding(14)
                        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12))
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: done)
                        .disabled(validated == nil)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { isFocused = true }
    }

    private func done() {
        guard let validated else { return }
        save(validated)
        dismiss()
    }
}

// MARK: - Deadline -

private struct PaymentRequestDeadlineSheet: View {

    @Environment(\.dismiss) private var dismiss

    @Binding var deadline: PaymentRequestDeadline

    @State private var customDate: Date = PaymentRequestDeadline.oneWeek.endsAt(sentAt: .now)
    @State private var isPickingCustom = false
    @State private var customRange = PaymentRequestDeadline.customRange(openedAt: .now)

    var body: some View {
        NavigationStack {
            List {
                ForEach(PaymentRequestDeadline.presets, id: \.rowTitle) { preset in
                    row(preset.rowTitle, isChecked: preset == deadline) {
                        deadline = preset
                        dismiss()
                    }
                }
                row("Custom", isChecked: isCustom) {
                    customRange = PaymentRequestDeadline.customRange(openedAt: .now)
                    if case .custom(let date) = deadline { customDate = date }
                    customDate = min(max(customDate, customRange.lowerBound), customRange.upperBound)
                    isPickingCustom = true
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.backgroundMain)
            .navigationTitle("Time To Pay")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $isPickingCustom) {
                customPicker
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isCustom: Bool {
        switch deadline {
        case .custom:                                              true
        case .oneDay, .threeDays, .oneWeek, .twoWeeks, .fourWeeks: false
        }
    }

    private var customPicker: some View {
        VStack {
            DatePicker(
                "Until",
                selection: $customDate,
                in: customRange,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .padding(20)
            Spacer()
        }
        .background(Color.backgroundMain)
        .navigationTitle("Custom")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    deadline = .custom(customDate)
                    dismiss()
                }
            }
        }
    }

    private func row(_ title: String, isChecked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                Spacer()
                if isChecked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.textMain)
                }
            }
            .contentShape(.rect)
        }
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

// MARK: - Select People -

private struct PaymentRequestSelectPeopleScreen: View {

    let viewModel: PaymentRequestCreateViewModel
    let done: () -> Void

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                SelectPeopleList(
                    members: viewModel.members,
                    isSelected: viewModel.isSelected,
                    toggle: viewModel.toggle,
                    rowIdentifier: "payment-request-member-row"
                )
                CodeButton(style: .filled, title: "Done", disabled: !viewModel.hasValidPeople, action: done)
                    .padding(20)
            }
        }
        .navigationTitle("Select People")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.conversationID) {
            await viewModel.refreshMembers()
        }
        .dialog(item: Binding(
            get: { viewModel.isShowingPeopleLimit ? peopleLimit : nil },
            set: { if $0 == nil { viewModel.isShowingPeopleLimit = false } }
        ))
    }

    private var peopleLimit: DialogItem {
        .info(title: "100 People Max", subtitle: "A request can include up to 100 people.") {
            DialogAction.okay(kind: .standard)
        }
    }
}
