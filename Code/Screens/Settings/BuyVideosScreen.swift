//
//  BuyVideosScreen.swift
//  Code
//
//  Created by Dima Bart on 2023-09-14.
//

import SwiftUI
import CodeServices
import CodeUI

struct BuyVideosScreen: View {
    
    // MARK: - Init -
    
    init() {
        
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            ScrollBox(color: .backgroundMain) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 40) {
                        
                        // Header
                        
                        VStack(alignment: .leading, spacing: 20) {
                            Text(Localized.Title.buySellKin)
                                .font(.appDisplayMedium)
                            Text(Localized.Subtitle.buySellDescription)
                                .font(.appTextMedium)
                        }
                        
                        // Buy
                        
                        VStack(spacing: 25) {
                            Button(action: openBuyVideo) {
                                ZStack {
                                    thumbnail(for: .videoBuyKin)
                                    Image.asset(.youtube)
                                }
                            }
                            
                            VStack(spacing: 0) {
                                CodeButton(style: .filled, title: Localized.Action.learnBuyKin, action: openBuyVideo)
                                CodeButton(style: .subtle, title: Localized.Action.shareVideo) {
                                    share(.videoBuyKin)
                                }
                            }
                        }
                        
                        // Sell
                        
                        VStack(spacing: 25) {
                            Button(action: openSellVideo) {
                                ZStack {
                                    thumbnail(for: .videoSellKin)
                                    Image.asset(.youtube)
                                }
                            }
                            
                            VStack(spacing: 0) {
                                CodeButton(style: .filled, title: Localized.Action.learnSellKin, action: openSellVideo)
                                CodeButton(style: .subtle, title: Localized.Action.shareVideo) {
                                    share(.videoSellKin)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding([.leading, .bottom, .trailing], 20)
                    .padding(.top, 5)
                    .foregroundColor(.textMain)
                }
            }
            .padding(.top)
            .navigationBarHidden(false)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            Analytics.open(screen: .buyVideo)
            ErrorReporting.breadcrumb(.buyVideoScreen)
        }
    }
    
    private func thumbnail(for asset: Asset) -> some View {
        Image.asset(asset)
            .resizable()
            .aspectRatio(16 / 9, contentMode: .fit)
            .cornerRadius(Metrics.buttonRadius)
            .clipped()
    }
    
    private func openBuyVideo() {
        URL.videoBuyKin.openWithApplication()
    }
    
    private func openSellVideo() {
        URL.videoSellKin.openWithApplication()
    }
    
    private func share(_ url: URL) {
        Task {
            await ShareSheet.present(url: url)
        }
    }
}


// MARK: - Previews -

struct BuyVideosScreen_Previews: PreviewProvider {
    static var previews: some View {
        BuyVideosScreen()
            .preferredColorScheme(.dark)
    }
}

