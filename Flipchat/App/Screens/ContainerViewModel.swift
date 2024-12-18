//
//  ContainerViewModel.swift
//  Code
//
//  Created by Dima Bart on 2024-11-03.
//

import Foundation
import FlipchatServices

@MainActor
class ContainerViewModel: ObservableObject {
    
    @Published var navigationPath: [ContainerPath] = [] {
        didSet {
            PushController.activeRoomIDs = activeRoomIDs
        }
    }
    
    private let sessionAuthenticator: SessionAuthenticator
    
    private var activeRoomIDs: Set<ChatID> {
        let ids = navigationPath.compactMap {
            switch $0 {
            case .chat(let id):
                return id
            case .details:
                return nil
            }
        }
        
        return Set(ids)
    }
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    // MARK: - Chat -
    
    func pushChat(chatID: ChatID) {
        navigationPath.append(.chat(chatID))
    }
    
    func pushDetails(chatID: ChatID) {
        navigationPath.append(.details(chatID))
    }
    
    func popChat() {
        navigationPath = []
    }
    
    // MARK: - Logout -
    
    func logout() {
        sessionAuthenticator.logout()
    }
}

enum ContainerPath: Hashable {
    case chat(ChatID)
    case details(ChatID)
}

extension ContainerViewModel {
    static let mock = ContainerViewModel(sessionAuthenticator: .mock)
}
