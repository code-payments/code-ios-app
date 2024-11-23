//
//  EnterRoomNumberScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI

struct EnterRoomNumberScreen: View {
    
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var viewModel: ChatViewModel
    
    // MARK: - Init -
    
    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.joinRoomPath) {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .roomNumber,
                    enteredAmount: $viewModel.enteredRoomNumber,
                    actionState: $viewModel.buttonState,
                    actionEnabled: { _ in
                        viewModel.isEnteredRoomNumberValid()
                    },
                    action: viewModel.previewChat
                )
                .onAppear(perform: onAppear)
                .foregroundColor(.textMain)
                .padding(20)
                .navigationBarTitle(Text("Enter a Room Number"), displayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(binding: $viewModel.isShowingEnterRoomNumber)
                    }
                }
            }
            .navigationDestination(for: JoinRoomPath.self) { path in
                switch path {
                case .previewRoom(let chat, let members, let host):
                    PreviewRoomScreen(
                        chat: chat,
                        members: members,
                        host: host,
                        viewModel: viewModel
                    )
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
