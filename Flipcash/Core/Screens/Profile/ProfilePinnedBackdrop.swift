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
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isActive)
    }

    /// Fades content into the bottom of a profile that pins no bar, the way the chat's transcript
    /// dissolves under its composer: a ramp across the home indicator's inset only, so the row that
    /// ends the scroll stays clear of it. `isActive` false draws nothing, for a screen whose content
    /// doesn't scroll.
    func profileBarlessFade(isActive: Bool) -> some View {
        background {
            if isActive {
                LinearGradient(
                    gradient: ChatFade.gradient(Color.backgroundMain),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isActive)
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
            // The insets (home indicator, pinned bar) are space content can't settle in, so short
            // content stretched past them would scroll.
            ScrollHeights(
                visible: geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom,
                content: geometry.contentSize.height,
                bottomInset: geometry.contentInsets.bottom,
                isAtEnd: geometry.visibleRect.maxY >= geometry.contentSize.height - 1
            )
        } action: { _, heights in
            fit.wrappedValue.update(
                visibleHeight: heights.visible,
                contentHeight: heights.content,
                bottomInset: heights.bottomInset,
                isAtEnd: heights.isAtEnd
            )
        }
    }
}

/// How a profile's scroll content fits the screen.
struct ProfileScrollFit: Equatable {

    /// The height the scroll view shows content in, which short content stretches to.
    private(set) var visibleHeight: CGFloat = 0

    /// Whether the content runs past the screen, which is when a barless profile's bottom fade
    /// belongs.
    private(set) var overflows = false

    /// The inset under the visible height, which content may draw into without scrolling.
    private(set) var bottomInset: CGFloat = 0

    /// Whether the content is scrolled to its end, where nothing is left to fade out under the
    /// home indicator.
    private(set) var isAtEnd = true

    /// Whether the content runs past the screen and more of it lies below, which is when a barless
    /// profile's bottom fade belongs.
    var fadesBottom: Bool { overflows && !isAtEnd }

    /// Records the scroll view's visible height, its content's height, its bottom inset, and
    /// whether it's scrolled to the end.
    mutating func update(visibleHeight: CGFloat, contentHeight: CGFloat, bottomInset: CGFloat = 0, isAtEnd: Bool = true) {
        self.visibleHeight = visibleHeight
        self.bottomInset = bottomInset
        self.isAtEnd = isAtEnd
        overflows = contentHeight > visibleHeight + 0.5
    }
}

private struct ScrollHeights: Equatable {
    let visible: CGFloat
    let content: CGFloat
    let bottomInset: CGFloat
    let isAtEnd: Bool
}

private enum ProfilePinnedBackdrop {
    static let fadeHeight: CGFloat = 56
}
