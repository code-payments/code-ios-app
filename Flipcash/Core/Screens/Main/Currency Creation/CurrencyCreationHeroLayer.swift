//
//  CurrencyCreationHeroLayer.swift
//  Flipcash
//
//  The wizard's hero overlay layer. Pure visuals — reads anchor rects
//  via `overlayPreferenceValue(HeroAnchorKey.self)` and positions an
//  independent HeroCircle and HeroName at those rects. Never
//  interactive: `.allowsHitTesting(false)` lets taps pass through to
//  the real Menu / TextField underneath.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct HeroLayer: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    @Bindable var state: CurrencyCreationState
    let heroNameRevealed: Bool
    let anchors: [HeroAnchorID: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if step != .billCreation, let rect = anchors[.circle].map({ proxy[$0] }) {
                    HeroCircle(step: step, selectedImage: state.selectedImage)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                if step != .billCreation, let rect = anchors[.name].map({ proxy[$0] }) {
                    HeroName(step: step, name: state.currencyName)
                        .frame(width: rect.width, height: rect.height, alignment: .leading)
                        .position(x: rect.midX, y: rect.midY)
                        .opacity(step == .name && !heroNameRevealed ? 0 : 1)
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(false)
    }
}

private struct HeroCircle: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    let selectedImage: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.2))

            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "plus")
                    .font(.system(size: step == .icon ? 40 : 18, weight: .light))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .compositingGroup()
        .clipShape(Circle())
    }
}

private struct HeroName: View {
    let step: CurrencyCreationWizardScreen.WizardStep
    let name: String

    var body: some View {
        Text(name.isEmpty ? " " : name)
            .font(font)
            .foregroundStyle(Color.textMain)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var font: Font {
        switch step {
        case .name: .appDisplayMedium
        case .icon: .appDisplaySmall
        case .description, .billCreation, .confirmation: .appTextLarge
        }
    }

    private var alignment: Alignment {
        switch step {
        case .icon: .center
        case .name, .description, .billCreation, .confirmation: .leading
        }
    }
}
