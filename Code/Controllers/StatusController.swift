//
//  StatusController.swift
//  Code
//
//  Created by Dima Bart on 2021-11-24.
//

import Foundation
import CodeServices

class StatusController: ObservableObject {
    
    @Published private(set) var status: Status = .default
    @Published private(set) var requiresUpgrade: Bool = false
    
    private var poller: Poller!
    
    private let decoder = JSONDecoder()
    
    // MARK: - Init -
    
    init() {
        poller = Poller(seconds: 10, fireImmediately: true) { [weak self] in
            self?.fetchLatestStatus()
        }
    }
    
    // MARK: - Fetch -
    
    func fetchLatestStatus() {
        Task {
            let status = try await fetchStatus()
            await update(status)
        }
    }
    
    @CronActor
    private func fetchStatus() async throws -> Status {
        try await withCheckedThrowingContinuation { c in
            let task = URLSession.shared.dataTask(with: .status) { data, response, error in
                guard
                    let data = data,
                    let status = try? JSONDecoder().decode(Status.self, from: data)
                else {
                    trace(.failure, components: "Failed to fetch status: \(error?.localizedDescription ?? "nil")")
                    c.resume(throwing: ErrorGeneric.unknown)
                    return
                }
                
                c.resume(returning: status)
            }
            
            task.resume()
        }
    }
    
    @MainActor
    private func update(_ status: Status) {
        self.status = status
        updateUpgradeStatus()
    }
    
    private func updateUpgradeStatus() {
        let currentVersion = Int(AppMeta.build) ?? 0
        self.requiresUpgrade = currentVersion < status.minimumClientVersion
    }
}

struct Status: Codable {
    let code: Code
    let minimumClientVersion: Int
}

extension Status {
    enum Code: String, Codable {
        case ok
        case down
    }
}

private extension Status {
    static let `default` = Status(code: .ok, minimumClientVersion: 0)
}
