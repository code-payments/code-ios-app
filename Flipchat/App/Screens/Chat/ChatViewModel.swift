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
    
    @Published var buttonState: ButtonState = .normal
    
    @Published var enteredRoomNumber: String = ""
    
    @Published var isShowingEnterRoomNumber: Bool = false
    
    @Published var isShowingJoinPayment: Bool = false
    
    @Published var isShowingCreatePayment: Bool = false
    
    private let session: Session
    private let chatController: ChatController
    private let client: FlipchatClient
    private let exchange: Exchange
    private let banners: Banners
    
    private weak var containerViewModel: ContainerViewModel?
    
    // MARK: - Init -
    
    init(session: Session, chatController: ChatController, client: FlipchatClient, exchange: Exchange, banners: Banners, containerViewModel: ContainerViewModel) {
        self.session = session
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
                .standard(title: "Join a Room", action: showEnterRoomNumber),
                .standard(title: "Create a New Room", action: attemptCreateChat),
                .cancel(title: "Cancel"),
            ]
        )
    }
    
    func selectChat(chat: pChat) {
        containerViewModel?.pushChat(chatID: ID(data: chat.serverID))
    }
    
    func popChat() {
        containerViewModel?.popChat()
    }
    
    func attemptLeaveChat(chatID: ChatID, roomNumber: RoomNumber) {
        banners.show(
            style: .error,
            title: "Leave Room \(roomNumber.roomString)?",
            description: "Are you sure you want to leave? You'll need to pay the cover charge to get back in.",
            position: .bottom,
            isDismissable: true,
            actions: [
                .destructive(title: "Leave Room \(roomNumber.roomString)") {
                    self.leaveChat(chatID: chatID)
                },
                .cancel(title: "Cancel"),
            ]
        )
    }
    
    func showEnterRoomNumber() {
        isShowingEnterRoomNumber = true
        joinRoomPath = []
        
        resetEnteredRoomNumber()
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
    
    private func attemptCreateChat() {
        isShowingCreatePayment = true
    }
    
    func createChat() async throws {
        guard let _ = session.userFlags else {
            throw Error.missingUserFlags
        }
        
        let chatID = try await chatController.startGroupChat(amount: session.startGroupCost)
        containerViewModel?.pushChat(chatID: chatID)
    }
    
    func attemptJoinChat(chatID: ChatID, hostID: UserID, amount: Kin) {
        if chatID == hostID {
            joinChat(
                chatID: chatID,
                hostID: hostID,
                amount: amount
            )
        } else {
            isShowingJoinPayment = true
        }
    }
    
    func joinChat(chatID: ChatID, hostID: UserID, amount: Kin) {
        withButtonState { [chatController] in
            try await chatController.joinGroupChat(
                chatID: chatID,
                hostID: hostID,
                amount: amount
            )
            
        } success: { chatID in
            self.isShowingEnterRoomNumber = false
            try await Task.delay(milliseconds: 100)
            self.containerViewModel?.pushChat(chatID: chatID)
            
        } error: { _ in
            self.showNotFoundError()
        }
    }
    
    private func leaveChat(chatID: ChatID) {
        withButtonState { [chatController] in
            try await chatController.leaveChat(chatID: chatID)
        } success: {
            self.popChat()
        } error: { _ in
            self.showFailedToLeaveChatError()
        }
    }
    
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
    
    private func showFailedToLeaveChatError() {
        banners.show(
            style: .error,
            title: "Failed to Leave Chat",
            description: "Something wen't wrong. Please try again.",
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
            buttonState = .loading
            do {
                let result = try await closure()
                
                try await Task.delay(milliseconds: 500)
                buttonState = .success
                try await Task.delay(milliseconds: 500)
                
                try await success(result)
                
                // Reset
                
                try await Task.delay(milliseconds: 100)
                buttonState  = .normal
                resetEnteredRoomNumber()
                
            } catch let caughtError {
                error(caughtError)
                buttonState  = .normal
            }
        }
    }
}

extension ChatViewModel {
    enum Error: Swift.Error {
        case missingUserFlags
        case exchateRateNotFound
        case friendChatIDNotFound
    }
}

enum JoinRoomPath: Hashable {
    case previewRoom(ChatID)
}

extension ChatViewModel {
    static let mock: ChatViewModel = .init(
        session: .mock,
        chatController: .mock,
        client: .mock,
        exchange: .mock,
        banners: .mock,
        containerViewModel: .mock
    )
}
