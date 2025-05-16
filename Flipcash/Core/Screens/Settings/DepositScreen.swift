//
//  DepositScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct DepositScreen: View {
    
    @ObservedObject private var session: Session
    
    @State private var buttonState: ButtonState = .normal
    
    private let depositAddress: PublicKey
    
    // MARK: - Init -
    
    init(session: Session) {
        self.session   = session
        self.depositAddress = session.owner.depositPublicKey
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Deposit USDC into your Code wallet by sending USDC to your deposit address below. Tap to copy.")
                    .font(.appTextMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button {
                    copyAddress()
                } label: {
                    ImmutableField(depositAddress.base58)
                }
                
                Spacer()
                
                CodeButton(
                    state: buttonState,
                    style: .filled,
                    title: "Copy Address",
                    action: copyAddress
                )
//                QRCode(
//                    data: Data(publicKey.base58.utf8),
//                    padding: 6,
//                    codeColor: .white,
//                    backgroundColor: .backgroundMain,
//                    labelColor: .textSecondary.opacity(0.5),
//                    correctionLevel: .medium
//                )
//                .frame(width: 200, height: 200)
//                .contextMenu(ContextMenu {
//                    Button(action: copyAddress) {
//                        Label("Copy Address", systemImage: SystemSymbol.doc.rawValue)
//                    }
//                })
//
//                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("Deposit")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Actions -
    
    private func copyAddress() {
        UIPasteboard.general.string = depositAddress.base58
        buttonState = .successText("Copied")
    }
}
