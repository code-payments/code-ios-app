//
//  ChangeCoverScreen.swift
//  Flipchat
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct ChangeCoverScreen: View {
    
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var viewModel: ChatViewModel

    private let chatID: ChatID
    
    // MARK: - Init -
    
    init(chatID: ChatID, viewModel: ChatViewModel) {
        self.chatID = chatID
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .coverCharge,
                    enteredAmount: $viewModel.enteredNewCover,
                    actionState: $viewModel.buttonState,
                    actionEnabled: { _ in
                        viewModel.isEnteredCoverChargeValid()
                    }
                ) {
                    viewModel.changeCover(chatID: chatID)
                }
                .onAppear(perform: onAppear)
                .foregroundColor(.textMain)
                .padding(20)
                .navigationBarTitle(Text("Change Cover Charge"), displayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(binding: $viewModel.isShowingChangeCover)
                    }
                }
            }
        }
    }
    
    private func onAppear() {
        
    }
}

#Preview {
    ChangeCoverScreen(chatID: .mock, viewModel: .mock)
}
