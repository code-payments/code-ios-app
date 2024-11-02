//
//  ConversationContainer.swift
//  Code
//
//  Created by Dima Bart on 2024-09-19.
//

import SwiftUI
import CodeUI

struct ConversationContainer: View {
    
    @ObservedObject private var viewModel: ChatViewModel
    
    var displayName: String {
        switch viewModel.friendshipState {
        case .none:
            return "Anonymous"
            
        case .reader(let chat), .contributor(let chat):
            return chat.displayName
        }
    }
    
    private let chatController: ChatController
    
    // MARK: - Init -
    
    init(chatController: ChatController, viewModel: ChatViewModel) {
        self.chatController = chatController
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            switch viewModel.friendshipState {
            case .none, .reader:
                VStack {
                    Spacer()
                    
                    if case .reader = viewModel.friendshipState {
                        CodeButton(style: .filledThin, title: "Send $ to Start Chatting") {
                            viewModel.establishFriendshipAction()
                        }
                    }
                }
                .padding(20)
                
            case .contributor(let chat):
                ConversationScreen(chat: chat, chatController: chatController)
            }
            
            paymentModal()
        }
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                title()
            }
        }
    }
    
    @ViewBuilder private func title() -> some View {
        HStack(spacing: 10) {
            avatarView()
            
            VStack(alignment: .leading, spacing: 0) {
                Text(displayName)
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                Text("Last seen recently")
                    .font(.appTextHeading)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder private func avatarView() -> some View {
        switch viewModel.friendshipState {
        case .none:
            AvatarView(value: .placeholder, diameter: 30)
            
        case .reader(let chat), .contributor(let chat):
            GradientAvatarView(data: chat.id.data, diameter: 30)
        }
    }
    
    @ViewBuilder private func paymentModal() -> some View {
        if viewModel.isShowingPayForFriendship, case .reader(let chat) = viewModel.friendshipState {
            ModalPaymentConfirmation(
                amount: "$1.00",
                currency: .usd,
                primaryAction: "Swipe to Pay",
                secondaryAction: "Cancel") {
                    
                } dismissAction: {
                    
                } cancelAction: {
                    
                }
                .zIndex(5)
        }
    }
}
