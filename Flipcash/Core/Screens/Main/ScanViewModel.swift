//
//  ScanViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-04-08.
//

import Foundation
import FlipcashUI
import FlipcashCore
import Combine

private let logger = Logger(label: "flipcash.scan")

@MainActor @Observable
class ScanViewModel {

    private static let qrCooldownInterval: TimeInterval = 5.0

    @ObservationIgnored let cameraSession: CameraSession<CodeExtractor>

    @ObservationIgnored private let session: Session

    @ObservationIgnored private var scannedRendezvous: Set<PublicKey> = []
    @ObservationIgnored private var scannedQRCodes: Set<String> = []
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    
    // MARK: - Init -
    
    init(container: Container, sessionContainer: SessionContainer) {
        self.session = sessionContainer.session
        self.cameraSession = container.cameraSession
        
        registerCodeExtractorObserver()
    }
    
    // MARK: - CameraSession -
    
    func configureCameraSession() {
        do {
            try cameraSession.configureDevices()
            cameraSession.start()
        } catch {
            logger.error("Error configuring camera session: \(error)")
        }
    }
    
    func stopCamera() {
        cameraSession.stop()
    }
    
    // MARK: - Scanning -
    
    private func registerCodeExtractorObserver() {
        cameraSession.extraction.sink { [weak self] payload in
            if let payload = payload {
                self?.didScan(payload)
            }
        }
        .store(in: &cancellables)

        cameraSession.metadataExtraction.sink { [weak self] string in
            self?.didScanQR(string)
        }
        .store(in: &cancellables)
    }
    
    private func didScan(_ payload: CashCode.Payload) {
        guard !session.isShowingBill else {
            return
        }

        guard !session.isProcessingScan else {
            return
        }

        guard !scannedRendezvous.contains(payload.rendezvous.publicKey) else {
            return
        }
        
        if BetaFlags.shared.hasEnabled(.vibrateOnScan) {
            Haptics.tap()
        }
        
//        trace(.note, components: scannedRendezvous.map { $0.base58 })
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
    /// Only `.cash` and `.token` routes are allowed; `.login` and `.verifyEmail` are blocked for security.
    nonisolated static func canScanQR(url: URL) -> Bool {
        guard let route = Route(url: url) else {
            return false
        }

        switch route.path {
        case .cash, .token:
            return true
        case .login, .verifyEmail, .unknown:
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
}
