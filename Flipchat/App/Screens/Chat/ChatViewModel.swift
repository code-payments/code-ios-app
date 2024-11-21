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
    
    @Published var enteredNewCover: String = ""
    
    @Published var isShowingEnterRoomNumber: Bool = false
    
    @Published var isShowingJoinPayment: Bool = false
    
    @Published var isShowingCreatePayment: Bool = false
    
    @Published var isShowingChangeCover: Bool = false
    
    var userID: UserID {
        session.userID
    }
    
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
            description: "Are you sure you want to log out?",
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
                .standard(title: "Enter a Room Number") {
                    Task {
                        try await Task.delay(milliseconds: 300)
                        self.showEnterRoomNumber()
                    }
                },
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
            title: "Leave Room?",
            description: "We won't tell people you left",
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
    
    private func resetEnteredCover() {
        enteredNewCover = ""
    }
    
    // MARK: - Chat -
    
    func previewChat() {
        guard let roomNumber = RoomNumber(enteredRoomNumber) else {
            // TODO: Use number parser instead
            return
        }
        
        // Check if this chat exists locally, is so, just
        // send the user directly into the conversation
        if let chatID = try? chatController.chatFor(roomNumber: roomNumber) {
            
            withButtonState(delayTask: false) {} success: {
                self.completeJoiningChat(chatID: chatID)
            } error: { _ in }
            
        } else {
            withButtonState(showSuccess: false) { [chatController] in
                try await chatController.fetchGroupChat(roomNumber: roomNumber)
                
            } success: { (chat, members) in
                self.joinRoomPath.append(.previewRoom(chat, members))
                
            } error: { _ in
                self.showFailedToLoadRoomError()
            }
        }
    }
    
    func showChangeCover(currentCover: Kin) {
        enteredNewCover = String(currentCover.truncatedKinValue)
        isShowingChangeCover = true
    }
    
    func dismissChangeCover() {
        isShowingChangeCover = false
        Task {
            try await Task.delay(milliseconds: 500)
            enteredNewCover = ""
        }
    }
    
    func changeCover(chatID: ChatID) {
        guard
            let coverInt = Int(enteredNewCover),
            let newCover = Kin(kin: coverInt)
        else {
            // TODO: Use number parser instead
            return
        }
        
        withButtonState { [chatController] in
            try await chatController.changeCover(chatID: chatID, newCover: newCover)
            
        } success: { chatID in
            self.dismissChangeCover()
            
        } error: { _ in
            self.showFailedToLoadRoomError()
        }
    }
    
    private func attemptCreateChat() {
        isShowingCreatePayment = true
    }
    
    func createChat() async throws {
        guard let userFlags = session.userFlags else {
            throw Error.missingUserFlags
        }
        
        let chatID = try await chatController.startGroupChat(
            amount: userFlags.startGroupCost,
            destination: userFlags.feeDestination
        )
        
        containerViewModel?.pushChat(chatID: chatID)
    }
    
    func attemptJoinChat(chatID: ChatID, hostID: UserID, amount: Kin) async throws {
        if chatID == hostID {
            try await joinChat(
                chatID: chatID,
                hostID: hostID,
                amount: amount
            )
        } else {
            isShowingJoinPayment = true
        }
    }
    
    func joinChat(chatID: ChatID, hostID: UserID, amount: Kin) async throws {
        // We don't want to use withButtonState here because
        // it's not desireble to show loading and success state
        // here. Most of the time is taken up by the payment modal.
        do {
            _ = try await chatController.joinGroupChat(
                chatID: chatID,
                hostID: hostID,
                amount: amount
            )
            
        } catch {
            self.showNotFoundError()
            throw error
        }
    }
    
    func completeJoiningChat(chatID: ChatID) {
        containerViewModel?.pushChat(chatID: chatID)
        Task {
            try await Task.delay(milliseconds: 400)
            isShowingJoinPayment = false
            isShowingEnterRoomNumber = false
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
    
    func isEnteredCoverChargeValid() -> Bool {
        guard let coverInt = UInt64(enteredNewCover) else {
            return false
        }
        
        let cover = Kin(kin: coverInt)
        return cover > 0 && cover < 1_000_000_000
    }
    
    // MARK: - Errors -
    
    private func showFailedToLoadRoomError() {
        banners.show(
            style: .error,
            title: "Room Doesn't Exist Yet",
            description: "Please try a different room number.",
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
    
    private func showFailedToChangeCover() {
        banners.show(
            style: .error,
            title: "Failed to Change Cover",
            description: "Something wen't wrong. Please try again.",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
}

// MARK: - Button State -

extension ChatViewModel {
    private func withButtonState<T>(showSuccess: Bool = true, delayTask: Bool = true, closure: @escaping () async throws -> T, success: @escaping (T) async throws -> Void, error: @escaping (Swift.Error) -> Void) where T: Sendable {
        Task {
            buttonState = .loading
            do {
                let result = try await closure()
                if delayTask {
                    try await Task.delay(milliseconds: 250)
                }
                
                if showSuccess {
                    buttonState = .success
                    try await Task.delay(milliseconds: 500)
                }
                
                try await success(result)
                
                // Reset
                
                try await Task.delay(milliseconds: 300)
                buttonState  = .normal
                
                try await Task.delay(milliseconds: 100)
                
                resetEnteredRoomNumber()
                resetEnteredCover()
                
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
    case previewRoom(Chat.Metadata, [Chat.Member])
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
