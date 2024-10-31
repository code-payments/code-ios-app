//
//  ChatViewModel.swift
//  Code
//
//  Created by Dima Bart on 2024-09-11.
//

import SwiftUI
import CodeUI
import FlipchatServices

@MainActor
class ChatViewModel: ObservableObject {
    
    @Published var friendshipState: FriendshipState = .none
    
    @Published var navigationPath: [DirectMessagePath] = []
    
    @Published var beginChatState: ButtonState = .normal
    
    @Published var enteredRoomNumber: String = ""
    
    @Published private(set) var isShowingPayForFriendship: Bool = false
    
    private let session: Session
    private let sessionAuthenticator: SessionAuthenticator
    private let client: FlipchatClient
    private let exchange: Exchange
    private let chatController: ChatController
    private let banners: Banners
    
    // MARK: - Init -
    
    init(session: Session, sessionAuthenticator: SessionAuthenticator, client: FlipchatClient, exchange: Exchange, banners: Banners) {
        self.session = session
        self.sessionAuthenticator = sessionAuthenticator
        self.client = client
        self.exchange = exchange
        self.chatController = session.chatController
        self.banners = banners
    }
    
    // MARK: - Actions -
    
    func logout() {
        sessionAuthenticator.logout()
    }
    
    func startNewChat() {
        Task {
            let chat = try await chatController.startGroupChat()
            friendshipState = .contributor(chat)
            navigationPath.append(.chat)
        }
    }
    
    func joinExistingChat() {
        navigationPath = [.enterRoomNumber]
    }
    
    func selectChat(_ chat: Chat) {
        friendshipState = .contributor(chat)
        navigationPath.append(.chat)
    }
    
    func attemptEnterGroupChat() {
        guard let roomNumber = RoomNumber(enteredRoomNumber) else {
            // TODO: Use number parser instead
            return
        }
        
        Task {
            beginChatState = .loading
            do {
                let chat = try await chatController.joinGroupChat(roomNumber: roomNumber)
                
                try await Task.delay(milliseconds: 500)
                beginChatState = .success
                try await Task.delay(milliseconds: 500)
                
                friendshipState = .contributor(chat) // TODO: Should be .reader()
                navigationPath.append(.chat)
                
                // Reset
                
                try await Task.delay(milliseconds: 500)
                beginChatState  = .normal
                enteredRoomNumber = ""
                
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
    
//    func completePaymentForFriendship(with user: TwitterUser) async throws {
//        guard let rate = exchange.rate(for: user.costOfFriendship.currency) else {
//            throw Error.exchateRateNotFound
//        }
//        
//        guard let friendChatID = user.friendChatID else {
//            throw Error.friendChatIDNotFound
//        }
//        
//        // Convert cost of friendship from a fiat
//        // value to Kin using the latest fx rates
//        let amount = KinAmount(
//            fiat: user.costOfFriendship.amount,
//            rate: rate
//        )
//        
//        let destination = user.tipAddress
//        
//        let chat = try await session.payAndStartChat(
//            amount: amount,
//            destination: destination,
//            chatID: friendChatID
//        )
//        
//        friendshipState = .established(chat)
//    }
    
    // MARK: - Validation -
    
    func isEnteredRoomNumberValid() -> Bool {
        enteredRoomNumber.count >= 1
    }
    
    // MARK: - Errors -
    
    private func showNotFoundError() {
        banners.show(
            style: .error,
            title: "Username Not Found",
            description: "This X username isn't on Code yet. Please try a different username.",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
}

extension ChatViewModel {
    enum FriendshipState {
        case none
        case reader(Chat)
        case contributor(Chat)
    }
}

extension ChatViewModel {
    enum Error: Swift.Error {
        case exchateRateNotFound
        case friendChatIDNotFound
    }
}

enum DirectMessagePath: Hashable {
    case enterRoomNumber
    case chat
}

extension ChatViewModel {
    static let mock: ChatViewModel = .init(
        session: .mock,
        sessionAuthenticator: .mock,
        client: .mock,
        exchange: .mock,
        banners: .mock
    )
}
