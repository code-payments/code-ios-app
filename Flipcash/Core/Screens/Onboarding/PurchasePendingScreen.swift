//
//  PurchasePendingScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-06-10.
//

import SwiftUI
import FlipcashUI

struct PurchasePendingScreen: View {
    
    @ObservedObject private var viewModel: OnboardingViewModel
    
    @State private var dialogItem: DialogItem?
    
    // MARK: - Init -
    
    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Spacer()
                    
                    LoadingView(color: .white)
                    Text("Purchase pending...")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                    
                    Spacer()
                    
                    CodeButton(style: .subtle, title: "Cancel Purchase") {
                        dialogItem = .init(
                            style: .destructive,
                            title: "Cancel Purchase?",
                            subtitle: "Are you sure you would like to cancel this purchase?",
                            dismissable: true,
                            actions: {
                                .destructive("Yes") {
                                    viewModel.cancelPendingPurchaseAction()
                                };
                                
                                .subtle("Nevermind") {}
                            }
                        )
                    }
                }
            }
            .padding(20)
        }
        .navigationBarBackButtonHidden(true)
        .dialog(item: $dialogItem)
    }
}
