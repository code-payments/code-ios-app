//
//  AlertPill.swift
//  FlipcashUI
//

import SwiftUI
import UIKit
import FlipcashCore
import Observation

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
    @State private var opacity: Double = 0
    /// The banner's entrance and exit: a short drop from just above its slot, growing from slightly
    /// small and unblurring, rather than a full slide that would cross the status bar.
    @State private var lift: CGFloat = -28
    @State private var scale: CGFloat = 0.92
    @State private var blur: CGFloat = 6
    @State private var expandedHeight: CGFloat = 96
    @State private var dismissRequested = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let expandedWidth: CGFloat = 378
    private static let compactSize = CGSize(width: 236, height: 36)

    /// Always the glass banner for now: the system draws the status bar over any card grown out of the
    /// island, and no app window can cover or hide it. The island morph below is unused until that changes.
    private var island: CGRect? { nil }

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
        return Color.clear
            .alertGlassBackground(cornerRadius: cornerRadius)
            .overlay(alignment: .top) {
                ZStack {
                    compactContent(content).opacity(phase == .compact ? 1 : 0)
                    expandedContent(content)
                        .opacity(textVisible && phase == .expanded ? 1 : 0)
                        .animation(.smooth(duration: 0.15), value: presented.revision)
                        .frame(width: expandedWidth, alignment: .top)
                }
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale, anchor: .top)
            .blur(radius: blur)
            .opacity(opacity)
            .offset(y: restingY + lift + dragResistance)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { controller.pillFrame = $0 }
            .contentShape(Rectangle())
            .onTapGesture { dismiss(thenTap: true) }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { dragOffset = $0.translation.height }
                    .onEnded { value in
                        if value.translation.height < -20 || value.predictedEndTranslation.height < -60 {
                            dismiss(thenTap: false)
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragOffset = 0 }
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(content.title). \(content.subtitle)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Dismiss") { dismiss(thenTap: false) }
    }

    /// Follows an upward drag one to one and resists a downward one, so the banner feels held in place.
    private var dragResistance: CGFloat {
        dragOffset < 0 ? dragOffset : 10 * log1p(dragOffset / 10)
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
            return safeAreaTop + 4
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
                Text(text).font(.appTextSmall).foregroundStyle(Color.textSuccess)
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
            // Left empty over the island: another app's Live Activity in it draws over anything the
            // pill puts in this row. The banner sits below the status bar and needs no gap.
            if island != nil {
                Color.clear.frame(height: 16)
            }

            HStack(spacing: 12) {
                avatars(content.avatars)
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.topRow)
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Text(content.title)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if !content.subtitle.isEmpty {
                        Text(content.subtitle)
                            .font(.appTextCaption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing(content.trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func avatars(_ avatars: [AlertPillContent.Avatar]) -> some View {
        if avatars.count > 1 {
            // Smaller and overlapped less than a single avatar, with the first reactor on top.
            HStack(spacing: -10) {
                ForEach(Array(avatars.prefix(3).enumerated()), id: \.offset) { index, avatar in
                    AlertAvatarView(avatar: avatar, diameter: 32)
                        .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 2))
                        .zIndex(Double(-index))
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
            // The newest two; the title already counts everyone.
            Text(emojis.suffix(2).joined()).font(.system(size: 20, weight: .semibold))
                .fixedSize()
        case .amount(let text):
            Text(text).font(.appTextLarge).foregroundStyle(Color.textSuccess)
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
        let isUpdate = phase == .expanded && textVisible
        if !isUpdate {
            await open()
        } else if !reduceMotion {
            // A new reaction on the banner already up: a small bump so the change is noticed.
            withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) { scale = 1.025 }
            _ = try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { scale = 1 }
        }
        controller.playHaptic(presented.haptic, isUpdate: isUpdate)
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
        if reduceMotion {
            lift = 0
            scale = 1
            blur = 0
            withAnimation(.easeInOut(duration: 0.2)) {
                phase = .expanded
                opacity = 1
                textVisible = true
            }
            _ = try? await Task.sleep(for: .milliseconds(200))
            return
        }
        if island == nil {
            // Drops a short way into its slot with a small settle; the haptic plays as it lands.
            phase = .expanded
            textVisible = true
            withAnimation(.easeOut(duration: 0.18)) {
                opacity = 1
                blur = 0
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                lift = 0
                scale = 1
            }
            _ = try? await Task.sleep(for: .milliseconds(240))
            return
        }
        lift = 0
        scale = 1
        blur = 0
        opacity = 1
        if phase == .rest {
            withAnimation(.easeInOut(duration: 0.18)) { phase = .compact }
            guard (try? await Task.sleep(for: .milliseconds(180))) != nil else { return }
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { phase = .expanded }
        // The text waits until the height has mostly opened, so it doesn't peek out under a pill
        // that is still growing.
        withAnimation(.easeIn(duration: 0.15).delay(0.28)) { textVisible = true }
        _ = try? await Task.sleep(for: .milliseconds(430))
    }

    private func close() async {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { opacity = 0 }
            _ = try? await Task.sleep(for: .milliseconds(220))
            controller.finish(presented.id)
            return
        }
        if island == nil {
            // Lifts back the way it came, picking up from wherever a swipe left it.
            withAnimation(.easeIn(duration: 0.22)) {
                lift = -24
                scale = 0.94
                blur = 4
                opacity = 0
            }
            _ = try? await Task.sleep(for: .milliseconds(230))
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
            if let data = avatar.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            } else {
                initialText
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var initialText: some View {
        Text(avatar.initial)
            .font(.default(size: diameter * 0.4, weight: .semibold))
            .foregroundStyle(Color.black)
    }
}

/// The top-anchored half of the toast host. The pill draws in its own window, shown only while a pill
/// is up.
struct AlertPillHost: View {
    let controller: AlertPillController

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { AlertPillWindow.attach(controller) }
            .onDisappear { AlertPillWindow.detach(controller) }
    }
}

/// The pill's window: above the status bar, passing every touch through except those on the pill.
@MainActor
private enum AlertPillWindow {
    private static var window: PassthroughWindow?
    private static var attachments = 0

    static func attach(_ controller: AlertPillController) {
        attachments += 1
        guard window == nil, let scene = activeScene else { return }
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        window.controller = controller
        let host = UIHostingController(rootView: AlertPillRoot(controller: controller))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        self.window = window
        showWhilePresenting(window, controller)
    }

    /// Keeps the window hidden while no pill is up, so it never decides the status bar otherwise.
    private static func showWhilePresenting(_ window: PassthroughWindow, _ controller: AlertPillController) {
        withObservationTracking {
            window.isHidden = controller.current == nil
        } onChange: { [weak window, weak controller] in
            Task { @MainActor in
                guard let window, let controller, self.window === window else { return }
                showWhilePresenting(window, controller)
            }
        }
    }

    static func detach(_ controller: AlertPillController) {
        attachments = max(0, attachments - 1)
        guard attachments == 0 else { return }
        window?.isHidden = true
        window = nil
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

private final class PassthroughWindow: UIWindow {
    weak var controller: AlertPillController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let controller, controller.current != nil, controller.pillFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

private struct AlertPillRoot: View {
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
        .ignoresSafeArea()
    }

    /// The app window's top inset: inside an overlay that ignores the safe area a `GeometryReader`
    /// reports 0.
    private static var windowSafeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
    }
}

private extension View {

    /// The panel glass with a dark tint, so the alert reads as a solid surface over busy content.
    @ViewBuilder
    func alertGlassBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.tint(Color.black.opacity(0.55)), in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
                .background(Color.black.opacity(0.55), in: .rect(cornerRadius: cornerRadius))
        }
    }
}
