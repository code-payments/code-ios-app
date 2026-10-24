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
                path.append(.selectPeople)
            }
            .toolbar { closeButton }
            .navigationDestination(for: GroupSendStep.self) { step in
                switch step {
                case .selectPeople:
                    GroupSendSelectPeopleScreen(viewModel: viewModel)
                        .toolbar { closeButton }
                }
            }
        }
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
            SelectCurrencyScreen(isPresented: $isShowingTokenSelection) { balance in
                viewModel.selectCurrencyAction(exchangedBalance: balance)
            }
        }
    }
}

// MARK: - Select People -

private struct GroupSendSelectPeopleScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let viewModel: GroupSendViewModel

    @State private var isConfirming = false

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                List {
                    ForEach(viewModel.members, id: \.userID) { portrait in
                        row(portrait)
                            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

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

    private func row(_ portrait: GroupPortrait) -> some View {
        let isSelected = viewModel.isSelected(portrait.userID)
        return Button {
            viewModel.toggle(portrait.userID)
        } label: {
            HStack(spacing: 12) {
                GroupSendAvatar(portrait: portrait, size: 40)
                Text(portrait.name)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.textMain : Color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("group-send-member-row")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Confirm -

/// The swipe to send, in a sheet sized to its content over Select People.
private struct GroupSendConfirmSheet: View {

    @Environment(AppRouter.self) private var router

    let viewModel: GroupSendViewModel

    @State private var didSucceed = false
    @State private var contentHeight: CGFloat = 0

    /// "to Alex and 5 Others", or just "to Alex" for one.
    private var recipientsLine: String {
        let picked = viewModel.selectedMembers
        guard let first = picked.first else { return "" }
        let firstName = first.name.split(separator: " ").first.map(String.init) ?? first.name
        switch picked.count {
        case 1:  return "to \(firstName)"
        case 2:  return "to \(firstName) and 1 Other"
        default: return "to \(firstName) and \(picked.count - 1) Others"
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: -12) {
                ForEach(viewModel.selectedMembers.prefix(3), id: \.userID) { portrait in
                    GroupSendAvatar(portrait: portrait, size: 48)
                        .overlay(Circle().stroke(Color.backgroundMain, lineWidth: 2))
                }
            }
            Text(recipientsLine)
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
            Text(viewModel.enteredTotal?.formatted() ?? "")
                .font(.appDisplayMedium)
                .foregroundStyle(Color.textMain)
            if let each = viewModel.eachLabel {
                Text(each)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
            }
            SwipeControl(text: "Swipe to Send") {
                switch await viewModel.submit() {
                case .success:
                    didSucceed = true
                case .failed:
                    throw GroupSendDismissed()
                }
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 32)
        .padding(.bottom, 20)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight)] : [.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.backgroundMain)
        // Hold the success checkmark briefly, then dismiss the whole flow back to the chat.
        .task(id: didSucceed) {
            guard didSucceed else { return }
            try? await Task.delay(seconds: 1)
            guard !Task.isCancelled else { return }
            router.dismissSheet()
        }
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
