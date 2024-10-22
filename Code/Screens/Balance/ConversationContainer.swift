//
//  ConversationContainer.swift
//  Code
//
//  Created by Dima Bart on 2024-09-19.
//

import SwiftUI
import CodeUI
import CodeServices

struct ConversationContainer: View {
    
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var notificationController: NotificationController
    @EnvironmentObject private var betaFlags: BetaFlags
    
    @ObservedObject private var viewModel: DirectMessageViewModel
    
    var displayName: String {
        switch viewModel.friendshipState {
        case .none:
            return "Anonymous"
            
        case .pending(let twitterUser):
            return twitterUser.displayName
            
        case .established(let chat):
            return chat.displayName
        }
    }
    
    var avatarValue: AvatarView.Value {
        switch viewModel.friendshipState {
        case .none:
            return .placeholder
            
        case .pending(let twitterUser):
            return .url(twitterUser.avatarURL)
            
        case .established(let chat):
            if let avatarURL = chat.otherMemberAvatarURL {
                return .url(avatarURL)
            } else {
                return .placeholder
            }
        }
    }
    
    private let chatController: ChatController
    
    init(chatController: ChatController, viewModel: DirectMessageViewModel) {
        self.chatController = chatController
        self.viewModel = viewModel
    }
    
    var body: some View {
        Background(color: .backgroundMain) {
            switch viewModel.friendshipState {
            case .none, .pending:
                VStack {
                    Spacer()
                    
                    if case .pending(let user) = viewModel.friendshipState {
                        CodeButton(style: .filledThin, title: "Send \(user.costOfFriendship.formatted(showOfKin: false)) to Start Chatting") {
                            viewModel.establishFriendshipAction()
                        }
                    }
                }
                .padding(20)
                
            case .established(let chat):
                ConversationScreen(chat: chat, chatController: chatController)
            }
            
            paymentModal()
        }
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .principal) {
                title()
            }
        }
    }
    
    @ViewBuilder private func title() -> some View {
        HStack(spacing: 10) {
            AvatarView(value: avatarValue, diameter: 30)
            
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
    
    @ViewBuilder private func paymentModal() -> some View {
        if viewModel.isShowingPayForFriendship, case .pending(let twitterUser) = viewModel.friendshipState {
            ModalTipConfirmation(
                username: twitterUser.username,
                amount: twitterUser.costOfFriendship.formatted(showOfKin: true),
                currency: twitterUser.costOfFriendship.currency,
                avatar: .url(twitterUser.avatarURL),
                user: twitterUser,
                primaryAction: Localized.Action.swipeToSend,
                secondaryAction: Localized.Action.cancel,
                paymentAction: {
                    try await viewModel.completePaymentForFriendship(with: twitterUser)
                    
                }, dismissAction: {
                    viewModel.cancelEstablishFrienship()
                    
                }, cancelAction: {
                    viewModel.cancelEstablishFrienship()
                }
            )
            .zIndex(5)
        }
    }
}

extension ConversationContainer {
    enum State {
        case unpaid(TwitterUser)
        case paid(ChatLegacy, ChatController)
    }
}
