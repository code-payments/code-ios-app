//
//  Untitled.swift
//  Code
//
//  Created by Dima Bart on 2024-11-03.
//

import SwiftUI
import CodeUI

struct BalanceScreen: View {
    
    @ObservedObject private var session: Session
    
    private let container: AppContainer
    
    // MARK: - Init -
    
    init(session: Session, container: AppContainer) {
        self.session = session
        self.container = container
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
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
            }
        }
    }
}
