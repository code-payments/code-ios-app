//
//  DeleteAccountViewModel.swift
//  Code
//
//  Created by Dima Bart on 2022-10-04.
//

import UIKit
import CodeServices
import CodeUI

@MainActor
class DeleteAccountViewModel: ObservableObject {
    
    @Published var showingDeleteConfirmation: Bool = false
    
    @Published var confirmationText: String = ""
    
    var canDeleteAccount: Bool {
        confirmationText == Localized.Subtitle.delete
    }
    
    private let sessionAuthenticator: SessionAuthenticator
    private let bannerController: BannerController
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator, bannerController: BannerController) {
        self.sessionAuthenticator = sessionAuthenticator
        self.bannerController = bannerController
    }
    
    // MARK: - Navigation -
    
    func continueToAccountDeletion() {
        showingDeleteConfirmation = true
    }
    
    // MARK: - Actions -
    
    func deleteAccount() {
        bannerController.show(
            style: .error,
            title: Localized.Prompt.Title.deleteAccount,
            description: nil,
            position: .bottom,
            actionStyle: .stacked,
            actions: [
                .destructive(title: Localized.Action.deleteAccount) {
                    self.finalizeAccountDeletion()
                },
                .cancel(title: Localized.Action.cancel),
            ]
        )
    }
    
    private func finalizeAccountDeletion() {
        sessionAuthenticator.deleteAndLogout()
    }
}
