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
                
                Text("You can deposit funds from your bank account into Flipcash")
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                CodeButton(
                    style: .filled,
                    title: "Learn How to Deposit Funds",
                    action: learnAction
                )
                
                NavigationLink {
                    DepositScreen(session: session)
                } label: {
                    CodeButton(
                        style: .filled,
                        title: "Deposit Funds Now",
                        action: depositAction
                    )
                }
            }
            .padding(20)
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
