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
    private let client: FlipchatClient
    private let exchange: Exchange
    private let chatController: ChatController
    private let bannerController: BannerController
    
    // MARK: - Init -
    
    init(session: Session, client: FlipchatClient, exchange: Exchange, bannerController: BannerController) {
        self.session = session
        self.client = client
        self.exchange = exchange
        self.chatController = session.chatController
        self.bannerController = bannerController
    }
    
    // MARK: - Actions -
    
    func fetchAllChats() {
        chatController.fetchChats()
    }
    
    func startNewChat() {
        navigationPath = [.enterUsername]
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
                let chat = try await client.fetchChat(
                    for: roomNumber,
                    owner: session.organizer.ownerKeyPair
                )
                
                try await Task.delay(milliseconds: 500)
                beginChatState = .success
                try await Task.delay(milliseconds: 500)
                
                friendshipState = .reader(chat)
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
    
    func isEnteredUsernameValid() -> Bool {
        enteredRoomNumber.count >= 4
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
    case enterUsername
    case chat
}

extension ChatViewModel {
    static let mock: ChatViewModel = .init(
        session: .mock,
        client: .mock,
        exchange: .mock,
        bannerController: .mock
    )
}
