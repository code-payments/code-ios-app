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
    
    @Published var joinRoomPath: [JoinRoomPath] = []
    
    @Published var beginChatState: ButtonState = .normal
    
    @Published var enteredRoomNumber: String = ""
    
    @Published var isShowingEnterRoomNumber: Bool = false
    
    @Published private(set) var isShowingPayForFriendship: Bool = false
    
    private let chatController: ChatController
    private let client: FlipchatClient
    private let exchange: Exchange
    private let banners: Banners
    
    private weak var containerViewModel: ContainerViewModel?
    
    // MARK: - Init -
    
    init(chatController: ChatController, client: FlipchatClient, exchange: Exchange, banners: Banners, containerViewModel: ContainerViewModel) {
        self.chatController = chatController
        self.client = client
        self.exchange = exchange
        self.banners = banners
        self.containerViewModel = containerViewModel
    }
    
    // MARK: - Actions -
    
    func logout() {
        banners.show(
            style: .error,
            title: "Log out?",
            description: "Are you sure you want to logout?",
            position: .bottom,
            actions: [
                .destructive(title: "Log Out") { [weak self] in
                    self?.containerViewModel?.logout()
                },
                .cancel(title: "Cancel"),
            ]
        )
    }
    
    func startChatting() {
        banners.show(
            style: .notification,
            title: nil,
            description: nil,
            position: .bottom,
            actions: [
                .standard(title: "Join a Room", action: joinExistingChat),
                .standard(title: "Create a New Room", action: startNewChat),
                .cancel(title: "Cancel"),
            ]
        )
    }
    
    func joinExistingChat() {
        isShowingEnterRoomNumber = true
        joinRoomPath = []
        
        resetEnteredRoomNumber()
    }
    
    func startNewChat() {
        Task {
            let chatID = try await chatController.startGroupChat()
            containerViewModel?.pushChat(chatID: chatID)
        }
    }
    
    func selectChat(chat: pChat) {
        containerViewModel?.pushChat(chatID: ID(data: chat.serverID))
    }
    
    private func resetEnteredRoomNumber() {
        enteredRoomNumber = ""
    }
    
    // MARK: - Chat -
    
    func previewChat() {
        guard let roomNumber = RoomNumber(enteredRoomNumber) else {
            // TODO: Use number parser instead
            return
        }
        
        withButtonState { [chatController] in
            try await chatController.fetchGroupChat(
                roomNumber: roomNumber,
                hide: true // This is a preview, we don't want to add it to the list yet
            )
            
        } success: { chatID in
            self.joinRoomPath.append(.previewRoom(chatID))
            
        } error: { _ in
            self.showFailedToLoadRoomError()
        }
    }
    
    func attemptEnterGroupChat(chatID: ChatID, hostID: UserID) {
        withButtonState { [chatController] in
            try await chatController.joinGroupChat(chatID: chatID, hostID: hostID)
            
        } success: { chatID in
            self.isShowingEnterRoomNumber = false
            try await Task.delay(milliseconds: 100)
            self.containerViewModel?.pushChat(chatID: chatID)
            
        } error: { _ in
            self.showNotFoundError()
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
    
    private func showFailedToLoadRoomError() {
        banners.show(
            style: .error,
            title: "Failed to Load Room",
            description: "An error occured while retrieving room metadata.",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showNotFoundError() {
        banners.show(
            style: .error,
            title: "Room Not Found",
            description: "This room doesn't appear to exist.",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
}

// MARK: - Button State -

extension ChatViewModel {
    private func withButtonState<T>(closure: @escaping () async throws -> T, success: @escaping (T) async throws -> Void, error: @escaping (Swift.Error) -> Void) where T: Sendable {
        Task {
            beginChatState = .loading
            do {
                let result = try await closure()
                
                try await Task.delay(milliseconds: 500)
                beginChatState = .success
                try await Task.delay(milliseconds: 500)
                
                try await success(result)
                
                // Reset
                
                try await Task.delay(milliseconds: 100)
                beginChatState  = .normal
                resetEnteredRoomNumber()
                
            } catch let caughtError {
                error(caughtError)
                beginChatState  = .normal
            }
        }
    }
}

extension ChatViewModel {
    enum Error: Swift.Error {
        case exchateRateNotFound
        case friendChatIDNotFound
    }
}

enum JoinRoomPath: Hashable {
    case previewRoom(ChatID)
}

extension ChatViewModel {
    static let mock: ChatViewModel = .init(
        chatController: .mock,
        client: .mock,
        exchange: .mock,
        banners: .mock,
        containerViewModel: .mock
    )
}
