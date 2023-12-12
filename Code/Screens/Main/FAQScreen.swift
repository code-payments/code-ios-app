//
//  FAQScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-11.
//

import SwiftUI
import CodeUI
import CodeServices

struct FAQScreen: View {
    
    @EnvironmentObject private var contentController: ContentController
    
    @Binding public var isPresented: Bool
    
    private let isModal: Bool
    
    // MARK: - Init -
    
    public init(isPresented: Binding<Bool>?) {
        self._isPresented = isPresented ?? .constant(false)
        self.isModal = isPresented != nil
    }
    
    // MARK: - Body -
    
    var body: some View {
        content()
    }
    
    @ViewBuilder private func content() -> some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading) {
                ScrollBox(color: .backgroundMain) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 40) {
                            ForEach(contentController.faqs, id: \.question) { faq in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(faq.question)
                                        .font(.appTextLarge)
                                    Text(LocalizedStringKey(faq.answer))
                                        .font(.appTextBody)
                                        .tint(.textSecondary)
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .foregroundColor(.textMain)
            .navigationBarTitle(Text(Localized.Title.faq), displayMode: .inline)
        }
        .onAppear {
            Analytics.open(screen: .faq)
            ErrorReporting.breadcrumb(.faqScreen)
        }
    }
}

// MARK: - Previews -

struct FAQScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FAQScreen(isPresented: .constant(true))
            NavigationView {
                FAQScreen(isPresented: nil)
            }
        }
        .environmentObjectsForSession()
    }
}
