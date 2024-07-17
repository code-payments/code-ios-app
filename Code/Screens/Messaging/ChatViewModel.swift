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
    
    private let chatController: ChatController
    
    // MARK: - Init -
    
    init(chatController: ChatController) {
        self.chatController = chatController
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
