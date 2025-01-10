//
//  RoomNumber.swift
//  FlipchatServices
//
//  Created by Dima Bart on 2025-01-10.
//

import Foundation

extension BinaryInteger {
    public var formattedRoomNumber: String {
        "Room \(self.formattedRoomNumberShort)"
    }
    public var formattedRoomNumberShort: String {
        "#\(self)"
    }
}
