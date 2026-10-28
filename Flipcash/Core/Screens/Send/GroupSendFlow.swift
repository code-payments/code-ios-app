//
//  GroupSendFlow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Thrown to reset the SwipeControl knob without its success checkmark when a send doesn't complete.
private struct GroupSendDismissed: Error {}

/// Send Cash in a private group: the total, then the members it's split between, then the swipe
/// in a sheet over that list.
struct GroupSendFlow: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let conversationID: ConversationID

    var body: some View {
        GroupSendFlowContent(sessionContainer: sessionContainer, conversationID: conversationID)
    }
}

private enum GroupSendStep: Hashable {
    case selectPeople
}

private struct GroupSendFlowContent: View {

    @Environment(AppRouter.self) private var router

    @State private var viewModel: GroupSendViewModel
    @State private var path: [GroupSendStep] = []

    init(sessionContainer: SessionContainer, conversationID: ConversationID) {
        _viewModel = State(initialValue: GroupSendViewModel(
            sessionContainer: sessionContainer,
            conversationID: conversationID
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            GroupSendAmountScreen(viewModel: viewModel) {
                if viewModel.confirmAmount() { path.append(.selectPeople) }
            }
            .toolbar { closeButton }
            .navigationDestination(for: GroupSendStep.self) { step in
                switch step {
                case .selectPeople:
                    GroupSendSelectPeopleScreen(viewModel: viewModel)
                }
            }
        }
        // Like the share-to-chats screen, the flow closes only from its X.
        .interactiveDismissDisabled()
        .onChange(of: viewModel.depositMint) { _, mint in
            guard let mint else { return }
            viewModel.depositMint = nil
            router.navigate(to: .currencyInfoForDeposit(mint))
        }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            CloseButton(action: router.dismissSheet)
        }
    }
}

// MARK: - Amount -

private struct GroupSendAmountScreen: View {

    @Bindable var viewModel: GroupSendViewModel
    let next: () -> Void

    @State private var isShowingTokenSelection = false

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
            ToolbarItem(placement: .principal) {
                TokenSelectorButton(
                    selectedBalance: viewModel.selectedBalance,
                    action: { isShowingTokenSelection = true }
                )
                .id(viewModel.selectedBalance?.stored.mint)
            }
        }
        // On the screen, not the button: the button's `.id` changes with the pick, and a sheet
        // hosted on it would be torn down mid-dismiss, taking the whole flow with it.
        .sheet(isPresented: $isShowingTokenSelection) {
            let options = viewModel.paymentOptions
            CurrencyPickerSheet(
                options: options,
                selectedMint: viewModel.selectedBalance?.stored.mint ?? .usdf,
                onSelect: { mint in
                    if let balance = options.first(where: { $0.stored.mint == mint }) {
                        viewModel.selectCurrencyAction(exchangedBalance: balance)
                    }
                    isShowingTokenSelection = false
                }
            )
        }
    }
}

// MARK: - Select People -

private struct GroupSendSelectPeopleScreen: View {

    let viewModel: GroupSendViewModel

    @State private var isConfirming = false

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                SelectPeopleList(
                    members: viewModel.members,
                    isSelected: viewModel.isSelected,
                    toggle: viewModel.toggle,
                    rowIdentifier: "group-send-member-row"
                )

                CodeButton(
                    style: .filled,
                    title: viewModel.sendButtonTitle,
                    disabled: viewModel.selection.isEmpty
                ) {
                    if viewModel.confirmSelection() {
                        isConfirming = true
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Select People")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.conversationID) {
            await viewModel.refreshMembers()
        }
        .sheet(isPresented: $isConfirming) {
            GroupSendConfirmSheet(viewModel: viewModel)
        }
    }
}

// MARK: - Member checklist -

/// The checklist of a group's members that group send and a new request both pick from.
struct SelectPeopleList: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let members: [GroupPortrait]
    let isSelected: (UserID) -> Bool
    let toggle: (UserID) -> Void
    let rowIdentifier: String

    var body: some View {
        List {
            Section {
                ForEach(members, id: \.userID) { portrait in
                    row(portrait)
                }
            } header: {
                Text("Members")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ portrait: GroupPortrait) -> some View {
        let checked = isSelected(portrait.userID)
        return RecipientRowScaffold(
            avatarID: portrait.userID.uuidString,
            title: portrait.name,
            subtitle: nil,
            imageData: sessionContainer.profileAvatars.data(for: portrait.userID),
            blurhash: portrait.picture?.thumbnailBlurhash,
            accessibilityLabel: portrait.name,
            onTap: { toggle(portrait.userID) }
        ) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(checked ? Color.textMain : Color.textSecondary)
        }
        .accessibilityIdentifier(rowIdentifier)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .task(id: portrait.userID) {
            await sessionContainer.profileAvatars.load(userID: portrait.userID, picture: portrait.picture)
        }
    }
}

// MARK: - Confirm -

/// The swipe to send, in a sheet sized to its content over Select People.
private struct GroupSendConfirmSheet: View {

    @Environment(AppRouter.self) private var router

    let viewModel: GroupSendViewModel

    @State private var didSucceed = false
    @State private var isShowingTokenSelection = false

    /// Faces drawn before the rest collapse into a "+N" badge.
    private static let maxFaces = 4

    /// "Alex Morgan and 5 Others", or just "Alex Morgan" for one.
    private var recipientsTitle: String {
        let picked = viewModel.selectedMembers
        guard let first = picked.first else { return "" }
        switch picked.count {
        case 1:  return first.name
        case 2:  return "\(first.name) and 1 Other"
        default: return "\(first.name) and \(picked.count - 1) Others"
        }
    }

    var body: some View {
        PartialSheet(background: .clear) {
            VStack(spacing: 25) {
                VStack(spacing: 12) {
                    faces
                    Text(recipientsTitle)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                }
                VStack(spacing: 8) {
                    Text(viewModel.enteredTotal?.formatted() ?? "")
                        .font(.appDisplayLarge)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    if viewModel.selection.count > 1, let each = viewModel.eachLabel {
                        Text(each)
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                    // Filled as on Android's cash sheets: with no toolbar around it, the chevron
                    // alone wouldn't say the currency can be changed.
                    TokenSelectorButton(selectedBalance: viewModel.selectedBalance) {
                        isShowingTokenSelection = true
                    }
                    .id(viewModel.selectedBalance?.stored.mint)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .padding(.top, 4)
                }
                SwipeControl(text: "Swipe to Send") {
                    switch await viewModel.submit() {
                    case .success:
                        didSucceed = true
                    case .failed:
                        throw GroupSendDismissed()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, bottomPadding)
        }
        // Hold the success checkmark briefly, then dismiss the whole flow back to the chat.
        .task(id: didSucceed) {
            guard didSucceed else { return }
            await PaymentSuccess.release { router.dismissSheet() }
        }
        .sheet(isPresented: $isShowingTokenSelection) {
            let options = viewModel.paymentOptions
            CurrencyPickerSheet(
                options: options,
                selectedMint: viewModel.selectedBalance?.stored.mint ?? .usdf,
                onSelect: { mint in
                    if let balance = options.first(where: { $0.stored.mint == mint }) {
                        viewModel.selectCurrencyAction(exchangedBalance: balance)
                    }
                    isShowingTokenSelection = false
                }
            )
        }
    }

    private var faces: some View {
        let picked = viewModel.selectedMembers
        let overflow = picked.count - Self.maxFaces
        return HStack(spacing: -12) {
            ForEach(picked.prefix(Self.maxFaces), id: \.userID) { portrait in
                GroupSendAvatar(portrait: portrait, size: 56)
                    .overlay(Circle().stroke(Color.backgroundMain, lineWidth: 2))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .frame(width: 56, height: 56)
                    .background(Color.backgroundSecondary, in: .circle)
                    .overlay(Circle().stroke(Color.backgroundMain, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }

    /// The design's 20 under the swipe, less whatever the sheet already holds back for the home
    /// indicator — stacking the two doubles the gap.
    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 20 - reserved)
    }
}

private struct GroupSendAvatar: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let portrait: GroupPortrait
    let size: CGFloat

    var body: some View {
        ContactAvatarView(
            id: portrait.userID.uuidString,
            displayName: portrait.name,
            imageData: sessionContainer.profileAvatars.data(for: portrait.userID),
            blurhash: portrait.picture?.thumbnailBlurhash,
            size: size
        )
        .task(id: portrait.userID) {
            await sessionContainer.profileAvatars.load(userID: portrait.userID, picture: portrait.picture)
        }
    }
}
