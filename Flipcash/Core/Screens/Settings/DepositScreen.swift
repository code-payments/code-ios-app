//
//  DepositScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct DepositScreen: View {
    @State private var buttonState: ButtonState = .normal
    
    private let cluster: AccountCluster
    private let name: String?
    
    // MARK: - Init -
    
    init(cluster: AccountCluster, name: String?) {
        self.cluster = cluster
        self.name    = name
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Deposit funds into your wallet by sending \(name ?? "funds") to your deposit address below. Tap to copy.")
                    .font(.appTextMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button {
                    copyAddress()
                } label: {
                    ImmutableField(cluster.depositPublicKey.base58)
                }
                
                Spacer()
                
                CodeButton(
                    state: buttonState,
                    style: .filled,
                    title: "Copy Address",
                    action: copyAddress
                )
            }
            .padding(20)
        }
        .navigationTitle("Deposit\(name != nil ? " \(name!)" : "")")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Actions -
    
    private func copyAddress() {
        UIPasteboard.general.string = cluster.depositPublicKey.base58
        buttonState = .successText("Copied")
    }
}
