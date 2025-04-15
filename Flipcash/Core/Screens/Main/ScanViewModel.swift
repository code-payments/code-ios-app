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
    
    private let client: Client
    
    @Published var billState: BillState = .default()
    @Published var presentationState: PresentationState = .hidden(.slide)
    
    private var isTransactionInProgress: Bool = false
    
    private var scannedRendezvous: Set<PublicKey> = []
    private var cancellables: Set<AnyCancellable> = []
    
    private var canPresentBill: Bool {
        billState.bill == nil
    }
    
    private var scanOperation: ScanCashOperation?
    
    // MARK: - Init -
    
    init(container: Container) {
        self.cameraSession = container.cameraSession
        self.client = container.client
        
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
        guard canPresentBill else {
            trace(.warning, components: "Can't initiate send.")
            return
        }
        
        guard !scannedRendezvous.contains(payload.rendezvous.publicKey) else {
            trace(.warning, components: "Nonce previously received: \(payload.nonce.hexString())")
            return
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
            didScanCash(payload)
        }
    }
    
    private func didScanCash(_ payload: CashCode.Payload) {
        print("Scanned: \(payload.fiat!.formatted(suffix: nil)) \(payload.fiat!.currencyCode)")
        
        // TODO: Replace with actual account public key
        let owner = KeyPair.generate()!
        
        guard scanOperation == nil else {
            return
        }
        
        let operation = ScanCashOperation(
            client: client,
            owner: owner,
            payload: payload
        )
        
        scanOperation = operation
        Task {
            defer {
                scanOperation = nil
            }
            
            do {
                let metadata = try await operation.start()
                // TODO: self.showBill(metadata)
                
            } catch ScanCashOperation.Error.noOpenStreamForRendezvous {
                // Do not remove the nonce from received pool
//                showCashExpiredError()
                
            } catch {
                scannedRendezvous.remove(payload.rendezvous.publicKey)
            }
            
            // Update balance
        }
    }
}
