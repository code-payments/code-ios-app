//
//  PhoneUploadController.swift
//  Code
//
//  Created by Dima Bart.
//  Copyright © 2022 Code Inc. All rights reserved.
//

import Foundation
import CodeServices

@globalActor
struct CronActor {
    actor ActorType { }
    
    static let shared: ActorType = ActorType()
}

@CronActor
class PhoneUploadController {
    
    private let cacheName: String
    private let cacheLocation: URL
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var hashes: Set<PhoneHash> = []
    
    private let client: Client
    private let user: User
    private let owner: KeyPair
    
    // MARK: - Init -
    
    nonisolated init(client: Client, user: User, owner: KeyPair) {
        self.client = client
        self.user = user
        self.owner = owner
        self.cacheName = "com.code.uploadedPhoneNumbers.\(user.containerIdentifier)"
        self.cacheLocation = Self.cacheLocation(name: cacheName)
        
        Task {
            try await loadCachedHashes()
        }
    }
    
    private func loadCachedHashes() throws {
        set(phoneHashes: try read())
    }
    
    // MARK: - Requests -
    
    private func uploadContacts(phones: [Phone]) async throws {
        try await client.uploadContacts(containerID: user.containerID, phoneNumbers: phones, owner: owner)
    }
    
    // MARK: - Operations -
    
    private func filterForUpload(phones: [Phone]) -> [Phone] {
        Array(phones.reversed().filter { !isUploaded(phone: $0) })
    }
    
    func requiresUpload(phones: [Phone]) -> Bool {
        !filterForUpload(phones: phones).isEmpty
    }
    
    func batchUpload(phones: [Phone]) async -> Int {
        let pageSize   = 1000
        var collection = filterForUpload(phones: phones)
        var batchCount = 0
        var errorCount = 0
        var count      = 0
        
        guard collection.count > 0 else {
            return 0
        }
        
        repeat {
            let phonesToUpload = Array(collection.suffix(pageSize))
            batchCount = phonesToUpload.count
            do {
                trace(.note, components: phonesToUpload.map { $0.e164 })
                try await uploadContacts(phones: phonesToUpload)
                insert(phones: phonesToUpload)
                Task.detached {
                    try await self.write(hashes: await self.hashes)
                }
            } catch {
                let batchDescription = phonesToUpload.map { $0.e164 }.joined(separator: " ")
                errorCount += phonesToUpload.count
                trace(.failure, components: "Failed to upload batch: \(batchDescription)", "Error: \(error)")
            }
            
            collection = collection.dropLast(batchCount)
            count += 1
            
        } while batchCount >= pageSize
        
        return errorCount
    }
    
    func isUploaded(phone: Phone) -> Bool {
        let hash = PhoneHash(phone: phone)
        return hashes.contains(hash)
    }
    
    func reset() {
        hashes.removeAll()
        try? deleteCache()
    }
    
    // MARK: - Set -
    
    private func insert(phone: Phone) {
        let hash = PhoneHash(phone: phone)
        hashes.insert(hash)
    }
    
    private func insert(phones: [Phone]) {
        phones.forEach {
            insert(phone: $0)
        }
    }
    
    private func set(phoneHashes: Set<PhoneHash>) {
        trace(.success, components: "Loaded \(phoneHashes.count) phone hashes.")
        hashes = phoneHashes
    }
    
    // MARK: - IO -
    
    nonisolated private static func cacheLocation(name: String) -> URL {
        let url = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return url.appendingPathComponent(name)
    }
    
    private func read() throws -> Set<PhoneHash> {
        let data = try Data(contentsOf: cacheLocation)
        return try decoder.decode(Set<PhoneHash>.self, from: data)
    }
    
    private func write(hashes: Set<PhoneHash>) throws {
        let data = try encoder.encode(hashes)
        try data.write(to: cacheLocation)
    }
    
    private func deleteCache() throws {
        try FileManager.default.removeItem(at: cacheLocation)
    }
}

private extension User {
    var containerIdentifier: String {
        containerID.data.hexEncodedString()
    }
}

// MARK: - PhoneHash -

private struct PhoneHash: Hashable, Codable {
    
    private let hashedValue: Data
    
    init(phone: Phone) {
        self.hashedValue = SHA256.digest(phone.e164)
    }
}

// MARK: - Mock -

extension PhoneUploadController {
    static let mock = PhoneUploadController(
        client: .mock,
        user: .mock,
        owner: .mock
    )
}
