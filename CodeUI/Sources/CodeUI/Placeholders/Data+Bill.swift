//
//  Data+Bill.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Data {
    public static var placeholder: Data {
        Data([
            0xB2, 0xCB, 0x25, 0xC6, 0x01,
            0x00, 0x00, 0x00, 0x40, 0x71,
            0xD8, 0x9E, 0x81, 0x34, 0x63,
            0x06, 0xA0, 0x35, 0xA6, 0x83,
        ])
    }
    
    public static var placeholder35: Data {
        Data([
            0xB2, 0xCB, 0x25, 0xC6, 0x01,
            0x00, 0x00, 0x00, 0x40, 0x71,
            0xD8, 0x9E, 0x81, 0x34, 0x63,
            0x06, 0xA0, 0x35, 0xA6, 0x83,
            0xD8, 0x9E, 0x81, 0x34, 0x63,
            0x06, 0xA0, 0x35, 0xA6, 0x83,
            0xD8, 0x9E, 0x81, 0x34, 0x63,
        ])
    }
}
