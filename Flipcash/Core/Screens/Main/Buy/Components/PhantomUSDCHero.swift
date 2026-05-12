//
//  PhantomUSDCHero.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashUI

/// Dual-logo hero used by both `PhantomEducationScreen` ("disconnected" state)
/// and `PhantomConfirmScreen` ("connected" state, with checkmark badge).
struct PhantomUSDCHero: View {

    let connected: Bool

    var body: some View {
        HStack(spacing: -8) {
            Image.asset(.phantom)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    if connected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.green)
                    }
                }
            Image.asset(.solanaUSDC)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(Circle())
        }
    }
}
