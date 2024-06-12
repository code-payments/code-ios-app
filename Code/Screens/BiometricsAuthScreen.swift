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
                    Button {
                        verify()
                    } label: {
                        TextBubble(
                            style: .filled,
                            font: .appTextMedium,
                            text: "Unlock Code",
                            paddingVertical: 5,
                            paddingHorizontal: 15
                        )
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
