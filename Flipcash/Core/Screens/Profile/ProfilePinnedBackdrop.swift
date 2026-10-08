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
    /// avatar grid. `isActive` false draws nothing, for a screen whose content doesn't scroll.
    func profilePinnedBackdrop(isActive: Bool = true) -> some View {
        background {
            if isActive {
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
    }

    /// Ends a profile's scroll content above the fade ``profilePinnedBackdrop()`` draws over the
    /// pinned bar, so the last row is readable when scrolled to the bottom. Apply to the scroll view;
    /// `isActive` false leaves the margin off a screen that draws no backdrop.
    func profilePinnedBackdropClearance(isActive: Bool = true) -> some View {
        contentMargins(.bottom, isActive ? ProfilePinnedBackdrop.fadeHeight : 0, for: .scrollContent)
    }

    /// Keeps `fit` current with how the scroll view's content fits it, so a profile can stretch
    /// short content to the screen and show the fade only when content scrolls. Apply to the scroll
    /// view.
    func profileScrollFit(_ fit: Binding<ProfileScrollFit>) -> some View {
        onScrollGeometryChange(for: ScrollHeights.self) { geometry in
            ScrollHeights(visible: geometry.containerSize.height, content: geometry.contentSize.height)
        } action: { _, heights in
            fit.wrappedValue.update(visibleHeight: heights.visible, contentHeight: heights.content)
        }
    }
}

/// How a profile's scroll content fits the screen.
struct ProfileScrollFit: Equatable {

    /// The height the scroll view shows content in, which short content stretches to.
    private(set) var visibleHeight: CGFloat = 0

    /// Whether the content runs past the screen, which is when the bottom fade and its clearance
    /// belong.
    private(set) var overflows = false

    /// Records the scroll view's visible height and its content's height.
    mutating func update(visibleHeight: CGFloat, contentHeight: CGFloat) {
        self.visibleHeight = visibleHeight
        // The clearance shrinks the visible height while it is on; compare against the height
        // without it, or turning it on would keep it on.
        let clearance = overflows ? ProfilePinnedBackdrop.fadeHeight : 0
        overflows = contentHeight > visibleHeight + clearance + 0.5
    }
}

private struct ScrollHeights: Equatable {
    let visible: CGFloat
    let content: CGFloat
}

private enum ProfilePinnedBackdrop {
    static let fadeHeight: CGFloat = 56
}
