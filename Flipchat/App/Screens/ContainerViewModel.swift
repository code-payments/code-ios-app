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
    
    @Published var navigationPath: [ContainerPath] = []
    
    private let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    // MARK: - Chat -
    
    func pushChat(chatID: ChatID) {
        navigationPath = [.chat(chatID)]
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
}

extension ContainerViewModel {
    static let mock = ContainerViewModel(sessionAuthenticator: .mock)
}
