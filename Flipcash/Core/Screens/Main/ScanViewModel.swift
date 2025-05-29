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

@MainActor
class ScanViewModel: ObservableObject {
    
    let cameraSession: CameraSession<CodeExtractor>
    
    private let session: Session
    
    private var scannedRendezvous: Set<PublicKey> = []
    private var cancellables: Set<AnyCancellable> = []
    
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
            trace(.warning, components: "Can't initiate send, bill on screen.")
            return
        }
        
        guard !scannedRendezvous.contains(payload.rendezvous.publicKey) else {
            trace(.warning, components: "Nonce previously received: \(payload.nonce.hexString())")
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
        case .cash:
            session.receiveCash(payload) { [weak self] result in
                switch result {
                case .success:
                    break
                case .noStream:
                    // Do not remove the nonce from received pool
                    break
                case .failed:
                    self?.scannedRendezvous.remove(payload.rendezvous.publicKey)
                }
            }
        }
    }
}
