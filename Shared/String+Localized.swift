//
//  String+Localized.swift
//  Code
//
//  Created by Dima Bart on 2023-10-19.
//

import Foundation

extension String {
    var localizedStringByKey: String {
        NSLocalizedString(self, comment: "")
    }
}
