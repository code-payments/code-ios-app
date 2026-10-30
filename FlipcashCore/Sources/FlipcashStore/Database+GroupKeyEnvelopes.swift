//
//  Database+GroupKeyEnvelopes.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import SQLite

/// The database keeps each private group's key envelope as the server returned it, so the chat key
/// can be opened offline. The conversation tables' deletes remove it with the chat.
nonisolated extension Database: GroupKeyEnvelopeStore {

    public func material(for conversationID: ConversationID) throws -> GroupKeyMaterial? {
        let k = GroupKeyEnvelopeTable()
        return try reader.pluck(k.table.filter(k.conversationID == conversationID.data)).flatMap {
            GroupKeyMaterial(serialized: $0[k.envelope])
        }
    }

    public func store(_ material: GroupKeyMaterial, for conversationID: ConversationID) throws {
        let bytes = try material.serialized()
        try write { writer in
            let k = GroupKeyEnvelopeTable()
            try writer.run(
                k.table.insert(or: .replace, k.conversationID <- conversationID.data, k.envelope <- bytes)
            )
        }
    }

    public func remove(for conversationID: ConversationID) throws {
        try write { writer in
            let k = GroupKeyEnvelopeTable()
            try writer.run(k.table.filter(k.conversationID == conversationID.data).delete())
        }
    }
}
