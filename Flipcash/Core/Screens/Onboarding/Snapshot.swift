//
//  Snapshot.swift
//  Code
//
//  Created by Dima Bart on 2022-08-19.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct Snapshot: View {
    
    var mnemonic: MnemonicPhrase
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                Spacer()
                
                Text("Warning! This image gives access to your Flipchat account. Do not share this image with anyone else. Keep it secure and safe.")
                    .font(.appTextSmall)
                    .foregroundColor(.textError)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 255)
                    .padding(.bottom, 20)
                
                Spacer()
                
                AccessKey(
                    mnemonic: mnemonic,
                    url: .login(with: mnemonic)
                )
                .padding(.bottom, 20)
                
                Spacer()
                
                Text("Tap and hold the QR code to log in. Alternatively you can log in manually by entering the 12 words in the Code Log In screen.")
                    .font(.appTextHeading)
                    .foregroundColor(.textMain)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 255)
                
                Spacer()
            }
            .foregroundColor(.textMain)
            .padding([.leading, .trailing], 0)
            .padding(.top, 30)
            .padding(.bottom, 60)
        }
    }
}

// MARK: - CGRect (iPhones) -

extension CGRect {
    static let iPhone13 = CGRect(x: 0, y: 0, width: 390, height: 844)
}
