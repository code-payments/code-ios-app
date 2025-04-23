//
//  Toast.swift
//  Code
//
//  Created by Dima Bart on 2025-04-22.
//

import Foundation
import FlipcashCore

struct Toast: Equatable, Hashable {
    let amount: Fiat
    let isDeposit: Bool
}
