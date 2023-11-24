//
//  Snapshot.swift
//  Code
//
//  Created by Dima Bart on 2022-08-19.
//

import SwiftUI
import CodeUI
import CodeServices

struct Snapshot: View {
    
    var mnemonic: MnemonicPhrase
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                Spacer()
                
                AccessKey(
                    mnemonic: mnemonic,
                    url: .login(with: mnemonic)
                )
                
                Spacer()
                
                Text(Localized.Subtitle.accessKeySnapshotDescription)
                    .font(.appTextHeading)
                    .foregroundColor(.textMain)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 255)
                
                Spacer()
            }
            .foregroundColor(.textMain)
            .padding([.leading, .trailing], 0)
            .padding([.top, .bottom], 60)
        }
    }
    
    private func keyPairForMnemonic() -> KeyPair {
        KeyPair(mnemonic: mnemonic, path: .solana)
    }
    
    private func loginLink() -> URL {
        .login(with: mnemonic)
    }
    
    private func payloadForQRCode() -> Data {
        Data(loginLink().absoluteString.utf8)
    }
}

// MARK: - CGRect (iPhones) -

extension CGRect {
    static let iPhone13 = CGRect(x: 0, y: 0, width: 390, height: 844)
}

// MARK: - Previews -

struct Snapshot_Previews: PreviewProvider {
    static var previews: some View {
        Snapshot(mnemonic: .mock)
            .previewLayout(.fixed(width: CGRect.iPhone13.width, height: CGRect.iPhone13.height))
    }
}
