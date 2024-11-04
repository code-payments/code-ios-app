//
//  ContainerViewModel.swift
//  Code
//
//  Created by Dima Bart on 2024-11-03.
//

import Foundation

@MainActor
class ContainerViewModel: ObservableObject {
    
    @Published var navigationPath: [ContainerPath] = []
    
    private let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    // MARK: - Chat -
    
    func pushChat() {
        navigationPath = [.chat]
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
    case chat
}

extension ContainerViewModel {
    static let mock = ContainerViewModel(sessionAuthenticator: .mock)
}
