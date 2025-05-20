//
//  BetaFlagsScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-25.
//

import SwiftUI
import FlipcashUI

struct BetaFlagsScreen: View {
    
    @ObservedObject private var betaFlags: BetaFlags

    private var options: [Option] = []
    
    // MARK: - Init -
    
    init(container: Container) {
        self.betaFlags = container.betaFlags
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
                            .tint(.textSuccess)
                            .padding([.top, .bottom], 10)
                        }
                        .padding(20)
                        .vSeparator(color: .rowSeparator, position: .bottom)
                    }
                }
            }
        }
        .navigationTitle("Beta Flags")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension BetaFlagsScreen {
    struct Option {
        var title: String
        var description: String
        var binding: Binding<Bool>
    }
}
