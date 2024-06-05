//
//  DownloadScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-06-04.
//

import SwiftUI
import CodeUI

struct DownloadScreen: View {
    
    @Binding var isPresented: Bool
    
    private let size: CGFloat = 250.0
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    
                    Spacer()
                    
                    VStack(spacing: 30) {
                        Text("Scan to download the\nCode Wallet app")
                            .frame(maxWidth: size)
                            .multilineTextAlignment(.center)
                            .font(.appTextLarge)
                            .foregroundColor(.textMain)
                        
                        QRCode(
                            string: URL.downloadCode.absoluteString,
                            showLabel: false,
                            codeColor: .backgroundMain,
                            correctionLevel: .high
                        )
                        .frame(width: size, height: size)
                        .overlay {
                            ZStack {
                                Rectangle()
                                    .fill(Color.textMain)
                                Image.asset(.codeLogo)
                                    .resizable()
                                    .renderingMode(.template)
                                    .foregroundColor(.backgroundMain)
                                    .padding(7)
                            }
                            .frame(width: 46, height: 46)
                        }
                    }
                    .padding(.bottom, 20)
                    
                    Spacer()
                    
                    CodeButton(style: .filled, title: Localized.Action.share) {
                        ShareSheet.present(url: .downloadCode)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Download Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarCloseButton(binding: $isPresented)
            }
        }
    }
}

#Preview {
    DownloadScreen(isPresented: .constant(true))
}
