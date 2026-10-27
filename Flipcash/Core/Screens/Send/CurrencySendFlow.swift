//
//  CurrencySendFlow.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Thrown to reset the SwipeControl knob without its success checkmark when a send doesn't complete.
private struct CurrencySendDismissed: Error {}

/// What the confirm sheet's dismissal means: a send that succeeded leaves Select Recipient for
/// Currency Info once the sheet is gone, and a sheet closed any other way just returns to the list.
nonisolated struct CurrencySendHandoff {
    private(set) var sent = false

    mutating func sendSucceeded() { sent = true }

    /// Whether to leave the flow now that the sheet has finished dismissing. Reads once.
    mutating func sheetDidDismiss() -> Bool {
        defer { sent = false }
        return sent
    }
}

/// Send one currency from its Currency Info page: the amount, then who gets it, then the swipe in a
/// sheet over that list. "Or Give As Cash" skips the person and goes straight to the bill. The
/// amount and the recipient list are pushed onto Currency Info's stack; only the swipe is a sheet.
struct CurrencySendAmountDestination: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let mint: PublicKey

    var body: some View {
        CurrencySendAmountHost(sessionContainer: sessionContainer, mint: mint)
    }
}

private struct CurrencySendAmountHost: View {

    @Environment(AppRouter.self) private var router

    @State private var viewModel: CurrencySendViewModel

    private let mint: PublicKey

    init(sessionContainer: SessionContainer, mint: PublicKey) {
        self.mint = mint
        _viewModel = State(initialValue: CurrencySendViewModel(sessionContainer: sessionContainer, mint: mint))
    }

    var body: some View {
        CurrencySendAmountScreen(viewModel: viewModel) {
            router.push(.currencySendRecipient(mint, amount: viewModel.enteredAmount))
        }
    }
}

/// Select Recipient, pushed over the amount. It carries the typed amount in its route and rebuilds
/// the view model from it, so the two screens share nothing but the route.
struct CurrencySendRecipientDestination: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(Container.self) private var container

    let mint: PublicKey
    let amount: String

    var body: some View {
        CurrencySendRecipientHost(sessionContainer: sessionContainer, container: container, mint: mint, amount: amount)
    }
}

private struct CurrencySendRecipientHost: View {

    @State private var viewModel: CurrencySendViewModel

    private let container: Container
    private let sessionContainer: SessionContainer

    init(sessionContainer: SessionContainer, container: Container, mint: PublicKey, amount: String) {
        self.container = container
        self.sessionContainer = sessionContainer
        let model = CurrencySendViewModel(sessionContainer: sessionContainer, mint: mint)
        model.enteredAmount = amount
        _viewModel = State(initialValue: model)
    }

    var body: some View {
        CurrencySelectRecipientScreen(viewModel: viewModel, container: container, sessionContainer: sessionContainer)
    }
}

// MARK: - Amount -

private struct CurrencySendAmountScreen: View {

    @Bindable var viewModel: CurrencySendViewModel
    let next: () -> Void

    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .currency,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .balanceWithLimit(viewModel.available),
                actionState: .constant(.normal),
                actionEnabled: { _ in viewModel.canContinue },
                action: next,
                actionTitle: "Next",
                header: AnyView(EnterAmountHeader(
                    enteredAmount: $viewModel.enteredAmount,
                    hint: .available(viewModel.available)
                ))
            )
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle("")
        .toolbar {
            // The currency is the page the user came from, so the label stands alone: no chevron,
            // and nothing to tap.
            ToolbarItem(placement: .principal) {
                CurrencyLabel(
                    imageURL: viewModel.selectedBalance?.stored.imageURL,
                    name: viewModel.selectedBalance?.stored.name ?? "",
                    amount: nil
                )
                .accessibilityIdentifier("currency-send-currency")
            }
        }
    }
}

// MARK: - Select Recipient -

private struct CurrencySelectRecipientScreen: View {

    @Environment(ConversationController.self) private var conversationController
    @Environment(AppRouter.self) private var router

    let viewModel: CurrencySendViewModel
    let container: Container
    let sessionContainer: SessionContainer

    @State private var query = ""
    @State private var confirming: ConfirmTarget?
    @State private var handoff = CurrencySendHandoff()

    /// What the confirm sheet is open for: the recipient, and the send view model built for them.
    private struct ConfirmTarget: Identifiable {
        let id: ConversationID
        let model: SendAmountViewModel
        let name: String
        let username: Username?
        let userID: UserID?
        let picture: ProfilePicture?
    }

    private var recipients: [Conversation] {
        CurrencySendRecipients.recipients(
            in: conversationController.chatListConversations,
            query: query,
            selfUserID: conversationController.selfUserID,
            name: conversationController.displayName(for:)
        )
    }

    var body: some View {
        Background(color: .backgroundMain) {
            List {
                ForEach(recipients) { chat in
                    row(chat)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(.rowSeparator)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Always on screen, empty list or not.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CodeButton(style: .filledSecondary, title: "Or Give As Cash") {
                    giveAsCash()
                }
                .padding(20)
            }
        }
        .navigationTitle("Select Recipient")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .sheet(item: $confirming, onDismiss: {
            // After the dismiss animation: nothing on the stack moves while the sheet is up.
            if handoff.sheetDidDismiss() { leaveFlow() }
        }) { target in
            CurrencySendConfirmSheet(target: target.model, amount: viewModel.enteredTotal, name: target.name, username: target.username, userID: target.userID, picture: target.picture) {
                handoff.sendSucceeded()
                confirming = nil
            }
        }
    }

    @ViewBuilder
    private func row(_ chat: Conversation) -> some View {
        let counterpart = chat.counterpart(excluding: conversationController.selfUserID)
        let name = conversationController.displayName(for: chat)
        let subject: ProfileAvatarStore.AvatarSubject = counterpart?.userID.map { .user($0) } ?? .chat(chat.id)

        // Compact, per the design: a 24pt avatar and a 17pt semibold name, 48pt tall. The chat list's
        // row is 44pt of avatar and a bold 16pt title, which reads as twice the size here.
        Button {
            select(chat, name: name, counterpart: counterpart)
        } label: {
            HStack(spacing: 16) {
                ContactAvatarView(
                    id: counterpart?.userID?.uuidString ?? chat.id.description,
                    displayName: name,
                    imageData: sessionContainer.profileAvatars.data(for: subject),
                    blurhash: counterpart?.profilePicture?.thumbnailBlurhash,
                    size: 24
                )
                Text(name)
                    .font(.default(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The divider starts under the name, not under the avatar.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 40 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("currency-send-recipient-row")
        .task(id: subject) {
            await sessionContainer.profileAvatars.load(subject, picture: counterpart?.profilePicture)
        }
    }

    /// Back to Currency Info: pops the recipient list and the amount beneath it.
    private func leaveFlow() {
        router.popTopmost(2)
    }

    private func select(_ chat: Conversation, name: String, counterpart: ConversationMember?) {
        guard let target = SendTarget(
            conversation: chat,
            dmChatID: chat.id.data,
            selfUserID: conversationController.selfUserID ?? UUID()
        ) else { return }
        let model = SendAmountViewModel(sessionContainer: sessionContainer, target: target, mint: viewModel.mint)
        model.enteredAmount = viewModel.enteredAmount
        confirming = ConfirmTarget(
            id: chat.id,
            model: model,
            name: name,
            username: counterpart?.username,
            userID: counterpart?.userID,
            picture: counterpart?.profilePicture
        )
    }

    /// The bill for the entered amount and this currency, skipping the Give screen's own entry.
    private func giveAsCash() {
        let give = GiveViewModel(container: container, sessionContainer: sessionContainer, mint: viewModel.mint)
        give.enteredAmount = viewModel.enteredAmount
        give.onBillPresented = { leaveFlow() }
        give.giveAction()
    }
}

// MARK: - Confirm -

/// The swipe to send, in a sheet sized to its content over Select Recipient.
private struct CurrencySendConfirmSheet: View {

    @Environment(AppRouter.self) private var router
    @Environment(SessionContainer.self) private var sessionContainer

    let target: SendAmountViewModel
    let amount: FiatAmount?
    let name: String
    let username: Username?
    let userID: UserID?
    let picture: ProfilePicture?
    /// Called once the success state has been held; the presenter dismisses the sheet and then leaves.
    let onSent: () -> Void

    @State private var didSucceed = false
    /// From the swipe's start until it fails: the sheet stays put while the send is in flight.
    @State private var isSending = false

    var body: some View {
        PartialSheet(background: .clear, canDismiss: !isSending && !didSucceed) {
            VStack(spacing: 25) {
                VStack(spacing: 8) {
                    ContactAvatarView(
                        id: userID?.uuidString ?? name,
                        displayName: name,
                        imageData: userID.flatMap { sessionContainer.profileAvatars.data(for: .user($0)) },
                        blurhash: picture?.thumbnailBlurhash,
                        size: 56
                    )
                    .padding(.bottom, 4)
                    Text(name)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                    if let username {
                        Text("@\(username.value)")
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                VStack(spacing: 8) {
                    Text(amount?.formatted() ?? "")
                        .font(.appDisplayLarge)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    // The same label the picker would draw, without the picker.
                    CurrencyLabel(
                        imageURL: target.selectedBalance?.stored.imageURL,
                        name: target.selectedBalance?.stored.name ?? "",
                        amount: nil
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .padding(.top, 4)
                }
                SwipeControl(text: target.swipeLabel) {
                    isSending = true
                    switch await target.sendAction() {
                    case .success:
                        didSucceed = true
                    case .recipientNotFound, .failed:
                        isSending = false
                        throw CurrencySendDismissed()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, bottomPadding)
        }
        .task { await target.prewarmVerifiedRate() }
        // Hold the success checkmark briefly, then hand off to the presenter to dismiss.
        .task(id: didSucceed) {
            guard didSucceed else { return }
            await PaymentSuccess.release { onSent() }
        }
    }

    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 20 - reserved)
    }
}
