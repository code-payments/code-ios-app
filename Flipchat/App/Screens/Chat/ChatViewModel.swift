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
    
    @Published var enteredRoomNumber: String = ""
    
    @Published var enteredNewCover: String = ""
    
    // Sheets
    
    @Published var isShowingEnterRoomNumber: Bool = false
    
    @Published var isShowingJoinPayment: Bool = false
    
    @Published var isShowingCreatePayment: Bool = false
    
    @Published var isShowingChangeCover: Bool = false
    
    // Button States
    
    @Published var buttonStatePreviewRoom: ButtonState = .normal
    
    @Published var buttonStateChangeCover: ButtonState = .normal
    
    @Published var buttonStateLeaveChat: ButtonState = .normal
    
    @Published var buttonStateWatchChat: ButtonState = .normal
    
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
            description: "You will need to enter your Access Key to get back into this account",
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
                .standard(title: "Enter Room Number") { [weak self] in
                    Task {
                        try await Task.delay(milliseconds: 300)
                        self?.showEnterRoomNumber()
                    }
                },
                .standard(title: "Create New Room", action: attemptCreateChat),
                .cancel(title: "Cancel"),
            ]
        )
    }
    
    func pushChat(chatID: ChatID) {
        containerViewModel?.pushChat(chatID: chatID)
        Task {
            try await chatController.advanceReadPointerToLatest(for: chatID)
            try await chatController.syncChatAndMembers(for: chatID)
            
        }
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
        
        Task {
            // Check if this chat exists locally, is so, just
            // send the user directly into the conversation.
            // Exclude chats that have been previously joined
            // and left because we have to update server state.
            if let chatID = try await chatController.localChatFor(roomNumber: roomNumber) {
                
                withButtonState(state: \.buttonStatePreviewRoom, delayTask: false) {} success: {
                    self.pushJoinedChat(chatID: chatID)
                } error: { error in
                    ErrorReporting.captureError(error)
                }
                
            } else {
                withButtonState(state: \.buttonStatePreviewRoom, showSuccess: false) { [chatController] in
                    try await chatController.fetchGroupChat(roomNumber: roomNumber)
                    
                } success: { (chat, members, host) in
                    self.joinRoomPath.append(.previewRoom(chat, members, host))
                    
                } error: { error in
                    ErrorReporting.captureError(error)
                    self.showFailedToLoadRoomError()
                }
            }
        }
    }
    
    func showChangeCover() {
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
        
        withButtonState(state: \.buttonStateChangeCover) { [chatController] in
            try await chatController.changeCover(chatID: chatID, newCover: newCover)
            
        } success: { chatID in
            self.dismissChangeCover()
            
        } error: { error in
            ErrorReporting.captureError(error)
            self.showGenericError()
        }
    }
    
    private func attemptCreateChat() {
        if session.hasSufficientFunds(for: session.userFlags.startGroupCost) {
            isShowingCreatePayment = true
        } else {
            showInsufficientFundsError()
        }
    }
    
    func createChat() async throws {
        let userFlags = session.userFlags
        let chatID = try await chatController.startGroupChat(
            amount: userFlags.startGroupCost,
            destination: userFlags.feeDestination
        )
        
        pushChat(chatID: chatID)
    }
    
    func attemptJoinChat(chatID: ChatID, hostID: UserID, amount: Kin) async throws {
        if chatID == hostID {
            try await payAndJoinChat( // Payment skipped for chat hosts / owners
                chatID: chatID,
                hostID: hostID,
                amount: amount
            )
        } else {
            if session.hasSufficientFunds(for: amount) {
                isShowingJoinPayment = true
            } else {
                showInsufficientFundsError()
            }
        }
    }
    
    func payAndJoinChat(chatID: ChatID, hostID: UserID, amount: Kin) async throws {
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
            ErrorReporting.captureError(error)
            self.showGenericError()
            throw error
        }
    }
    
    func watchChat(chatID: ChatID) async throws {
        withButtonState(state: \.buttonStateWatchChat) { [chatController] in
            _ = try await chatController.watchRoom(chatID: chatID)
        } success: {
            self.pushJoinedChat(chatID: chatID)
        } error: { error in
            ErrorReporting.captureError(error)
            self.showGenericError()
        }
    }
    
    func pushJoinedChat(chatID: ChatID) {
        pushChat(chatID: chatID)
        Task {
            try await Task.delay(milliseconds: 400)
            isShowingJoinPayment = false
            isShowingEnterRoomNumber = false
        }
    }
    
    func cancelJoinChatPayment() {
        isShowingJoinPayment = false
    }
    
    private func leaveChat(chatID: ChatID) {
        withButtonState(state: \.buttonStateLeaveChat) { [chatController] in
            try await chatController.leaveChat(chatID: chatID)
        } success: {
            self.popChat()
        } error: { error in
            ErrorReporting.captureError(error)
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
    
    private func showGenericError() {
        banners.show(
            style: .error,
            title: "Something Went Wrong",
            description: "That wasn't supposed to happen. Please try again.",
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
    
    private func showInsufficientFundsError() {
        banners.show(
            style: .error,
            title: "Insufficient Balance",
            description: "You don't have enough Kin to complete this payment.",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
}

// MARK: - Button State -

extension ChatViewModel {
    private func withButtonState<T>(state: ReferenceWritableKeyPath<ChatViewModel, ButtonState>, showSuccess: Bool = true, delayTask: Bool = true, closure: @escaping () async throws -> T, success: @escaping (T) async throws -> Void, error: @escaping (Swift.Error) -> Void) where T: Sendable {
        Task {
            self[keyPath: state] = .loading
            do {
                let result = try await closure()
                if delayTask {
                    try await Task.delay(milliseconds: 250)
                }
                
                if showSuccess {
                    self[keyPath: state] = .success
                    try await Task.delay(milliseconds: 500)
                }
                
                try await success(result)
                
                // Reset
                
                try await Task.delay(milliseconds: 500)
                self[keyPath: state]  = .normal
                
                resetEnteredRoomNumber()
                resetEnteredCover()
                
            } catch let caughtError {
                error(caughtError)
                self[keyPath: state]  = .normal
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
    case previewRoom(Chat.Metadata, [Chat.Member], Chat.Identity)
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
