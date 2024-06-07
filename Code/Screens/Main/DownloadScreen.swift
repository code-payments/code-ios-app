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
    
    private let size: CGFloat = 230.0
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    
                    Spacer()
                    
                    VStack(spacing: 80) {
                        Text(Localized.Subtitle.scanToDownload)
                            .frame(maxWidth: size)
                            .multilineTextAlignment(.center)
                            .font(.appTextLarge)
                            .foregroundColor(.textMain)
                        
                        VStack(spacing: 35) {
                            QRCode(
                                string: URL.downloadCode(ref: .iosQR).absoluteString,
                                showLabel: false,
                                padding: 0,
                                cornerRadius: 0,
                                codeColor: .backgroundMain,
                                correctionLevel: .low
                            )
                            .frame(width: size, height: size)
                            .contextMenu(ContextMenu {
                                Button(action: copy) {
                                    Label(Localized.Action.copy, systemImage: SystemSymbol.doc.rawValue)
                                }
                            })
                            
                            HStack(spacing: 30) {
                                Image.asset(.logoApple)
                                Image.asset(.logoAndroid)
                            }
                        }
                    }
                    .padding(.bottom, 44) // Adjust for nav bar center
                    
                    Spacer()
                    
                    CodeButton(style: .filled, title: Localized.Action.share) {
                        ShareSheet.present(url: .downloadCode(ref: .iosLink))
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarCloseButton(binding: $isPresented)
            }
        }
    }
    
    private func copy() {
        UIPasteboard.general.string = URL.downloadCode(ref: .iosLink).absoluteString
    }
}

#Preview {
    DownloadScreen(isPresented: .constant(true))
}
