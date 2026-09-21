//
//  ScanViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-04-08.
//

import CoreGraphics
import Foundation
import FlipcashUI
import FlipcashCore
import Combine

private let logger = Logger(label: "flipcash.scan")

@Observable
class ScanViewModel {

    private static let qrCooldownInterval: TimeInterval = 5.0

    @ObservationIgnored let cameraSession: CameraSession<CodeExtractor>

    /// `true` once the capture session has delivered its first frame. Drives the
    /// preview's cross-fade so the camera warm-up (after a tab switch) shows the
    /// dark placeholder instead of popping in from black. `extraction` fires once
    /// per frame, so its first emission is the first rendered frame.
    private(set) var isPreviewReady: Bool = false

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let tipFlow: TipFlow

    @ObservationIgnored private var scannedRendezvous: Set<PublicKey> = []
    @ObservationIgnored private var scannedQRCodes: Set<String> = []
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer) {
        self.session = sessionContainer.session
        self.tipFlow = sessionContainer.tipFlow
        self.cameraSession = container.cameraSession

        registerCodeExtractorObserver()
    }
    
    // MARK: - CameraSession -
    
    func configureCameraSession() {
        do {
            try cameraSession.configureDevices()
            cameraSession.start()
        } catch {
            logger.error("Error configuring camera session", metadata: ["error": "\(error)"])
        }
    }
    
    func stopCamera() {
        cameraSession.stop()
        // Re-arm the cross-fade so a subsequent start fades in on its first frame.
        isPreviewReady = false
    }
    
    // MARK: - Scanning -
    
    private func registerCodeExtractorObserver() {
        cameraSession.extraction.sink { [weak self] payload in
            guard let self else { return }
            // First frame in — reveal the preview.
            if !self.isPreviewReady {
                self.isPreviewReady = true
            }
            if let payload = payload {
                self.didScan(payload)
            }
        }
        .store(in: &cancellables)

        cameraSession.metadataExtraction.sink { [weak self] string in
            self?.didScanQR(string)
        }
        .store(in: &cancellables)
    }
    
    private func didScan(_ code: ScannedCode) {
        guard !session.isShowingBill else {
            return
        }

        guard !session.isProcessingScan else {
            return
        }

        switch code {
        case .cash(let payload):
            didScanCash(payload)
        case .tip(let payload):
            Analytics.track(event: Analytics.TipCardEvent.scanned)
            tipFlow.begin(userID: payload.userID)
        }
    }

    private func didScanCash(_ payload: CashCode.Payload) {
        guard !scannedRendezvous.contains(payload.rendezvous.publicKey) else {
            return
        }

        if BetaFlags.shared.hasEnabled(.vibrateOnScan) {
            Haptics.tap()
        }

        scannedRendezvous.insert(payload.rendezvous.publicKey)

        logger.debug("Scanned payload", metadata: [
            "kind":       "\(payload.kind)",
            "nonce":      "\(payload.nonce.hexString())",
            "rendezvous": "\(payload.rendezvous.publicKey.base58)",
        ])

        switch payload.kind {
        case .cash, .cashMulticurrency:
            session.receiveCash(payload) { [weak self] result in
                switch result {
                case .success:
                    break
                case .noStream, .failed:
                    self?.scannedRendezvous.remove(payload.rendezvous.publicKey)
                }
            }
        }
    }

    // MARK: - QR Scanning -

    /// Returns whether a URL is eligible for QR code scanning.
    ///
    /// Two gates. The host comes first: a QR code is read off whatever the camera is pointed at,
    /// so nothing vouched for its host, and `Route` matches on path alone — ungated, a Discord
    /// invite scans as a handle and a stranger's `/c/#/e=…` scans as a cash link.
    ///
    /// Then the route: an allowlist of `.cash`, `.token`, `.tip`, and `.username`, with every
    /// other route refused by name — including the security-sensitive `.login` and
    /// `.verifyEmail`. A new `Route.Path` case is refused until someone adds it here.
    ///
    /// Every entry point answers to this, not just the camera: a gallery image is one the
    /// user chose, and a shared image is one somebody else sent them.
    nonisolated static func canScanQR(url: URL) -> Bool {
        guard Route.isFlipcashLink(url), let route = Route(url: url) else {
            return false
        }

        switch route.path {
        // `.username` is the vanity form of `.tip` — the same tipcard link, so
        // a printed handle QR scans where the user id one already does.
        case .cash, .token, .tip, .username:
            return true
        case .login, .verifyEmail, .chat, .chatSendCash, .give, .balance, .discover, .unknown:
            return false
        }
    }

    private func didScanQR(_ string: String) {
        guard !session.isShowingBill else {
            return
        }

        guard !session.isProcessingScan else {
            return
        }

        guard !scannedQRCodes.contains(string) else {
            return
        }

        guard let url = URL(string: string) else {
            return
        }

        guard Self.canScanQR(url: url) else {
            return
        }

        if BetaFlags.shared.hasEnabled(.vibrateOnScan) {
            Haptics.tap()
        }

        scannedQRCodes.insert(string)

        // Remove from dedup set after cooldown to allow re-scanning
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.qrCooldownInterval) { [weak self] in
            self?.scannedQRCodes.remove(string)
        }

        logger.debug("QR code scanned", metadata: ["url": "\(url.sanitizedForAnalytics)"])

        NotificationCenter.default.post(
            name: .qrDeepLinkReceived,
            object: nil,
            userInfo: ["url": url]
        )
    }
    // MARK: - Still Images -

    /// What a still-image scan ended up doing, for the UI to report.
    enum StillImageOutcome: Equatable {
        case handled
        case nothingFound
        /// A cash code decoded, but the giver's device is not streaming. Almost always a
        /// screenshot of a bill that is no longer on anyone's screen.
        case cashCodeNotLive
    }

    /// Scans a picked or shared image and routes whatever it finds the way the camera would.
    ///
    /// The camera's dedup does not apply. `scannedQRCodes` and `scannedRendezvous` exist
    /// because a capture session sees the same code sixty times a second; picking the same
    /// image twice is a deliberate act and has to scan twice.
    func scanStillImage(_ image: CGImage) async -> StillImageOutcome {
        guard !session.isShowingBill, !session.isProcessingScan else {
            return .nothingFound
        }

        Analytics.galleryScanStarted()

        let started = Date()
        let outcome = await GalleryScanner().scan(image)
        let elapsed = Date().timeIntervalSince(started)

        switch outcome {
        case .code(let code, let match):
            Analytics.galleryScanFoundCode(
                tier: match.tier.rawValue,
                zoom: Double(match.zoom),
                elapsed: elapsed
            )
            return await handle(code)

        case .url(let url):
            guard Self.canScanQR(url: url) else {
                Analytics.galleryScanFoundNothing(reason: .routeRefused, elapsed: elapsed)
                // Deliberately indistinguishable from "nothing found". Someone who has been
                // sent a login QR learns nothing about why it was refused.
                return .nothingFound
            }

            Analytics.galleryScanFoundQR(elapsed: elapsed)

            logger.debug("QR code scanned from still image", metadata: [
                "url": "\(url.sanitizedForAnalytics)",
            ])

            NotificationCenter.default.post(
                name: .qrDeepLinkReceived,
                object: nil,
                userInfo: ["url": url]
            )
            return .handled

        case .nothingFound:
            Analytics.galleryScanFoundNothing(reason: .exhausted, elapsed: elapsed)
            return .nothingFound

        case .cancelled:
            Analytics.galleryScanFoundNothing(reason: .cancelled, elapsed: elapsed)
            return .nothingFound
        }
    }

    private func handle(_ code: ScannedCode) async -> StillImageOutcome {
        switch code {
        case .tip(let payload):
            Analytics.track(event: Analytics.TipCardEvent.scanned)
            tipFlow.begin(userID: payload.userID)
            return .handled

        case .cash(let payload):
            // Checked again here, not only on the way in: the search takes seconds, and a
            // camera scan that starts inside that window makes `receiveCash` return on its
            // own `scanOperation == nil` guard without ever calling the completion — the one
            // path that would leave this continuation suspended, and the overlay with it.
            guard !session.isProcessingScan else {
                return .nothingFound
            }

            return await withCheckedContinuation { continuation in
                session.receiveCash(payload) { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: .handled)
                    case .noStream:
                        // The one thing a still image genuinely cannot do. Its own message,
                        // because the generic failure reads as a bug.
                        continuation.resume(returning: .cashCodeNotLive)
                    case .failed:
                        continuation.resume(returning: .nothingFound)
                    }
                }
            }
        }
    }
}
