//
//  ScanScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-07.
//

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

    private var cameraPrompt: CameraPrompt? {
        CameraPrompt(status: cameraAuthorizer.status, cameraEnabled: preferences.cameraEnabled)
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
