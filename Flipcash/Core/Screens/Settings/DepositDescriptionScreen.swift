//
//  DepositDescriptionScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct DepositDescriptionScreen: View {
    
    @State private var isShowingDeposit: Bool = false
    
    private let session: Session
    
    // MARK: - Init -
    
    init(session: Session) {
        self.session = session
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 20) {
                NavigationLink(
                    destination: DepositScreen(session: session),
                    isActive: $isShowingDeposit
                ) { EmptyView() }
                
                Spacer()
                
                Image.asset(.depositCircle)
                
                Spacer()
                
                Text("Purchase USDC on a crypto exchange with your bank account, and then deposit into Flipcash")
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                VStack(spacing: 0) {
                    CodeButton(
                        style: .filled,
                        title: "Deposit USDC",
                        action: depositAction
                    )
                    
                    CodeButton(
                        style: .subtle,
                        title: "Learn How to Get USDC",
                        action: learnAction
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .navigationTitle("Deposit")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Actions -
    
    private func depositAction() {
        isShowingDeposit.toggle()
    }
    
    private func learnAction() {
        let url = URL(string: "https://chatgpt.com/share/68431710-5824-8002-af0a-c4948970b626")!
        url.openWithApplication()
    }
}
