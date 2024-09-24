//
//  Reachability.swift
//  Code
//
//  Created by Dima Bart on 2022-08-16.
//

import Foundation
import Network

@MainActor
public class Reachability: ObservableObject {
    
    @Published private(set) var status: Status = .offline
    
    private let monitor = NWPathMonitor()
    
    // MARK: - Init -
    
    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.update(path: path)
            }
        }
        
        monitor.start(queue: .main)
    }
    
    private func update(path: NWPath) {
        if path.status == .satisfied {
            status = .online
        } else {
            status = .offline
        }
    }
}

// MARK: - Status -

extension Reachability {
    public enum Status {
        case online
        case offline
    }
}

extension Reachability {
    static let mock: Reachability = Reachability()
}
