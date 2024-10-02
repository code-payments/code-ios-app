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
    
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    
    @State private var didCancelBiometrics: Bool = false
    
    var body: some View {
        ZStack {
            Background(color: .backgroundMain) {
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
    BiometricsAuthScreen()
        .injectingEnvironment(from: .mock)
}
