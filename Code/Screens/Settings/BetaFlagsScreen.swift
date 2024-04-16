//
//  BetaFlagsScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-25.
//

import SwiftUI
import CodeUI

struct BetaFlagsScreen: View {
    
    @ObservedObject private var betaFlags: BetaFlags
    @ObservedObject private var tipController: TipController

    private var options: [Option] = []
    
    // MARK: - Init -
    
    init(betaFlags: BetaFlags, tipController: TipController) {
        self.betaFlags = betaFlags
        self.tipController = tipController
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            ScrollBox(color: .backgroundMain) {
                LazyTable(spacing: 0) {
                    ForEach(BetaFlags.Option.allCases) { option in
                        HStack(spacing: 12) {
                            Toggle(isOn: betaFlags.bindingFor(option: option)) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(option.localizedTitle)
                                        .foregroundColor(.textMain)
                                        .font(.appTextMedium)
                                    Text(option.localizedDescription)
                                        .foregroundColor(.textSecondary)
                                        .font(.appTextHeading)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(.trailing, 20)
                            }
                            .padding([.top, .bottom], 10)
                        }
                        .padding(20)
                        .vSeparator(color: .rowSeparator, position: .bottom)
                    }
                    CodeButton(style: .filled, title: "Reset Local Twitter User") {
                        tipController.deleteAuthenticatedUser()
                    }
                    .padding(20)
                }
            }
        }
        .navigationBarTitle(Text("Beta Flags"), displayMode: .inline)
        .onAppear {
            Analytics.open(screen: .debug)
            ErrorReporting.breadcrumb(.debugScreen)
        }
    }
}

extension BetaFlagsScreen {
    struct Option {
        var title: String
        var description: String
        var binding: Binding<Bool>
    }
}

// MARK: - Previews -

struct DebugScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            BetaFlagsScreen(betaFlags: BetaFlags.shared, tipController: .mock)
        }
        .preferredColorScheme(.dark)
    }
}
