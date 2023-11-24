//
//  DepositScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import CodeServices
import CodeUI

struct DepositScreen: View {
    
    @ObservedObject private var session: Session
    
    @State private var buttonState: ButtonState = .normal
    
    private let publicKey: PublicKey
    
    // MARK: - Init -
    
    init(session: Session) {
        self.session   = session
        self.publicKey = session.organizer.primaryVault
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                Text(Localized.Subtitle.howToDeposit)
                    .font(.appTextSmall)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                
                Button {
                    copyAddress()
                } label: {
                    ImmutableField(publicKey.base58)
                }
                
                Spacer()
                
                CodeButton(
                    state: buttonState,
                    style: .filled,
                    title: Localized.Action.copyAddress,
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
        .navigationBarTitle(Text(Localized.Title.depositKin), displayMode: .inline)
        .onAppear {
            Analytics.open(screen: .deposit)
            ErrorReporting.breadcrumb(.depositScreen)
        }
    }
    
    // MARK: - Actions -
    
    private func copyAddress() {
        UIPasteboard.general.string = publicKey.base58
        buttonState = .successText(Localized.Action.copied)
    }
}

// MARK: - Previews -

struct DepositScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DepositScreen(session: .mock)
        }
    }
}
