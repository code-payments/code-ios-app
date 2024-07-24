//
//  ChatViewModel.swift
//  Code
//
//  Created by Dima Bart on 2024-07-15.
//

import SwiftUI
import CodeUI
import CodeServices

@MainActor
class ChatViewModel: ObservableObject {
    
    @Published var navigationPath: [Chat] = []
    
    var twitterUser: TwitterUser? {
        tipController.twitterUser
    }
    
    private let chatController: ChatController
    private let tipController: TipController
    
    // MARK: - Init -
    
    init(chatController: ChatController, tipController: TipController) {
        self.chatController = chatController
        self.tipController = tipController
    }
    
    // MARK: - Identity -
    
    func revealSelfIdentity(chat: Chat) {
        guard let username = twitterUser?.username else {
            return
        }
        
        Task {
            try await chatController.revealSelfIdentity(chat: chat, username: username)
            
            // TODO: Should update from stream instead
            chatController.fetchChats()
        }
    }
}

extension ChatViewModel: MessageListDelegate {
    func didInteract(chat: Chat, message: Chat.Message, reference: Chat.Reference) {
        guard case .intent(let intentID) = reference else {
            return
        }
        
        Task {
            // Check if this is a valid intentID
            let chat = try await chatController.startChat(for: intentID)
            navigationPath.append(chat)
            
            chatController.fetchChats()
        }
    }
}
