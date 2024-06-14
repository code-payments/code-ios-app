//
//  MessageController.swift
//  Code
//
//  Created by Dima Bart on 2022-01-25.
//

import Foundation
import MessageUI

/// Was used from the ContactsScreen
class MessageController: NSObject, ObservableObject, MFMessageComposeViewControllerDelegate {
    
    private var result: ((SendResult) -> Void)?
    
    // MARK: - Init -
    
    override init() {
        super.init()
    }
    
    // MARK: - Send -
    
    func presentMessage(to phoneNumber: String, body: String, result: @escaping (SendResult) -> Void) {
        guard MFMessageComposeViewController.canSendText() else {
            result(.cancelled)
            return
        }
        
        let controller = MFMessageComposeViewController()
        controller.recipients = [phoneNumber]
        controller.body = body
        controller.messageComposeDelegate = self
        
        self.result = result
        
        UIApplication.shared.rootViewController?.present(controller, animated: true, completion: nil)
    }
    
    // MARK: - MFMessageComposeViewControllerDelegate -
    
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        UIApplication.shared.rootViewController?.dismiss(animated: true, completion: nil)
        
        self.result?(SendResult(rawValue: result.rawValue) ?? .failed)
        self.result = nil
    }
}

extension MessageController {
    enum SendResult: Int {
        case cancelled
        case sent
        case failed
    }
}
