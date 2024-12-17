//
//  AccessKeyScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-04-13.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct AccessKeyScreen: View {
    
    @ObservedObject private var viewModel: OnboardingViewModel
    
    // MARK: - Init -
    
    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Spacer()
                
                VStack(alignment: .center, spacing: 30) {
                    AccessKey(
                        mnemonic: viewModel.mnemonic,
                        url: .flipchatLogin(with: viewModel.mnemonic)
                    )
                    .contextMenu {
                        Button(action: copy) {
                            Label("Copy", systemImage: SystemSymbol.doc.rawValue)
                        }
                    }
                    
                    Text("Your Access Key is the only way to access your account. Please keep it private and safe.")
                        .font(.appTextSmall)
                        .foregroundColor(.textMain)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
                
                Spacer()
                
                CodeButton(
                    state: viewModel.accessKeyButtonState,
                    style: .filled,
                    title: "Save Access Key to Photos"
                ) {
                    viewModel.promptSaveToPhotos()
                }
                
                CodeButton(
                    style: .subtle,
                    title: "Wrote the 12 Words Down Instead?",
                    disabled: viewModel.accessKeyButtonState != .normal
                ) {
                    viewModel.promptWrittenConfirmation()
                }
            }
            .ignoresSafeArea(.keyboard)
            .foregroundColor(.textMain)
            .padding(20)
            .navigationBarTitle(Text("Your Access Key"), displayMode: .inline)
            .interactiveDismissDisabled()
        }
    }
    
    // MARK: - Copy / Paste -
    
    private func copy() {
        UIPasteboard.general.string = viewModel.mnemonic.phrase
    }
}

// MARK: - Previews -

#Preview {
    AccessKeyScreen(
        viewModel: .init(
            state: .mock,
            container: .mock,
            isPresenting: .constant(true)
        ) {}
    )
}
