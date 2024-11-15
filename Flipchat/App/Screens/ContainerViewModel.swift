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
            updateTabBarVisibility()
        }
    }
    
    @Published var isTabBarVisible: Bool = true
    
    private let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    // MARK: - Chat -
    
    func pushChat(chatID: ChatID) {
        isTabBarVisible = false
        Task {
            try await Task.delay(milliseconds: 50)
            navigationPath = [.chat(chatID)]
        }
    }
    
    func pushDetails(chatID: ChatID) {
        navigationPath.append(.details(chatID))
    }
    
    func popChat() {
        navigationPath = []
    }
    
    private func updateTabBarVisibility() {
        self.isTabBarVisible = navigationPath.count == 0
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
