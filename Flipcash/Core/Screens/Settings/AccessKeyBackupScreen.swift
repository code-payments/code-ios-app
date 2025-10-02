//
//  AccessKeyBackupScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-05-30.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct AccessKeyBackupScreen: View {
    
    @State private var buttonState: ButtonState = .normal
    @State private var dialogItem: DialogItem?
    
    private let mnemonic: MnemonicPhrase
    
    // MARK: - Init -
    
    init(mnemonic: MnemonicPhrase) {
        self.mnemonic = mnemonic
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                
                Text("Your Access Key is the only way to access your account. Please keep it private and safe.")
                    .font(.appTextSmall)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                Spacer()
                
                AccessKey(
                    mnemonic: mnemonic,
                    url: .login(with: mnemonic)
                )
                .contextMenu {
                    Button(action: copy) {
                        Label("Copy", systemImage: SystemSymbol.doc.rawValue)
                    }
                }
                
                Spacer()
                
                CodeButton(
                    state: buttonState,
                    style: .filled,
                    title: "Save to Photos",
                    action: saveToPhotosAction
                )
            }
            .ignoresSafeArea(.keyboard)
            .foregroundColor(.textMain)
            .padding(20)
            .navigationTitle("Access Key")
            .navigationBarTitleDisplayMode(.inline)
        }
        .dialog(item: $dialogItem)
    }
    
    // MARK: - Actions -
    
    private func saveToPhotosAction() {
        Task {
            buttonState = .loading
            
            do {
                try await PhotoLibrary.saveSecretRecoveryPhraseSnapshot(for: mnemonic)
                
                try await Task.delay(milliseconds: 150)
                buttonState = .success
                
            } catch {
                buttonState = .normal
                dialogItem = .init(
                    style: .destructive,
                    title: "Failed to Save",
                    subtitle: "Please allow Flipcash access to Photos in Settings in order to save your Access Key.",
                    dismissable: true
                ) {
                    .destructive("Open Settings") {
                        URL.openSettings()
                    };
                    .notNow()
                }
            }
        }
    }
    
    // MARK: - Copy / Paste -
    
    private func copy() {
        UIPasteboard.general.string = mnemonic.phrase
    }
}
