//
//  TrayPresentation.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

extension View {

    /// Presents a tray for `item` while it is non-nil: a floating panel sized to its content on
    /// iOS 26, an edge-attached partial sheet on iOS 18.
    ///
    /// The card follows its content's height as steps change. With `isDismissable` false it can't
    /// be dragged away and its root step shows no X. `onDismiss` runs however the tray leaves.
    public func tray<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        isDismissable: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            TrayHost(isDismissable: isDismissable) {
                content(item)
            }
        }
    }

    /// Presents a tray while `isPresented` is true, as `tray(item:)` does for an item.
    public func tray<Content: View>(
        isPresented: Binding<Bool>,
        isDismissable: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            TrayHost(isDismissable: isDismissable, content: content)
        }
    }
}

/// The sheet's root: hangs the tray's card from the sheet's bottom edge, measures it, and hands
/// the height to the UIKit seam, which keeps the sheet invisible and tall enough.
private struct TrayHost<Content: View>: View {

    let isDismissable: Bool
    @ViewBuilder let content: Content

    @State private var cardHeight: CGFloat = 0
    /// The tallest the card can be, once the sheet has said; a taller page scrolls inside the card.
    @State private var maximumCardHeight: CGFloat?

    /// The floating sheet's bottom safe area covers nothing, so the card sits on its bottom edge;
    /// the iOS 18 sheet keeps the card's content above the home indicator.
    private static var floatingEdges: Edge.Set {
        if #available(iOS 26, *) { .bottom } else { [] }
    }

    var body: some View {
        // The root takes the sheet's size whatever the card's. A root sized by a card taller than
        // the sheet is centred by the hosting controller, which moved the card by half the change
        // on every grow; an overlay lets the card overhang instead.
        Color.clear
            .overlay(alignment: .bottom) {
                content
                    // Its full height until the sheet's limit is known, then offered that limit.
                    .fixedSize(horizontal: false, vertical: maximumCardHeight == nil)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        cardHeight = height
                    }
                    .environment(\.trayIsDismissable, isDismissable)
                    .frame(height: maximumCardHeight, alignment: .bottom)
            }
            .ignoresSafeArea(.container, edges: Self.floatingEdges)
            .background {
                TraySheetSeam(
                    cardHeight: cardHeight,
                    dimsBackground: TrayMetrics.dimsBackground,
                    onMaximumCardHeight: { maximumCardHeight = $0 }
                )
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            // The card draws its own surface; the sheet stays clear (see `TrayFill`).
            .presentationBackground(.clear)
            // Never changes, so SwiftUI never re-applies it over the seam's detent; it only shows
            // if the seam can't reach the sheet.
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(!isDismissable)
    }
}

/// The tray card's surface: our own Liquid Glass (a material on iOS 18) or the flat fill, under
/// the error style's red fade.
///
/// The sheet behind the card is clear. The seam clears the floating sheet's system glass through
/// the detent's background effect (iOS 26.1+), so the flat fill keeps a glass layer of its own
/// beneath it, as the system glass sat beneath it before; on iOS 18 a material stands in for the
/// glass.
struct TrayFill: View {

    let style: TrayStyle

    var body: some View {
        if #available(iOS 26, *) {
            let shape = ConcentricRectangle(
                uniformTopCorners: .fixed(TrayMetrics.topRadius),
                uniformBottomCorners: .concentric(minimum: .fixed(TrayMetrics.topRadius))
            )
            shape
                .fill(flat ?? .clear)
                .overlay { errorFade.clipShape(shape) }
                .background { Color.clear.glassEffect(.regular, in: shape) }
        } else {
            // The edge-attached sheet: its rounded top, and a square bottom running under the home
            // indicator.
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: TrayMetrics.edgeAttachedTopRadius,
                topTrailingRadius: TrayMetrics.edgeAttachedTopRadius,
                style: .continuous
            )
            shape
                .fill(flat ?? .clear)
                .overlay { errorFade.clipShape(shape) }
                .background(.thinMaterial, in: shape)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    /// The flat colour over the glass, or nil for glass alone.
    private var flat: Color? {
        TrayMetrics.usesGlass ? nil : Color.backgroundSecondary.opacity(TrayMetrics.flatOpacity)
    }

    /// A darker card with red fading down into it from the top edge, for the error style.
    @ViewBuilder
    private var errorFade: some View {
        if style.fadesRed {
            ZStack {
                Color.black.opacity(TrayMetrics.errorFadeDarkness)
                LinearGradient(
                    colors: [Color.bannerError.opacity(TrayMetrics.errorFadeStrength), Color.bannerError.opacity(0)],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: TrayMetrics.errorFadeLength)
                )
            }
        }
    }
}
