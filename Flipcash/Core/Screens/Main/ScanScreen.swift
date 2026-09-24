//
//  ScanScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-07.
//

import PhotosUI
import SwiftUI
import FlipcashUI
import FlipcashCore

/// Thin environment-reading wrapper that hands the DI containers to
/// ``ScanScreenContent``, whose `init` builds the `@State` scan view model and
/// `@Bindable` session synchronously. Mounted as the Scan tab of
/// ``HomeTabView``, which owns the app-level `router.rootSheet` host.
struct ScanScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        ScanScreenContent(container: container, sessionContainer: sessionContainer)
    }
}

private struct ScanScreenContent: View {

    @Environment(Preferences.self) private var preferences

    @Bindable private var session: Session

    @State private var viewModel: ScanViewModel

    @State private var cameraAuthorizer = CameraAuthorizer()

    @State private var pickedItem: PhotosPickerItem?
    @State private var isScanningStillImage = false
    @State private var scanTask: Task<ScanViewModel.StillImageOutcome, Never>?

    private var cameraPrompt: CameraPrompt? {
        CameraPrompt(status: cameraAuthorizer.status, cameraEnabled: preferences.cameraEnabled)
    }
    
    /// The gap between the gallery button and the tab bar it sits above.
    private static let glyphTabBarGap: CGFloat = 12

    /// How far the iOS 26 tab bar's glass platter sits in from each side. The bar's
    /// own view spans the full width and the platter inside it carries the margin,
    /// so the safe area gives no sign of it and there is no API that reports it —
    /// this is measured, and held at 21pt across the iPhone widths and OS versions
    /// it was checked on (390pt and 402pt, iOS 26.5 and 27.0).
    private static let systemTabBarSideMargin: CGFloat = 21

    /// How far the gallery button sits in from the trailing edge: whatever the tab
    /// bar below it is inset by, so the two ends line up.
    private static var glyphTrailingInset: CGFloat {
        if #available(iOS 26, *) {
            return systemTabBarSideMargin
        }
        return HomeTabView.legacyPillHorizontalMargin
    }

    /// How far the gallery button sits up from the bottom of the tab's content. The
    /// iOS 26 bar is part of the safe area, so the gap is the whole inset there;
    /// the legacy pill is an overlay that adds nothing to the safe area and has to
    /// be cleared on top of it.
    private static var glyphBottomInset: CGFloat {
        if #available(iOS 26, *) {
            return glyphTabBarGap
        }
        return glyphTabBarGap + HomeTabView.legacyPillClearance
    }

    private let sessionContainer: SessionContainer

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer) {
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session

        self.viewModel = ScanViewModel(
            container: container,
            sessionContainer: sessionContainer
        )
    }
    
    // MARK: - Body -
    
    var body: some View {
        let showControls = session.billState.bill == nil
        ZStack {
            if cameraPrompt == nil {
                cameraViewport()
                    .transition(.identity)
            }
            
            if showControls {
                // Any actionable views need to be positioned
                // in front of the BillCanvas, otherwise it
                // will swallow all touch events
                if let cameraPrompt {
                    CameraPromptView(prompt: cameraPrompt, embedded: true) {
                        performCameraPromptAction(cameraPrompt)
                    }
                    .zIndex(1)
                    .transition(.opacity)
                }

                // Outside the `cameraPrompt` branch on purpose: a photo can be scanned
                // whether or not the camera is available, so the glyph outlives the viewport.
                GalleryScanButton(selection: $pickedItem)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, Self.glyphTrailingInset)
                    .padding(.bottom, Self.glyphBottomInset)
                    .zIndex(2)
                    .transition(.opacity)
            }
        }
        // Fill the tab's full width and height. The iOS 26 native `TabView` does
        // not stretch tab content to fill, so without this the ZStack collapses to
        // its content width (the centered `CameraPromptView` at ~340pt, or the
        // camera viewport), leaving black bars down both sides of the scanner.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundMain)
        .animation(.easeInOut(duration: 0.15), value: showControls)
        .animation(.easeInOut(duration: 0.3), value: preferences.cameraEnabled)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await scanPickedItem(item) }
        }
        .overlay {
            if isScanningStillImage {
                ScanningOverlay {
                    scanTask?.cancel()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isScanningStillImage)
        .ignoresSafeArea(.keyboard)
        // Tells the app-root bill overlay the camera is behind it, so a grabbed
        // bill shows over the live camera without a scrim while the Scan tab is
        // forward. Any other surface gets the scrim.
        .onAppear { session.isScannerForeground = true }
        .onDisappear { session.isScannerForeground = false }
    }

    @ViewBuilder private func cameraViewport() -> some View {
        CameraViewport(
            session: viewModel.cameraSession,
            enableGestures: true
        )
        // Cross-fade the live preview in only once the first frame arrives, over
        // the dark placeholder — so the camera warm-up after a tab switch never
        // shows a black frame. See `ScanViewModel.isPreviewReady`.
        .opacity(viewModel.isPreviewReady ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isPreviewReady)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.configureCameraSession()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
    }
    
    /// Loads the picked image and scans it, reporting the outcome through the app's dialog.
    ///
    /// The overlay is blocking for the length of the search, so the idle timer goes with it:
    /// there is nothing to touch while the ladder runs, and the screen dimming mid-search
    /// would read as the app having stalled.
    private func scanPickedItem(_ item: PhotosPickerItem) async {
        isScanningStillImage = true
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            isScanningStillImage = false
            scanTask = nil
            pickedItem = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }

        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)?.cgImage
        else {
            session.dialogItem = .noCodeFound
            return
        }

        let task = Task { await viewModel.scanStillImage(image) }
        scanTask = task

        switch await task.value {
        case .handled:
            break
        case .nothingFound:
            session.dialogItem = .noCodeFound
        case .cashCodeNotLive:
            session.dialogItem = .cashCodeNotLive
        }
    }

    private func performCameraPromptAction(_ prompt: CameraPrompt) {
        switch prompt {
        case .requestPermission:
            Task {
                try await cameraAuthorizer.authorize()
            }
        case .openSettings:
            URL.openSettings()
        case .startCamera:
            preferences.cameraEnabled.toggle()
        }
    }

}

/// A blocking, cancellable overlay for the duration of a still-image search.
///
/// Blocking on purpose: the search can take seconds, and a half-scanned photo is not a
/// state worth showing. Cancellable for the same reason.
private struct ScanningOverlay: View {

    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)

                Text("Looking for a code\u{2026}")
                    .foregroundStyle(.white)

                Button("Cancel", action: onCancel)
                    .foregroundStyle(.white)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Dialogs -

private extension DialogItem {

    /// Also what a refused route reports. Someone who has been sent a login QR learns
    /// nothing from this about why it was refused, which is the point.
    static var noCodeFound: DialogItem {
        .info(
            title: "No Code Found",
            subtitle: "We couldn't find a code in that photo."
        )
    }

    static var cashCodeNotLive: DialogItem {
        .info(
            title: "Cash Code Isn't Live",
            subtitle: "That cash code isn't live any more. Ask them to show it on their screen while you scan."
        )
    }
}
