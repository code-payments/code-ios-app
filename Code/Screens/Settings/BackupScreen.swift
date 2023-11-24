//
//  BackupScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-11-16.
//

import SwiftUI
import CodeServices
import CodeUI

struct BackupScreen: View {
    
    @EnvironmentObject var bannerController: BannerController
    
    @State private var buttonState: ButtonState = .normal
    
    private let mnemonic: MnemonicPhrase
    private let owner: PublicKey
    
    // MARK: - Init -
    
    init(mnemonic: MnemonicPhrase, owner: PublicKey) {
        self.mnemonic = mnemonic
        self.owner = owner
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 10) {
                Text(Localized.Subtitle.accessKeyDescription)
                    .font(.appTextSmall)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                AccessKey(
                    mnemonic: mnemonic,
                    url: .login(with: mnemonic)
                )
                .contextMenu(ContextMenu {
                    Button(action: copyWords) {
                        Label(Localized.Action.copy, systemImage: SystemSymbol.doc.rawValue)
                    }
                })
                
                Spacer()
                
                CodeButton(
                    state: buttonState,
                    style: .filled,
                    title: Localized.Action.saveToPhotos,
                    action: saveScreeshot
                )
            }
            .padding(20)
        }
        .navigationBarTitle(Text(Localized.Title.accessKey), displayMode: .inline)
        .onAppear {
            Analytics.open(screen: .backup)
            ErrorReporting.breadcrumb(.backupScreen)
        }
    }
    
    // MARK: - Actions -
    
    private func saveScreeshot() {
        Task {
            do {
                buttonState = .loading
                try await PhotoLibrary.saveSecretRecoveryPhraseSnapshot(for: mnemonic)
                buttonState = .success
                try await Task.delay(seconds: 3)
                buttonState = .normal
            } catch {
                bannerController.show(
                    style: .error,
                    title: Localized.Error.Title.failedToSave,
                    description: Localized.Error.Description.failedToSave,
                    actions: [
                        .cancel(title: Localized.Action.ok),
                        .standard(title: Localized.Action.openSettings) {
                            URL.openSettings()
                        }
                    ]
                )
            }
        }
    }
    
    private func copyWords() {
        UIPasteboard.general.string = mnemonic.phrase
    }
    
    private func copyLink() {
        UIPasteboard.general.string = loginLink().absoluteString
    }
    
    private func loginLink() -> URL {
        .login(with: mnemonic)
    }
    
    private func payloadForQRCode() -> Data {
        Data(loginLink().absoluteString.utf8)
    }
}

// MARK: - Previews -

struct BackupScreen_Previews: PreviewProvider {
    
    private static let words = "dust diet cruise swap country chat mixed local fiscal double egg dumb".components(separatedBy: " ")
    
    static var previews: some View {
        Preview(devices: .iPhoneSE, .iPhoneMax) {
            NavigationView {
                BackupScreen(
                    mnemonic: MnemonicPhrase(words: words)!,
                    owner: KeyAccount.mock.ownerPublicKey
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}
