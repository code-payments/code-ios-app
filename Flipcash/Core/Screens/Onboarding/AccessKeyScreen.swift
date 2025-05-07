//
//  AccessKeyScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-04-13.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

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
                        mnemonic: viewModel.inflightMnemonic,
                        url: .login(with: viewModel.inflightMnemonic)
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
                    title: "Save Access Key to Photos",
                    action: viewModel.saveToPhotosAction
                )
                
                CodeButton(
                    style: .subtle,
                    title: "Wrote the 12 Words Down Instead?",
                    disabled: viewModel.accessKeyButtonState != .normal,
                    action: viewModel.wroteDownAction
                )
            }
            .ignoresSafeArea(.keyboard)
            .foregroundColor(.textMain)
            .padding(20)
            .navigationBarTitle(Text("Your Access Key"), displayMode: .inline)
            .interactiveDismissDisabled()
        }
        .dialog(item: $viewModel.dialogItem)
    }
    
    // MARK: - Copy / Paste -
    
    private func copy() {
        UIPasteboard.general.string = viewModel.inflightMnemonic.phrase
    }
}
