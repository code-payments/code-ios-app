//
//  DepositUSDCScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-02-07.
//

import SwiftUI
import CodeServices
import CodeUI

struct DepositUSDCScreen: View {
    
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var client: Client
    
    @ObservedObject private var session: Session
    
    @State private var relationshipEstablished: Bool = false
    @State private var buttonState: ButtonState = .normal
    
    private let depositAddress: PublicKey
    
    // MARK: - Init -
    
    init(session: Session) {
        self.session = session
        self.depositAddress = session.organizer.swapDepositAddress
    }
    
    private func didAppear() {
        ErrorReporting.breadcrumb(.buyMoreKinScreen)
        
        Task {
            try await establishSwapRelationship()
        }
    }
    
    private func establishSwapRelationship() async throws {
        guard session.organizer.info(for: .swap) == nil else {
            relationshipEstablished = true
            return
        }
        
        do {
            try await client.linkAdditionalAccounts(
                owner: session.organizer.ownerKeyPair,
                linkedAccount: session.organizer.swapKeyPair
            )
            relationshipEstablished = true
            
        } catch {
            bannerController.show(
                style: .error,
                title: "Account Error",
                description: "Failed to create a USDC deposit account."
            )
        }
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                Text("Buy more Kin by sending USDC to the address below.")
                    .font(.appTextSmall)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                
                if relationshipEstablished {
                    Button {
                        copyAddress()
                    } label: {
                        ImmutableField(depositAddress.base58)
                    }
                }
                
                Spacer()
                
                QRCode(
                    data: Data(depositAddress.base58.utf8),
//                    label: depositAddress.base58,
                    padding: 6,
                    codeColor: .white,
                    backgroundColor: .backgroundMain,
                    labelColor: .textSecondary.opacity(0.5),
                    correctionLevel: .medium
                )
                .frame(width: 200, height: 200)
                .contextMenu(ContextMenu {
                    Button(action: copyAddress) {
                        Label(Localized.Action.copyAddress, systemImage: SystemSymbol.doc.rawValue)
                    }
                })
                
                Spacer()
                
                CodeButton(
                    state: buttonState,
                    style: .filled,
                    title: Localized.Action.copyAddress,
                    action: copyAddress
                )
            }
            .padding(20)
        }
        .navigationBarTitle(Text(Localized.Action.buyMoreKin), displayMode: .inline)
        .onAppear {
            didAppear()
        }
    }
    
    // MARK: - Actions -
    
    private func copyAddress() {
        UIPasteboard.general.string = depositAddress.base58
        buttonState = .successText(Localized.Action.copied)
    }
}

#Preview {
    NavigationView {
        DepositUSDCScreen(session: .mock)
    }
}
