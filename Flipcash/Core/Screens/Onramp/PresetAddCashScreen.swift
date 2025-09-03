//
//  AddCashScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct PresetAddCashScreen: View {
    
    @Binding var isPresented: Bool
    
    @ObservedObject private var viewModel: OnrampViewModel
    
    private let container: Container
    private let session: Session
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented = isPresented
        self.container    = container
        self.session      = sessionContainer.session
        self.viewModel    = sessionContainer.onrampViewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 20) {
                    GridAmounts(selected: viewModel.adjustingSelectedPreset) { action in
                        
                    }
                    
                    CodeButton(
                        style: .filled, 
                        title: "Add Cash with Apple Pay",
                        disabled: !viewModel.hasSelectedPreset
                    ) {
                        viewModel.presetSelectedAction()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .navigationTitle("Add Cash with Debit Card")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(binding: $isPresented)
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
            .overlay {
                viewModel.applePayWebView()
            }
        }
        .frame(height: 320)
    }
}
