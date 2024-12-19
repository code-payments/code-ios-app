//
//  Untitled.swift
//  Code
//
//  Created by Dima Bart on 2024-11-03.
//

import SwiftUI
import CodeUI

struct BalanceScreen: View {
    
    @EnvironmentObject var banners: Banners
    
    @ObservedObject private var session: Session
    
    private let container: AppContainer
    private let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init(session: Session, container: AppContainer) {
        self.session = session
        self.container = container
        self.sessionAuthenticator = container.sessionAuthenticator
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                NavBar(title: "Balance")
                
                FiatField(
                    size: .extraLarge,
                    amount: .init(
                        kin: session.currentBalance,
                        rate: .oneToOne
                    )
                )
                .padding(.top, 40)
                .foregroundStyle(Color.textMain)
                
                Spacer()
                
                CodeButton(
                    style: .subtle,
                    title: "Delete My Account"
                ) {
                    banners.show(
                        style: .error,
                        title: "Permanently Delete Account?",
                        description: "This will permanently delete your Flipchat account",
                        position: .bottom,
                        actions: [
                            .destructive(title: "Permanently Delete My Account") {
                                sessionAuthenticator.logout()
                            },
                            .cancel(title: "Cancel") {},
                        ]
                    )
                }
                .padding(.bottom, 40)
            }
        }
    }
}
