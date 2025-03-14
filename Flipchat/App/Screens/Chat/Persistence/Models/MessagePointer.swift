//
//  MessagePointer.swift
//  Code
//
//  Created by Dima Bart on 2025-03-13.
//

import Foundation
import FlipchatServices

struct MessagePointer {
    let messageID: UUID
    let kind: Chat.Pointer.Kind
    let newUnreads: Int
}
