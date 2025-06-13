//
//  PurchasePendingScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-06-10.
//

import SwiftUI
import FlipcashUI

struct PurchasePendingScreen: View {
    
    // MARK: - Init -
    
    init() {}
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    LoadingView(color: .white)
                    Text("Purchase pending...")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(20)
        }
        .navigationBarBackButtonHidden(true)
    }
}
