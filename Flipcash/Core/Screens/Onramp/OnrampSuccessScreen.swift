//
//  OnrampSuccessScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct OnrampSuccessScreen: View {
    
    @ObservedObject private var viewModel: OnrampViewModel
    
    // MARK: - Init -
    
    init(viewModel: OnrampViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 20) {
                Spacer()
                
                VStack(spacing: 30) {
                    Image.asset(.successCircle)
                    
                    Text("Success")
                        .font(.appDisplaySmall)
                        .foregroundStyle(Color.textMain)
                    
                    VStack {
                        Text("Your cash is on the way and should arrive in a few minutes.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.textSecondary)
                        Text(viewModel.enteredEmail)
                            .foregroundStyle(Color.textMain)
                    }
                    .font(.appTextMedium)
                }
                
                Spacer()
                
                // Bottom
                VStack(spacing: 15) {
                    Text("If you have any issues receiving you funds please contact Coinbase at support@coinbase.com")
                        .font(.appTextSmall)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    CodeButton(
                        style: .filled,
                        title: "OK"
                    ) {
                        viewModel.navigateToRoot()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard)
    }
}
