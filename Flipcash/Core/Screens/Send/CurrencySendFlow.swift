//
//  CurrencySendFlow.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Thrown to reset the SwipeControl knob without its success checkmark when a send doesn't complete.
private struct CurrencySendDismissed: Error {}

/// Send one currency from its Currency Info page: the amount, then who gets it, then the swipe in a
/// sheet over that list. "Or Give As Cash" skips the person and goes straight to the bill.
struct CurrencySendFlow: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(Container.self) private var container

    let mint: PublicKey

    var body: some View {
        CurrencySendFlowContent(sessionContainer: sessionContainer, container: container, mint: mint)
    }
}

private enum CurrencySendStep: Hashable {
    case selectRecipient
}

private struct CurrencySendFlowContent: View {

    @Environment(AppRouter.self) private var router

    @State private var viewModel: CurrencySendViewModel
    @State private var path: [CurrencySendStep] = []

    private let container: Container
    private let sessionContainer: SessionContainer

    init(sessionContainer: SessionContainer, container: Container, mint: PublicKey) {
        self.container = container
        self.sessionContainer = sessionContainer
        _viewModel = State(initialValue: CurrencySendViewModel(sessionContainer: sessionContainer, mint: mint))
    }

    var body: some View {
        NavigationStack(path: $path) {
            CurrencySendAmountScreen(viewModel: viewModel) {
                path.append(.selectRecipient)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(action: router.dismissSheet)
                }
            }
            .navigationDestination(for: CurrencySendStep.self) { step in
                switch step {
                case .selectRecipient:
                    CurrencySelectRecipientScreen(
                        viewModel: viewModel,
                        container: container,
                        sessionContainer: sessionContainer
                    )
                }
            }
        }
        .interactiveDismissDisabled()
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
        .sheet(item: $confirming) { target in
            CurrencySendConfirmSheet(target: target.model, amount: viewModel.enteredTotal, name: target.name, username: target.username, userID: target.userID, picture: target.picture)
        }
    }

    @ViewBuilder
    private func row(_ chat: Conversation) -> some View {
        let counterpart = chat.counterpart(excluding: conversationController.selfUserID)
        let name = conversationController.displayName(for: chat)
        let subject: ProfileAvatarStore.AvatarSubject = counterpart?.userID.map { .user($0) } ?? .chat(chat.id)

        RecipientRowScaffold(
            avatarID: counterpart?.userID?.uuidString ?? chat.id.description,
            title: name,
            subtitle: nil,
            imageData: sessionContainer.profileAvatars.data(for: subject),
            blurhash: counterpart?.profilePicture?.thumbnailBlurhash,
            accessibilityLabel: name,
            onTap: { select(chat, name: name, counterpart: counterpart) }
        ) {
            EmptyView()
        }
        .accessibilityIdentifier("currency-send-recipient-row")
        .task(id: subject) {
            await sessionContainer.profileAvatars.load(subject, picture: counterpart?.profilePicture)
        }
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
        give.onBillPresented = { router.dismissSheet() }
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
                    case .recipientNotFound:
                        router.dismissSheet()
                        throw CurrencySendDismissed()
                    case .failed:
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
        // Hold the success checkmark briefly, then dismiss the whole flow back to Currency Info.
        .task(id: didSucceed) {
            guard didSucceed else { return }
            try? await Task.delay(seconds: 1)
            guard !Task.isCancelled else { return }
            router.dismissSheet()
        }
    }

    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 20 - reserved)
    }
}
