//
//  HistoryController.swift
//  Code
//
//  Created by Dima Bart on 2021-07-13.
//

import Foundation
import CodeServices

@MainActor
class HistoryController: ObservableObject {
    
    @Published private(set) var hasFetchedTransactions: Bool = false
    
    @Published private(set) var transactions: [HistoricalTransaction] = []
    
    @Published private(set) var chats: [Chat] = []
    
    @Published private(set) var unreadCount: Int = 0
    
    private let client: Client
    private let owner: KeyPair
    
    private let pageSize: Int = 100
    
    // MARK: - Init -
    
    init(client: Client, owner: KeyPair) {
        self.client = client
        self.owner = owner
        
        NotificationCenter.default.addObserver(forName: .pushNotificationReceived, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.pushNotificationReceived()
            }
        }
    }
    
    deinit {
        trace(.warning, components: "Deallocating HistoryController")
    }
    
    // MARK: - Fetch -
    
    func fetchDelta() {
        // Transactions are displayed in reverse order
        guard let latestTransaction = transactions.first else {
            fetchAll()
            return
        }
        
        Task {
            let delta = try await fetchAllTransactions(after: latestTransaction.id)
            transactions.append(contentsOf: delta)
            transactions = transactions.sortedByDateDescending()
            hasFetchedTransactions = true
        }
    }
    
    func fetchAll() {
        Task {
            transactions = try await fetchAllTransactions()
            hasFetchedTransactions = true
        }
    }
    
    func fetchChats() {
        Task {
            try await fetchAllChats()
        }
    }
    
    private func fetchAllChats() async throws {
        chats = try await fetchChats()
        computeUnreadCount()
        
        hasFetchedTransactions = true
    }
    
    private func computeUnreadCount() {
        unreadCount = computeUnreadCount(for: chats)
    }
    
    @CronActor
    private func fetchAllTransactions(after id: ID? = nil) async throws -> [HistoricalTransaction] {
        var container: [HistoricalTransaction] = []
        
        var currentID: ID? = id
        while true {
            let transactions = try await client.fetchPaymentHistory(owner: owner, after: currentID, pageSize: pageSize)
            guard !transactions.isEmpty else {
                break
            }
            
            container.append(contentsOf: transactions)
            currentID = transactions.last!.id
        }
        
        return container.sortedByDateDescending()
    }
    
    // MARK: - Chats -
    
    func advanceReadPointer(for chat: Chat) async throws {
        if let lastMessage = chat.messages.last {
            try await client.advancePointer(
                chatID: chat.id,
                to: lastMessage.id,
                owner: owner
            )
            
            let chatIndex = chats.firstIndex { $0.id == chat.id }
            if let chatIndex {
                chats[chatIndex] = chats[chatIndex].resettingUnreadCount()
            }
            
            computeUnreadCount()
        }
    }
    
    @CronActor
    private func fetchChats() async throws -> [Chat] {
        let chats = try await client.fetchChats(owner: owner)
        
        var container: [Chat] = []
        
        await withTaskGroup(of: (Chat, [Chat.Message]).self) { group in
            chats.forEach { chat in
                group.addTask {
                    do {
                        let messages = try await self.client.fetchMessages(chatID: chat.id, owner: self.owner).sorted { lhs, rhs in
                            lhs.date < rhs.date // Desc
                        }
                        
                        return (chat, messages)
                    } catch {
                        return (chat, [])
                    }
                }
            }
            
            for await (chat, messages) in group {
                var completeChat = chat
                completeChat.messages = messages
                container.append(completeChat)
            }
        }
        
        return container.sorted { lhs, rhs in
            let leftDate  = lhs.messages.last?.date
            let rightDate = rhs.messages.last?.date
            
            if let leftDate, let rightDate {
                return leftDate > rightDate
            } else if leftDate != nil {
                return true
            } else if rightDate != nil {
                return false
            } else {
                return false
            }
        }
    }
    
    private func computeUnreadCount(for chats: [Chat]) -> Int {
        chats.reduce(into: 0) { result, chat in
            result = result + chat.unreadCount
        }
    }
    
    // MARK: - Notifications -
    
    func pushNotificationReceived() {
        fetchDelta()
    }
}

// MARK: - HistoricalTransaction Array -

private extension Array where Element == HistoricalTransaction {
    func sortedByDateDescending() -> [Element] {
        sorted {
            $0.date > $1.date
        }
    }
}

// MARK: - Mock -

extension HistoryController {
    static let mock = HistoryController(
        client: .mock,
        owner: KeyAccount.mock.owner
    )
}
