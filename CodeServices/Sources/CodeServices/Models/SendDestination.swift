//
//  SendDestination.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum SendDestination {
    case publicKey(PublicKey)
    case phoneNumber(Phone)
}
