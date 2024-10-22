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
    
    @Published var friendshipState: FriendshipState = .none
    
    @Published var navigationPath: [DirectMessagePath] = []
    
    @Published var beginChatState: ButtonState = .normal
    
    @Published var enteredUsername: String = ""
    
    @Published private(set) var isShowingPayForFriendship: Bool = false
    
    private let session: Session
    private let exchange: Exchange
    private let chatController: ChatController
    private let bannerController: BannerController
    private let twitterController: TwitterUserController
    
    // MARK: - Init -
    
    init(session: Session, exchange: Exchange, chatController: ChatController, bannerController: BannerController) {
        self.session = session
        self.exchange = exchange
        self.chatController = chatController
        self.bannerController = bannerController
        self.twitterController = session.twitterUserController
    }
    
    // MARK: - Actions -
    
    func fetchAllChats() {
        chatController.fetchChats()
    }
    
    func startNewChat() {
        navigationPath = [.enterUsername]
    }
    
    func selectChat(_ chat: ChatLegacy) {
        friendshipState = .established(chat)
        navigationPath.append(.chat)
    }
    
    func attemptChatWithEnteredUsername() {
        let username = enteredUsername
        Task {
            beginChatState = .loading
            do {
                let user = try await twitterController.fetchUser(username: username)
                try await Task.delay(milliseconds: 500)
                beginChatState = .success
                try await Task.delay(milliseconds: 500)
                
                if user.isFriend {
                    // 1. Look up chat from local list
                    // 2. If not found, `startChat` and add to the local list
                    // 3. Navigation to the chat
                } else {
                    friendshipState = .pending(user)
                    navigationPath.append(.chat)
                }
                
                try await Task.delay(milliseconds: 500)
                beginChatState  = .normal
                enteredUsername = ""
                
            } catch {
                showNotFoundError()
                beginChatState  = .normal
            }
        }
    }
    
    // MARK: - Friendships -
    
    func establishFriendshipAction() {
        isShowingPayForFriendship = true
    }
    
    func cancelEstablishFrienship() {
        isShowingPayForFriendship = false
    }
    
    func completePaymentForFriendship(with user: TwitterUser) async throws {
        guard let rate = exchange.rate(for: user.costOfFriendship.currency) else {
            throw Error.exchateRateNotFound
        }
        
        guard let friendChatID = user.friendChatID else {
            throw Error.friendChatIDNotFound
        }
        
        // Convert cost of friendship from a fiat
        // value to Kin using the latest fx rates
        let amount = KinAmount(
            fiat: user.costOfFriendship.amount,
            rate: rate
        )
        
        let destination = user.tipAddress
        
        let chat = try await session.payAndStartChat(
            amount: amount,
            destination: destination,
            chatID: friendChatID
        )
        
        friendshipState = .established(chat)
    }
    
    // MARK: - Validation -
    
    func isEnteredUsernameValid() -> Bool {
        enteredUsername.count >= 4
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

extension DirectMessageViewModel {
    enum FriendshipState {
        case none
        case pending(TwitterUser)
        case established(ChatLegacy)
    }
}

extension DirectMessageViewModel {
    enum Error: Swift.Error {
        case exchateRateNotFound
        case friendChatIDNotFound
    }
}

enum DirectMessagePath: Hashable {
    case enterUsername
    case chat
}

extension DirectMessageViewModel {
    static let mock: DirectMessageViewModel = .init(
        session: .mock,
        exchange: .mock,
        chatController: .mock,
        bannerController: .mock
    )
}
