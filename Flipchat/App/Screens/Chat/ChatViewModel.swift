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
    
    @Published var enteredRoomName: String = ""
    
    @Published var enteredRoomNumber: String = ""
    
    @Published var enteredNewCover: String = ""
    
    // Sheets
    
    @Published var isShowingEnterRoomNumber: Bool = false
    
    @Published var isShowingJoinPayment: RoomDescription? = nil
    
    @Published var isShowingCreatePayment: Bool = false
    
    @Published var isShowingCreateAccountFromChats: Bool = false

    @Published var isShowingCreateAccountFromConversation: Bool = false
    
    @Published var isShowingFindRoomModal: Bool = false
    
    @Published var isShowingCustomize: Bool = false
    
    @Published var isShowingChangeCover: Bool = false
    
    @Published var isShowingChangeRoomName: Bool = false
    
    @Published var isShowingPreviewRoom: RoomPreview?
    
    // Button States
    
    @Published var buttonStateEnterRoomName: ButtonState = .normal
    
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
        isShowingFindRoomModal = true
    }
    
    func restoreTo(chatID: ChatID) {
        Task {
            // 1. Pop any existing conversations
            if containerViewModel?.navigationPath.isEmpty == false {
                containerViewModel?.popToRoot()
            }
            
            // 2. Ensure we have the latest room state and messages are up-to-date
            _ = try await chatController.syncChatAndMessages(for: chatID)
            
            // 3. Present the conversation with this ID
            containerViewModel?.pushChat(chatID: chatID)
        }
    }
    
    func pushChat(chatID: ChatID) {
        containerViewModel?.pushChat(chatID: chatID)
    }
    
    func popToRoot() {
        containerViewModel?.popToRoot()
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
    
    // MARK: - Preview Chat -
    
    func previewChat() {
        guard let roomNumber = RoomNumber(enteredRoomNumber) else {
            // TODO: Use number parser instead
            return
        }
        
        previewChat(
            roomNumber: roomNumber,
            showSuccess: true,
            showModally: false
        )
    }
    
    func previewChat(roomNumber: RoomNumber, showSuccess: Bool, showModally: Bool) {
        Task {
            // Check if this chat exists locally, is so, just
            // send the user directly into the conversation.
            // Exclude chats that have been previously joined
            // and left because we have to update server state.
            if let chatID = try await chatController.localChatFor(roomNumber: roomNumber) {
                
                // showSuccess == false, in this case just removes the delay for success
                withButtonState(state: \.buttonStatePreviewRoom, showSuccess: showSuccess, delayTask: false) {} success: {
                    self.pushJoinedChat(chatID: chatID)
                } error: { error in
                    ErrorReporting.captureError(error)
                }
                
            } else {
                withButtonState(state: \.buttonStatePreviewRoom, showSuccess: false) { [chatController] in
                    try await chatController.fetchGroupChat(roomNumber: roomNumber)
                    
                } success: { (chat, members, host) in
                    if showModally {
                        self.isShowingPreviewRoom = RoomPreview(
                            chat: chat,
                            members: members,
                            host: host
                        )
                    } else {
                        self.joinRoomPath.append(.previewRoom(chat, members, host))
                    }
                    
                } error: { error in
                    ErrorReporting.captureError(error)
                    self.showFailedToLoadRoomError()
                }
            }
        }
    }
    
    func dismissPreviewChatModal() {
        isShowingPreviewRoom = nil
    }
    
    // MARK: - Customize Chat -
    
    func showCustomizeRoomModal() {
        isShowingCustomize = true
    }
    
    func showChangeCover() {
        dismissCustomize()
        isShowingChangeCover = true
    }
    
    func showChangeRoomName(existingName: String?) {
        dismissCustomize()
        enteredRoomName = existingName ?? ""
        isShowingChangeRoomName = true
    }
    
    func dismissCustomize() {
        isShowingCustomize = false
    }
    
    func dismissChangeCover() {
        isShowingChangeCover = false
        Task {
            try await Task.delay(milliseconds: 500)
            enteredNewCover = ""
        }
    }
    
    func dismissChangeRoomName() {
        isShowingChangeRoomName = false
        Task {
            try await Task.delay(milliseconds: 500)
            enteredRoomName = ""
        }
    }
    
    func changeRoomName(chatID: ChatID) {
        let newName = enteredRoomName
        
        withButtonState(state: \.buttonStateEnterRoomName) { [chatController] in
            try await chatController.changeRoomName(chatID: chatID, newName: newName)
        } success: { chatID in
            self.dismissChangeRoomName()
            
        } error: { error in
            ErrorReporting.captureError(error)
            self.showGenericError()
        }
    }
    
    func changeCover(chatID: ChatID) {
        guard
            let coverInt = Int(enteredNewCover),
            let newCover = Kin(kin: coverInt)
        else {
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
    
    // MARK: - Create Chat -
    
    func attemptCreateChat() {
        guard chatController.isRegistered else {
            isShowingCreateAccountFromChats = true
            return
        }
        
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
    
    // MARK: - Join Chat -
    
    func attemptJoinChat(chatID: ChatID, hostID: UserID, amount: Kin) async throws {
        guard chatController.isRegistered else {
            isShowingCreateAccountFromConversation = true
            return
        }
        
        if chatID == hostID {
            try await payAndJoinChat( // Payment skipped for chat hosts / owners
                chatID: chatID,
                hostID: hostID,
                amount: amount
            )
        } else {
            if session.hasSufficientFunds(for: amount), let description = try? chatController.getRoom(chatID: chatID) {
                isShowingJoinPayment = description
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
            cancelJoinChatPayment()
            isShowingEnterRoomNumber = false
            isShowingPreviewRoom = nil
        }
    }
    
    func cancelJoinChatPayment() {
        isShowingJoinPayment = nil
    }
    
    private func leaveChat(chatID: ChatID) {
        withButtonState(state: \.buttonStateLeaveChat) { [chatController] in
            try await chatController.leaveChat(chatID: chatID)
        } success: {
            self.popToRoot()
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
    
    func isEnteredRoomNameValid() -> Bool {
        enteredRoomName.count >= 1 && enteredRoomName.count <= 64
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

struct RoomPreview: Hashable, Identifiable {
    
    let chat: Chat.Metadata
    let members: [Chat.Member]
    let host: Chat.Identity
    
    var id: ChatID {
        chat.id
    }
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
