//
//  ProfilePinnedBackdrop.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

extension View {

    /// Backs a profile's pinned bottom bar with the screen's background and a fade above it, so the
    /// bar's text stays readable over the content scrolling underneath.
    ///
    /// The system scroll edge effect fades too gradually for the encryption line to read over an
    /// avatar grid.
    func profilePinnedBackdrop() -> some View {
        background {
            VStack(spacing: 0) {
                // Eased rather than linear: it turns mostly opaque early, so a row cut off at the
                // top reads as a soft shadow instead of a hard sliver.
                LinearGradient(
                    stops: [
                        .init(color: Color.backgroundMain.opacity(0), location: 0),
                        .init(color: Color.backgroundMain.opacity(0.55), location: 0.3),
                        .init(color: Color.backgroundMain.opacity(0.85), location: 0.6),
                        .init(color: Color.backgroundMain, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: ProfilePinnedBackdrop.fadeHeight)
                Color.backgroundMain
            }
            .padding(.top, -ProfilePinnedBackdrop.fadeHeight)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    /// Ends a profile's scroll content above the fade ``profilePinnedBackdrop()`` draws over the
    /// pinned bar, so the last row is readable when scrolled to the bottom. Apply to the scroll view.
    func profilePinnedBackdropClearance() -> some View {
        contentMargins(.bottom, ProfilePinnedBackdrop.fadeHeight, for: .scrollContent)
    }
}

private enum ProfilePinnedBackdrop {
    static let fadeHeight: CGFloat = 56
}
