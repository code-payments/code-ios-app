//
//  Grinder.swift
//  CodeGrind
//
//  Created by Dima Bart on 2022-03-06.
//

import SwiftUI
import CodeServices

class Grinder: ObservableObject {
    
    @Published private(set) var matches: [Match] = []
    
    @Published private(set) var isRunning: Bool = false
    
    @Published private(set) var totalCount = 0
    
    @Published private(set) var hashRate = 0 // Keys per hour
    
    private let perSection = 1_000
    private let queue: DispatchQueue
    
    private var startDate: Date?
    
    // MARK: - Init -
    
    init() {
        self.queue = DispatchQueue(
            label: "com.code.grindQueue",
            qos: .default,
            attributes: [.concurrent],
            autoreleaseFrequency: .workItem
        )
    }
    
    func grindMulticore(term: String, type: MatchType, path: Derive.Path, ignoringCase: Bool) {
        reset()
        isRunning = true
        startDate = .now()
        
        queue.async {
            DispatchQueue.concurrentPerform(iterations: ProcessInfo.processInfo.processorCount * 3) { _ in
                self.grind(term: term, type: type, path: path, ignoringCase: ignoringCase) { match, section in
                    DispatchQueue.main.async {
                        if let match = match {
                            self.matches.append(match)
                        }
                        
                        if let section = section {
                            self.totalCount += section.count
                            self.updateHashRate()
//                            print("Scanned \(self.totalCount), Time since last: \(section.delta) sec")
                        }
                    }
                    
                    return self.isRunning ? .continue : .exit
                }
            }
        }
    }
    
    private func grind(term: String, type: MatchType, path: Derive.Path, ignoringCase: Bool, iteration: (Match?, Section?) -> Action) {
        print("Starting grind...")
        var sectionStart = Date()
        var sectionCount = 0
        repeat {
            var section: Section? = nil
            
            if sectionCount >= self.perSection {
                section = Section(
                    delta: Date().timeIntervalSince1970 - sectionStart.timeIntervalSince1970,
                    count: sectionCount
                )
                
                sectionStart = Date()
                sectionCount = 0
            }
            
            let mnemonic  = MnemonicPhrase.generate(.words12)
            let keyPair   = KeyPair(mnemonic: mnemonic, path: path, password: "")
            let publicKey = keyPair.publicKey.base58
            
            let action: Action
            
            if type.doesMatch(publicKey: publicKey, term: term, ignoringCase: ignoringCase) {
                action = iteration(
                    Match(
                        mnemonic: mnemonic,
                        keyPair: keyPair
                    ),
                    section
                )
                
            } else {
                action = iteration(nil, section)
            }
            
            sectionCount += 1
            
            switch action {
            case .continue:
                continue
            case .exit:
                print("Stopped grind.")
                return
            }
        } while true
    }
    
    func cancel() {
        isRunning = false
    }
    
    func reset() {
        totalCount = 0
        matches.removeAll()
    }
    
    private func updateHashRate() {
        guard let startDate = startDate else {
            return
        }

        let deltaSeconds = Date.now().timeIntervalSince1970 - startDate.timeIntervalSince1970
        let ratePerMinute = Double(totalCount) / deltaSeconds * 60.0
        hashRate = Int(ratePerMinute * 60.0)
    }
}

extension Grinder {
    struct Match: Identifiable {
        
        var mnemonic: MnemonicPhrase
        var keyPair: KeyPair
        
        var id: PublicKey {
            keyPair.publicKey
        }
    }
}

extension Grinder {
    enum MatchType {
        case prefix
        case suffix
        
        func doesMatch(publicKey: String, term: String, ignoringCase: Bool = false) -> Bool {
            let string = ignoringCase ? publicKey.lowercased() : publicKey
            switch self {
            case .suffix:
                return string.hasSuffix(term)
            case .prefix:
                return string.hasPrefix(term)
            }
        }
    }
}

private extension Grinder {
    enum Action {
        case `continue`
        case exit
    }
}

private extension Grinder {
    struct Section {
        var delta: TimeInterval
        var count: Int
    }
}

extension Derive.Path {
    static let solana  = Derive.Path("m/44'/501'/0'/0'")!
}
