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
///
/// Two cards like the Add Money sheet's and nothing else, matching Android (node 12243:1009).
struct MoneyActionsSheet: View {

    @Environment(\.dismiss) private var dismiss

    let sendMoney: () -> Void
    let requestMoney: () -> Void

    var body: some View {
        PartialSheet {
            VStack(spacing: 12) {
                row(icon: .withdraw, title: "Send Money", subtitle: "Send money to someone in the group, or multiple people", identifier: "money-action-send") {
                    dismiss()
                    sendMoney()
                }
                row(icon: .deposit, title: "Request Money", subtitle: "Collect money from people in the group", identifier: "money-action-request") {
                    dismiss()
                    requestMoney()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 20)
        }
    }

    private func row(icon: Asset, title: String, subtitle: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 12)

                Image.asset(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Color.textMain)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Flow -

private enum PaymentRequestStep: Hashable {
    case amount
    case summary
    case name
    case selectPeople
    case details(PaymentRequestID)
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
            PaymentRequestHistoryScreen(history: history, newRequest: {
                viewModel.startNewRequest()
                path.append(.amount)
            }, open: { path.append(.details($0)) })
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
                    PaymentRequestSummaryScreen(viewModel: viewModel, editName: {
                        path.append(.name)
                    }, selectPeople: {
                        path.append(.selectPeople)
                    }, sent: { dismiss() })
                case .name:
                    PaymentRequestNameScreen(title: viewModel.title) {
                        viewModel.title = $0
                        path.removeLast()
                    }
                case .selectPeople:
                    PaymentRequestSelectPeopleScreen(viewModel: viewModel) {
                        path.removeLast()
                    }
                case .details(let id):
                    PaymentRequestDetailsScreen(requestID: id, isPushed: true)
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
    let open: (PaymentRequestID) -> Void

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
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.appTextSmall)
            .foregroundStyle(Color.textSecondary)
    }

    private func row(_ request: GroupPaymentRequest) -> some View {
        let copy = PaymentRequestCopy(session.displayCurrency)
        return Button {
            open(request.id)
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
    let editName: () -> Void
    let selectPeople: () -> Void
    let sent: () -> Void

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

                        summaryRow(label: "Name", value: viewModel.title, secondLine: nil, action: editName)
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

/// The Name row's destination, drawn the way ``EditGroupNameScreen`` and ``ProfileNameScreen`` draw
/// theirs: one field under a heading, a countdown near the cap, and a filled button at the bottom.
private struct PaymentRequestNameScreen: View {

    @State private var text: String
    @FocusState private var isFocused: Bool

    let save: (String) -> Void

    /// Same threshold as the profile and group name screens.
    private static let countdownThreshold = 10

    init(title: String, save: @escaping (String) -> Void) {
        _text = State(initialValue: title)
        self.save = save
    }

    private var validated: String? { PaymentRequestTitleValidator().validate(text) }

    private var remainingScalars: Int {
        PaymentRequestTitleValidator.maxScalars - text.unicodeScalars.count
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text("What is the request for?")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                TextField("Request Name", text: $text)
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(done)
                    .padding(.top, 32)

                Spacer()

                if remainingScalars < Self.countdownThreshold {
                    Text("\(remainingScalars) characters")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                }

                Button("Done", action: done)
                    .buttonStyle(.filled)
                    .disabled(validated == nil)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .focusAfterPush($isFocused)
    }

    private func done() {
        guard let validated else { return }
        save(validated)
    }
}

// MARK: - Deadline -

private struct PaymentRequestDeadlineSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var deadline: PaymentRequestDeadline

    @State private var picker: PaymentRequestDeadlinePicker
    @State private var height: CGFloat = 0

    init(deadline: Binding<PaymentRequestDeadline>) {
        _deadline = deadline
        _picker = State(initialValue: PaymentRequestDeadlinePicker(deadline: deadline.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Time To Pay")
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
                .padding(.top, 24)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    field(label: "Starts", value: "Today, on send", isEditing: false)
                    field(label: "Closes", value: picker.closesValue, isEditing: true)
                        .onChange(of: picker.closesValue) { _, value in
                            AccessibilityNotification.Announcement("Closes \(value)").post()
                        }
                }
                Text(picker.summaryLine)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            chips

            PaymentRequestDeadlineGrid(picker: picker)

            HStack {
                Text("Time")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                Spacer()
                DatePicker(
                    "Time",
                    selection: Binding(get: { picker.timeRowDate }, set: { picker.setTime($0) }),
                    in: picker.timeRange,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .labelsHidden()
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(Color.backgroundSecondary, in: .rect(cornerRadius: 12))

            Button("Done") {
                deadline = picker.choice
                dismiss()
            }
            .buttonStyle(.filled)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationBackground(Color.backgroundMain)
        .presentationDetents([height > 0 ? .height(height) : .large])
        .presentationDragIndicator(.visible)
    }

    private func field(label: String, value: String, isEditing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.appTextCaption)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.backgroundSecondary, in: .rect(cornerRadius: 12))
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(PaymentRequestDeadline.presets, id: \.rowTitle) { preset in
                let isSelected = picker.selectedPreset == preset
                Button {
                    picker.select(preset)
                } label: {
                    Text(preset.rowTitle)
                        .font(.appTextSmall)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? Color.black : Color.textMain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .anchorPreference(key: SelectionAnchors<String>.self, value: .bounds) { [preset.rowTitle: $0] }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .backgroundPreferenceValue(SelectionAnchors<String>.self) { anchors in
            GeometryReader { proxy in
                ForEach(Array(anchors.keys), id: \.self) { title in
                    if let anchor = anchors[title] {
                        let rect = proxy[anchor]
                        Capsule().fill(Color.backgroundSecondary)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                // One capsule for the selection, so it slides between chips instead of fading.
                if let title = picker.selectedPreset?.rowTitle, let anchor = anchors[title] {
                    let rect = proxy[anchor]
                    Capsule().fill(Color.white)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: picker.selectedPreset)
    }
}

/// The Time To Pay grid: five weeks from today's, with only today through today + 28 days tappable.
private struct PaymentRequestDeadlineGrid: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let picker: PaymentRequestDeadlinePicker

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
            ForEach(picker.gridDays, id: \.self) { day in
                cell(day)
            }
        }
        .backgroundPreferenceValue(SelectionAnchors<Date>.self) { anchors in
            GeometryReader { proxy in
                // One band per week row, so a change grows or shrinks it without seams between cells.
                ForEach(0..<weeks.count, id: \.self) { row in
                    bandRow(weeks[row], anchors: anchors, proxy: proxy)
                }
                // One circle for the closing day, drawn under the cells so it slides between days instead of fading.
                if let anchor = anchors[picker.selectedDay] {
                    let rect = proxy[anchor]
                    Circle().fill(Color.white).frame(width: Self.circle, height: Self.circle)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .padding(12)
        .background(Color.backgroundSecondary, in: .rect(cornerRadius: 16))
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: picker.selectedDay)
    }

    private var weekdaySymbols: [String] {
        let calendar = picker.calendar
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    @ViewBuilder
    private func cell(_ day: Date) -> some View {
        let calendar = picker.calendar
        let isEnabled = picker.isEnabled(day)
        let isSelected = calendar.isDate(day, inSameDayAs: picker.selectedDay)
        let isStart = picker.rangeStart.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
        let number = calendar.component(.day, from: day)
        Button {
            picker.select(day: day)
        } label: {
            ZStack {
                if isStart {
                    Circle().fill(Self.startGrey).frame(width: Self.circle, height: Self.circle)
                }
                // The 1st stacks its month label above the number, centred as one group in the circle.
                VStack(spacing: 0) {
                    if number == 1 {
                        Text(day.formatted(.dateTime.month(.abbreviated).locale(picker.locale)).uppercased())
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(monthLabelColor(isEnabled: isEnabled, isSelected: isSelected, isStart: isStart, inBand: picker.band(for: day) != nil))
                    }
                    Text("\(number)")
                        .font(.appTextMedium)
                        .foregroundStyle(isSelected ? Color.black : Color.textMain)
                        .opacity(isEnabled ? 1 : 0.3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .contentShape(.rect)
            .anchorPreference(key: SelectionAnchors<Date>.self, value: .bounds) { [calendar.startOfDay(for: day): $0] }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityHidden(!isEnabled)
        .accessibilityLabel(picker.accessibilityDay(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func monthLabelColor(isEnabled: Bool, isSelected: Bool, isStart: Bool, inBand: Bool) -> Color {
        if isSelected { return Self.grey(0x59) }
        if isStart { return Self.grey(0xD9) }
        if isEnabled && inBand { return Self.grey(0x9E) }
        return Self.grey(0x7B)
    }

    private static func grey(_ value: Double) -> Color {
        Color(red: value / 255, green: value / 255, blue: value / 255)
    }

    private static let circle: CGFloat = 34
    private static let startGrey = Color(red: 0x6B / 255, green: 0x6B / 255, blue: 0x6E / 255)

    private var weeks: [[Date]] {
        stride(from: 0, to: picker.gridDays.count, by: 7).map { Array(picker.gridDays[$0..<min($0 + 7, picker.gridDays.count)]) }
    }

    /// A week row's part of the range band, collapsed to the row's leading edge when the range misses it.
    @ViewBuilder
    private func bandRow(_ week: [Date], anchors: [Date: Anchor<CGRect>], proxy: GeometryProxy) -> some View {
        if let first = week.first.flatMap({ anchors[$0] }), let last = week.last.flatMap({ anchors[$0] }) {
            let rowStart = proxy[first]
            let rowEnd = proxy[last]
            let inRange = week.compactMap { day in picker.band(for: day).map { (day, $0) } }
            let radius = Self.circle / 2
            let leading: CGFloat = inRange.first.flatMap { day, band in
                anchors[day].map { band.fromCenter ? proxy[$0].midX : proxy[$0].minX }
            } ?? rowStart.minX
            let trailing: CGFloat = inRange.last.flatMap { day, band in
                anchors[day].map { band.toCenter ? proxy[$0].midX : proxy[$0].maxX }
            } ?? rowStart.minX
            // Square ends clipped to a capsule spanning the row: only the row's edges ever round, so an end
            // sliding with the circle never animates a corner radius.
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: max(trailing - leading, 0), height: Self.circle)
                .position(x: (leading + trailing) / 2, y: rowEnd.midY)
                .mask {
                    Capsule()
                        .frame(width: rowEnd.maxX - rowStart.minX, height: radius * 2)
                        .position(x: (rowStart.minX + rowEnd.maxX) / 2, y: rowEnd.midY)
                }
                .opacity(inRange.isEmpty ? 0 : 1)
        }
    }
}

/// Each tappable item's bounds, so a selection highlight can be drawn once and slide between items.
private struct SelectionAnchors<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [ID: Anchor<CGRect>], nextValue: () -> [ID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
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
