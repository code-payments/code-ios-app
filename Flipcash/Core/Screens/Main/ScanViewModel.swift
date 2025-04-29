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
    private let historyController: HistoryController
    private let client: Client
    
    @Published var billState: BillState = .default()
    @Published var presentationState: PresentationState = .hidden(.slide)
    
    @Published var valuation: BillValuation? = nil
    @Published var toast: Toast? = nil
    
    private var isTransactionInProgress: Bool = false
    
    private var scannedRendezvous: Set<PublicKey> = []
    private var cancellables: Set<AnyCancellable> = []
    
    private var canPresentBill: Bool {
        billState.bill == nil
    }
    
    private var scanOperation: ScanCashOperation?
    private var sendOperation: SendCashOperation?
    
    // MARK: - Init -
    
    init(container: Container, sessionContainer: SessionContainer) {
        self.session = sessionContainer.session
        self.historyController = sessionContainer.historyController
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
        print("Scanned: \(payload.fiat.formatted(suffix: nil)) \(payload.fiat.currencyCode)")
        
        guard scanOperation == nil else {
            return
        }
        
        let operation = ScanCashOperation(
            client: client,
            historyController: historyController,
            owner: session.owner,
            payload: payload
        )
        
        scanOperation = operation
        Task {
            defer {
                scanOperation = nil
            }
            
            do {
                let metadata = try await operation.start()
                showCashBill(.init(
                    kind: .cash,
                    exchangedFiat: metadata.exchangedFiat,
                    received: true
                ))
                
            } catch ScanCashOperation.Error.noOpenStreamForRendezvous {
                // Do not remove the nonce from received pool
//                showCashExpiredError()
                
            } catch {
                scannedRendezvous.remove(payload.rendezvous.publicKey)
            }
            
            // Update balance
        }
    }
    
    // MARK: - Cash -
    
    func showCashBill(_ billDescription: BillDescription) {
        let operation = SendCashOperation(
            client: client,
            owner: session.owner,
            exchangedFiat: billDescription.exchangedFiat
        )
        
        if billDescription.received {
            valuation = BillValuation(
                rendezvous: operation.payload.rendezvous.publicKey,
                exchangedFiat: billDescription.exchangedFiat
            )
        }
        
        sendOperation = operation
        presentationState = .visible(billDescription.received ? .pop : .slide)
        billState = .init(
            bill: .cash(operation.payload),
            primaryAction: .init(asset: .cancel, title: "Cancel") { [weak self] in
                self?.dismissCashBill(style: .slide)
            },
        )
        
        operation.start { [weak self] result in
            switch result {
            case .success(let success):
                self?.dismissCashBill(style: .pop)
                self?.showToast(
                    fiat: billDescription.exchangedFiat.converted,
                    isDeposit: false
                )
                
            case .failure(let failure):
                self?.dismissCashBill(style: .slide)
            }
        }
    }
    
    func dismissCashBill(style: PresentationState.Style) {
        if billState.shouldShowToast, let valuation = valuation {
            showToast(
                fiat: valuation.exchangedFiat.converted,
                isDeposit: true
            )
        }
        
        sendOperation = nil
        presentationState = .hidden(style)
        billState = .default()
        valuation = nil
    }
    
    // MARK: - Toast -
    
    private func showToast(fiat: Fiat, isDeposit: Bool, autoDismiss: Bool = true) {
        toast = .init(
            amount: fiat,
            isDeposit: isDeposit
        )
        
        if autoDismiss {
            Task {
                try await Task.delay(seconds: 3)
                toast = nil
            }
        }
    }
}

extension ScanViewModel {
    struct BillDescription {
        enum Kind {
            case cash
        }
        
        let kind: Kind
        let exchangedFiat: ExchangedFiat
        let received: Bool
        
        init(kind: Kind, exchangedFiat: ExchangedFiat, received: Bool) {
            self.kind = kind
            self.exchangedFiat = exchangedFiat
            self.received = received
        }
    }
}
