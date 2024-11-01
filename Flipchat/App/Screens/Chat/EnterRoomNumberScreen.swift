//
//  EnterRoomNumberScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI
import CodeServices

struct EnterRoomNumberScreen: View {
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var viewModel: ChatViewModel
    
    // MARK: - Init -
    
    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    enteredAmount: $viewModel.enteredRoomNumber,
                    actionState: $viewModel.beginChatState,
                    subtext: "Enter Room Number",
                    formatter: .roomNumber,
                    actionEnabled: { _ in
                        viewModel.isEnteredRoomNumberValid()
                    },
                    action: viewModel.attemptEnterGroupChat
                )
                .onAppear(perform: onAppear)
                .foregroundColor(.textMain)
                .padding(20)
                .navigationBarTitle(Text("Enter Room Number"), displayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(binding: $viewModel.isShowingEnterRoomNumber)
                    }
                }
            }
        }
    }
    
    private func onAppear() {
        
    }
}

#Preview {
    EnterRoomNumberScreen(viewModel: .mock)
}
