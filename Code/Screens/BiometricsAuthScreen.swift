//
//  BiometricsAuthScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-06-11.
//

import SwiftUI
import CodeServices
import CodeUI

struct BiometricsAuthScreen: View {
    
    @State private var didCancelBiometrics: Bool = false
    
    private let sessionAuthenticator: SessionAuthenticator
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    var body: some View {
        ZStack {
            ScanScreen.Placeholder()
            
            Background(color: .backgroundMain.opacity(0.85)) {
                VStack {
                    Spacer()
                }
            }
            
            VStack(spacing: 0) {
                Spacer()
                
                if didCancelBiometrics {
                    BubbleButton(text: Localized.Action.unlockCode) {
                        verify()
                    }
                }
                
                Spacer()
            }
        }
        .onAppear {
            verify()
        }
    }
    
    private func verify() {
        Task {
            let isVerified = await sessionAuthenticator.verifyBiometrics()
            didCancelBiometrics = !isVerified
        }
    }
}

#Preview {
    BiometricsAuthScreen(sessionAuthenticator: .mock)
}
