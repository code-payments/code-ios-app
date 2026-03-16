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

@MainActor @Observable
class ScanViewModel {

    @ObservationIgnored let cameraSession: CameraSession<CodeExtractor>

    @ObservationIgnored private let session: Session

    @ObservationIgnored private var scannedRendezvous: Set<PublicKey> = []
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
            trace(.failure, components: "Error configuring camera session: \(error)")
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
        
        trace(.note, components:
              "Kind: \(payload.kind)",
              "Nonce: \(payload.nonce.hexString())",
              "Rendezvous: \(payload.rendezvous.publicKey.base58)"
        )
        
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
}
