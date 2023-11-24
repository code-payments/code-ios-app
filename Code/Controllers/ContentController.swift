//
//  ContentController.swift
//  Code
//
//  Created by Dima Bart on 2021-03-16.
//

import Foundation
import CodeServices

@MainActor
class ContentController: ObservableObject {
    
    @Published private(set) var faqs: [FAQ] = []
    
    private let client: Client
    
    // MARK: - Init -
    
    init(client: Client) {
        self.client = client
        
        loadFAQs()
    }
    
    // MARK: - FAQ -
    
    private func loadFAQs() {
        faqs = [
            FAQ(
                question: Localized.Faq.Q._1,
                answer:   Localized.Faq.A._1
            ),
            FAQ(
                question: Localized.Faq.Q._2,
                answer:   Localized.Faq.A._2
            ),
            FAQ(
                question: Localized.Faq.Q._3,
                answer:   Localized.Faq.A._3
            ),
            FAQ(
                question: Localized.Faq.Q._4,
                answer:   Localized.Faq.A._4
            ),
            FAQ(
                question: Localized.Faq.Q._5,
                answer:   Localized.Faq.A._5
            ),
            FAQ(
                question: Localized.Faq.Q._6,
                answer:   Localized.Faq.A._6
            ),
            FAQ(
                question: Localized.Faq.Q._7,
                answer:   Localized.Faq.A._7
            ),
            FAQ(
                question: Localized.Faq.Q._8,
                answer:   Localized.Faq.A._8
            ),
            FAQ(
                question: Localized.Faq.Q._9,
                answer:   Localized.Faq.A._9
            ),
            FAQ(
                question: Localized.Faq.Q._10,
                answer:   Localized.Faq.A._10
            ),
            FAQ(
                question: Localized.Faq.Q._11,
                answer:   Localized.Faq.A._11
            ),
        ]
    }
}

extension ContentController {
    static let mock = ContentController(client: .mock)
}
