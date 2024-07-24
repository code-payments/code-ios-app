//
//  ConnectXScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI
import CodeServices

struct ConnectXScreen: View {
    
    @Binding public var isPresented: Bool
    
    private let reason: Reason
    private let tipController: TipController
    
    @State private var nonce = UUID()
    
    // MARK: - Init -
    
    init(reason: Reason, tipController: TipController, isPresented: Binding<Bool>) {
        self.reason = reason
        self.tipController = tipController
        self._isPresented = isPresented
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(Localized.Title.receiveTips)
                        .font(.appDisplayMedium)
                    
                    Text(reason.subtitle)
                        .font(.appTextMedium)
                }
                
                Spacer()
                
                HStack(alignment: .top, spacing: 15) {
                    PlaceholderAvatar(diameter: 25)
                    Text(tipController.generateTwitterAuthMessage(nonce: nonce, short: reason.isTwitterPromptShort))
                        .font(.appTextSmall)
                        .foregroundColor(.textMain)
                }
                .padding(20)
                .background(Color.bannerInfo)
                .cornerRadius(4)
                
                Spacer()
                Spacer()
                
                CodeButton(
                    style: .filled,
                    image: Image.asset(.twitter),
                    title: Localized.Action.messageGetCode
                ) {
                    Analytics.messageCodeOnX()
                    tipController.openTwitterWithAuthenticationText(nonce: nonce, short: reason.isTwitterPromptShort)
                    Task {
                        try await Task.delay(milliseconds: 500)
                        isPresented = false
                    }
                }
            }
            .foregroundColor(.textMain)
            .frame(maxHeight: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .padding(.horizontal, 20)
        }
        .navigationBarTitle(Text(""), displayMode: .inline)
        .onAppear {
            Analytics.openConnectX()
        }
    }
}

extension ConnectTwitterScreen {
    enum Reason {
        case tipCard
        case identity
        
        var isTwitterPromptShort: Bool {
            switch self {
            case .tipCard:
                return false
            case .identity:
                return true
            }
        }
        
        var title: String {
            switch self {
            case .tipCard:
                return Localized.Title.requestTip
            case .identity:
                return Localized.Title.connectAccount
            }
        }
        
        var subtitle: String {
            switch self {
            case .tipCard:
                return Localized.Subtitle.tipCardTwitterDescription
            case .identity:
                return Localized.Subtitle.connectAccountTwitterDescription
            }
        }
    }
}

#Preview {
    ConnectXScreen(
        tipController: .mock, 
        isPresented: .constant(true)
    )
}
