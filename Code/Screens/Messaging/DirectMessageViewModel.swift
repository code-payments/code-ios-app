//
//  DirectMessageViewModel.swift
//  Code
//
//  Created by Dima Bart on 2024-09-11.
//

import SwiftUI
import CodeUI
import CodeServices

@MainActor
class DirectMessageViewModel: ObservableObject {
    
    @Published var navigationPath: [DirectMessagePath] = []
    
    @Published var beginChatState: ButtonState = .normal
    
    private let chatController: ChatController
    private let twitterController: TwitterUserController
    private let bannerController: BannerController
    
    // MARK: - Init -
    
    init(chatController: ChatController, twitterController: TwitterUserController, bannerController: BannerController) {
        self.chatController = chatController
        self.twitterController = twitterController
        self.bannerController = bannerController
    }
    
    // MARK: - Actions -
    
    func fetchAllChats() {
        chatController.fetchChats()
    }
    
    func startNewChat() {
        navigationPath = [.enterUsername]
    }
    
    func attemptChat(with username: String) {
        Task {
            beginChatState = .loading
            do {
                let (user, avatar) = try await twitterController.fetchCompleteUser(username: username)
                try await Task.delay(milliseconds: 500)
                beginChatState = .success
                try await Task.delay(milliseconds: 500)
                
                if user.isFriend {
//                    chatController.startChat(for: <#T##PublicKey#>)
//                    navigationPath.append(.chatPaid(chat))
                } else {
                    navigationPath.append(.chatUnpaid(user))
                }
                
            } catch {
                showNotFoundError()
            }
        }
    }
    
    // MARK: - Validation -
    
    func isValid(username: String) -> Bool {
        username.count >= 4
    }
    
    // MARK: - Errors -
    
    private func showNotFoundError() {
        bannerController.show(
            style: .error,
            title: "Username Not Found",
            description: "This X username isn't on Code yet. Please try a different username.",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
}

enum DirectMessagePath: Hashable {
    case enterUsername
    case chatUnpaid(TwitterUser)
    case chatPaid(Chat)
}

extension DirectMessageViewModel {
    static let mock: DirectMessageViewModel = .init(
        chatController: .mock,
        twitterController: .mock,
        bannerController: .mock
    )
}
