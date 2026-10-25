//
//  AlertPill.swift
//  FlipcashUI
//

import SwiftUI
import UIKit
import FlipcashCore

/// The in-app reaction and boost alert: a black capsule drawn over the Dynamic Island that grows into
/// a card, or a banner dropped from the top on a phone with no island. Sizes are the `Alert/Reaction
/// pill` component's: rest 126x37, compact 236x36, expanded up to 378 wide.
///
/// Timings are the spec's starting values, not tuned on a device: width grows over 180 ms, the height
/// springs open (response 0.42, damping 0.78), then after the hold the text fades in 120 ms, the
/// height collapses over 260 ms and the width returns to the island over 200 ms. With Reduce Motion
/// the expanded card crossfades in place for the same hold.
struct AlertPill: View {

    let controller: AlertPillController
    let presented: AlertPillController.Presented
    /// The top safe-area inset of the window, which the host's own geometry cannot report because it
    /// draws under the safe area.
    let safeAreaTop: CGFloat
    let screenWidth: CGFloat

    private enum Phase { case rest, compact, expanded }

    @State private var phase: Phase = .rest
    @State private var textVisible = false
    @State private var opacity: Double = 1
    @State private var expandedHeight: CGFloat = 96
    @State private var dismissRequested = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let expandedWidth: CGFloat = 378
    private static let compactSize = CGSize(width: 236, height: 36)

    private var island: CGRect? { IslandGeometry.island(safeAreaTop: safeAreaTop, screenWidth: screenWidth) }

    private var expandedWidth: CGFloat { min(Self.expandedWidth, screenWidth - 24) }

    var body: some View {
        let content = presented.content
        ZStack(alignment: .top) {
            shape(for: content)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(sizingProbe(content))
        .task(id: presented.revision) { await run() }
    }

    // MARK: - Shape -

    private func shape(for content: AlertPillContent) -> some View {
        let size = frameSize
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black)
            .overlay(alignment: .top) {
                ZStack {
                    compactContent(content).opacity(phase == .compact ? 1 : 0)
                    expandedContent(content)
                        .opacity(textVisible && phase == .expanded ? 1 : 0)
                        .frame(width: expandedWidth, alignment: .top)
                }
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .frame(width: size.width, height: size.height)
            .opacity(opacity)
            .offset(y: restingY + min(0, dragOffset))
            .contentShape(Rectangle())
            .onTapGesture { dismiss(thenTap: true) }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { dragOffset = min(0, $0.translation.height) }
                    .onEnded { value in
                        if value.translation.height < -20 || value.predictedEndTranslation.height < -60 {
                            dismiss(thenTap: false)
                        } else {
                            withAnimation(.spring(duration: 0.25)) { dragOffset = 0 }
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(content.title). \(content.subtitle)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Dismiss") { dismiss(thenTap: false) }
    }

    private var frameSize: CGSize {
        if island == nil {
            return CGSize(width: expandedWidth, height: expandedHeight)
        }
        if reduceMotion { return CGSize(width: expandedWidth, height: expandedHeight) }
        switch phase {
        case .rest: return island?.size ?? .zero
        case .compact: return Self.compactSize
        case .expanded: return CGSize(width: expandedWidth, height: expandedHeight)
        }
    }

    private var cornerRadius: CGFloat {
        if island == nil || reduceMotion { return 28 }
        switch phase {
        case .rest, .compact: return 18
        case .expanded: return 44
        }
    }

    /// Where the card's top edge sits. A banner starts above the screen and drops in.
    private var restingY: CGFloat {
        guard let island else {
            return phase == .rest ? -(expandedHeight + safeAreaTop) : safeAreaTop + 4
        }
        switch phase {
        case .rest, .compact where !reduceMotion:
            return island.midY - frameSize.height / 2
        default:
            return island.minY
        }
    }

    // MARK: - Content -

    private func compactContent(_ content: AlertPillContent) -> some View {
        HStack(spacing: 0) {
            AlertAvatarView(avatar: content.avatars.last ?? .init(initial: "?", seed: 0), diameter: 24)
            Spacer(minLength: 8)
            switch content.trailing {
            case .amount(let text):
                Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.alertGreen)
            case .emoji(let emoji):
                Text(emoji).font(.system(size: 18, weight: .semibold))
            case .emojis(let emojis):
                Text(emojis.joined()).font(.system(size: 18, weight: .semibold))
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(width: Self.compactSize.width, height: Self.compactSize.height)
    }

    private func expandedContent(_ content: AlertPillContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(content.topRow)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("now")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.5))

            HStack(spacing: 12) {
                avatars(content.avatars)
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textMain)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !content.subtitle.isEmpty {
                        Text(content.subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing(content.trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func avatars(_ avatars: [AlertPillContent.Avatar]) -> some View {
        if avatars.count > 1 {
            HStack(spacing: -14) {
                ForEach(Array(avatars.prefix(3).enumerated()), id: \.offset) { _, avatar in
                    AlertAvatarView(avatar: avatar, diameter: 40)
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                }
            }
        } else {
            AlertAvatarView(avatar: avatars.first ?? .init(initial: "?", seed: 0), diameter: 40)
        }
    }

    @ViewBuilder
    private func trailing(_ trailing: AlertPillContent.Trailing) -> some View {
        switch trailing {
        case .emoji(let emoji):
            Text(emoji).font(.system(size: 30, weight: .semibold))
        case .emojis(let emojis):
            Text(emojis.joined()).font(.system(size: 20, weight: .semibold))
        case .amount(let text):
            Text(text).font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.alertGreen)
        }
    }

    /// Lays the expanded card out invisibly to learn the height the open pill needs.
    private func sizingProbe(_ content: AlertPillContent) -> some View {
        expandedContent(content)
            .frame(width: expandedWidth)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { expandedHeight = $0 }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Timeline -

    private func run() async {
        dismissRequested = false
        if phase != .expanded || !textVisible {
            await open()
        }
        // Wait out the hold in short steps so a swipe or tap can end it early.
        let step = Duration.milliseconds(50)
        var waited = Duration.zero
        while waited < presented.hold, !dismissRequested {
            guard (try? await Task.sleep(for: step)) != nil else { return }
            waited += step
        }
        await close()
    }

    private func open() async {
        if island == nil || reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                phase = .expanded
                opacity = 1
                textVisible = true
            }
            if island == nil { return }
            return
        }
        if phase == .rest {
            withAnimation(.easeInOut(duration: 0.18)) { phase = .compact }
            guard (try? await Task.sleep(for: .milliseconds(180))) != nil else { return }
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { phase = .expanded }
        withAnimation(.easeIn(duration: 0.18).delay(0.1)) { textVisible = true }
        _ = try? await Task.sleep(for: .milliseconds(240))
    }

    private func close() async {
        if island == nil || reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                opacity = 0
                textVisible = false
            }
            _ = try? await Task.sleep(for: .milliseconds(220))
            controller.finish(presented.id)
            return
        }
        withAnimation(.easeOut(duration: 0.12)) { textVisible = false }
        guard (try? await Task.sleep(for: .milliseconds(120))) != nil else { return }
        withAnimation(.easeInOut(duration: 0.26)) { phase = .compact }
        guard (try? await Task.sleep(for: .milliseconds(260))) != nil else { return }
        withAnimation(.easeInOut(duration: 0.2)) { phase = .rest }
        guard (try? await Task.sleep(for: .milliseconds(200))) != nil else { return }
        controller.finish(presented.id)
    }

    private func dismiss(thenTap: Bool) {
        if thenTap { presented.onTap() }
        dismissRequested = true
    }
}

private struct AlertAvatarView: View {
    let avatar: AlertPillContent.Avatar
    let diameter: CGFloat

    private static let palette: [Color] = [
        Color(r: 232, g: 153, b: 107), Color(r: 115, g: 158, b: 242), Color(r: 140, g: 209, b: 140),
        Color(r: 214, g: 140, b: 200), Color(r: 240, g: 200, b: 100),
    ]

    var body: some View {
        ZStack {
            Circle().fill(Self.palette[abs(avatar.seed) % Self.palette.count])
            if let url = avatar.imageURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { initialText }
                    .clipShape(Circle())
            } else {
                initialText
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var initialText: some View {
        Text(avatar.initial)
            .font(.system(size: diameter * 0.4, weight: .semibold))
            .foregroundStyle(Color.black)
    }
}

private extension Color {
    /// The boost amount's green, `#34C759` in the component.
    static var alertGreen: Color { Color(r: 52, g: 199, b: 89) }
}

/// The top-anchored half of the toast host.
struct AlertPillHost: View {
    let controller: AlertPillController

    var body: some View {
        GeometryReader { proxy in
            if let presented = controller.current {
                AlertPill(
                    controller: controller,
                    presented: presented,
                    safeAreaTop: Self.windowSafeAreaTop,
                    screenWidth: proxy.size.width
                )
                .id(presented.id)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .allowsHitTesting(controller.current != nil)
    }

    /// The window's top inset: inside an overlay that ignores the safe area a `GeometryReader` reports 0.
    private static var windowSafeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }
}
