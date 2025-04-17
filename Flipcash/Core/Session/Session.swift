//
//  Session.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import Foundation
import FlipcashUI
import FlipcashCore

@MainActor
protocol SessionDelegate: AnyObject {
    func didDetectUnlockedAccount()
}

@MainActor
class Session: ObservableObject {

    let owner: AccountCluster
    let userID: UserID
    
    private let container: Container
    
    // MARK: - Init -
    
    init(container: Container, owner: AccountCluster, userID: UserID) {
        self.container = container
        self.owner     = owner
        self.userID    = userID
    }
    
    func prepareForLogout() {
        
    }
}
