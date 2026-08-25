//
//  UsernameDialogTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
import FlipcashUI
// `ErrorProfile.moderated` carries a generated proto enum.
import FlipcashAPI
@testable import Flipcash

@MainActor
@Suite("Username dialogs")
struct UsernameDialogTests {

    @Test("The gate names the server's minimum in both the title and the body")
    func gateDialog_namesMinimum() {
        let item = DialogItem.usernameMinimumBalance(minimum: .usd(100), onAddMoney: {})

        #expect(item.title == "$100 Minimum Balance Required")
        #expect(item.subtitle?.contains("$100 USD") == true)
    }

    @Test("The gate drops trailing zeros rather than reading $100.00")
    func gateDialog_wholeAmountHasNoCents() {
        let item = DialogItem.usernameMinimumBalance(minimum: .usd(100), onAddMoney: {})
        #expect(item.title?.contains(".00") == false)
    }

    @Test("The gate offers Add Money over Dismiss")
    func gateDialog_actions() {
        let item = DialogItem.usernameMinimumBalance(minimum: .usd(100), onAddMoney: {})

        #expect(item.actions.count == 2)
        #expect(item.actions[0].title == "Add Money")
        #expect(item.actions[1].title == "Dismiss")
    }

    @Test("Add Money runs the handler it was given")
    func gateDialog_addMoneyRunsHandler() {
        var ran = false
        let item = DialogItem.usernameMinimumBalance(minimum: .usd(100), onAddMoney: { ran = true })

        item.actions[0].action()
        #expect(ran)
    }

    @Test("The generic failure names itself, independent of its two callers")
    func genericFailure_copy() {
        let item = DialogItem.usernameGenericFailure

        #expect(item.title == "Couldn't Save Your Username")
        #expect(item.subtitle == "Try again")
    }

    @Test("Each validation failure gets its own copy")
    func validationDialogs_copy() {
        let tooShort = DialogItem.usernameValidation(.tooShort)
        #expect(tooShort.title == "Too Short")
        #expect(tooShort.subtitle == "Usernames must be a minimum of 2 characters")

        let tooLong = DialogItem.usernameValidation(.tooLong)
        #expect(tooLong.title == "Too Long")
        #expect(tooLong.subtitle == "Usernames must be a maximum of 15 characters")

        let invalid = DialogItem.usernameValidation(.invalidCharacters)
        #expect(invalid.title == "Invalid Characters")
        #expect(invalid.subtitle == "Only letters, numbers, and underscores are allowed")
    }

    @Test("Moderation reuses the display-name copy under a username title")
    func submissionDialog_moderated() {
        let item = DialogItem.usernameSubmission(.moderated(.other), minimum: nil, onAddMoney: {})

        #expect(item.title == "Inappropriate Username")
        #expect(item.subtitle == "Try a different name")
    }

    @Test("A taken handle asks for a different one")
    func submissionDialog_taken() {
        let item = DialogItem.usernameSubmission(.usernameTaken, minimum: nil, onAddMoney: {})

        #expect(item.title == "Username Taken")
        #expect(item.subtitle == "Please try a different username")
    }

    @Test("A reserved word points at support")
    func submissionDialog_reservedWord() {
        let item = DialogItem.usernameSubmission(.reservedWord, minimum: nil, onAddMoney: {})

        #expect(item.title == "Trademarks Not Allowed")
        #expect(item.subtitle?.contains("support@flipcash.com") == true)
    }

    @Test("Insufficient balance reuses the gate dialog rather than a seventh error")
    func submissionDialog_insufficientBalance_isGateDialog() {
        let item = DialogItem.usernameSubmission(.insufficientBalance, minimum: .usd(100), onAddMoney: {})

        #expect(item.title == "$100 Minimum Balance Required")
        #expect(item.actions[0].title == "Add Money")
    }

    @Test("Insufficient balance falls back to a generic error when no minimum is known")
    func submissionDialog_insufficientBalance_noMinimum() {
        let item = DialogItem.usernameSubmission(.insufficientBalance, minimum: nil, onAddMoney: {})
        #expect(item.title == "Couldn't Save Your Username")
    }

    @Test("An unmapped server error falls through to try again")
    func submissionDialog_unknown_generic() {
        let item = DialogItem.usernameSubmission(.unknown, minimum: nil, onAddMoney: {})

        #expect(item.title == "Couldn't Save Your Username")
        #expect(item.subtitle == "Try again")
    }

    @Test("A denied claim currently falls through to the generic error")
    func submissionDialog_denied_generic() {
        // Not bespoke copy yet — this pins today's behaviour so the day
        // `.denied` gets its own dialog, the change is deliberate.
        let item = DialogItem.usernameSubmission(.denied, minimum: nil, onAddMoney: {})

        #expect(item.title == "Couldn't Save Your Username")
        #expect(item.subtitle == "Try again")
    }

    @Test("The gate names the minimum's own currency rather than assuming USD")
    func gateDialog_nonUSDMinimum_namesItsCurrency() {
        let item = DialogItem.usernameMinimumBalance(minimum: FiatAmount(value: 100, currency: .cad), onAddMoney: {})

        #expect(item.subtitle?.contains("CAD") == true)
        #expect(item.subtitle?.contains("USD") == false)
    }

    @Test("Every rejection the user can type their way out of uses the grey banner")
    func rejections_areInformational() {
        let rejections: [DialogItem] = [
            .usernameValidation(.tooShort),
            .usernameValidation(.tooLong),
            .usernameValidation(.invalidCharacters),
            .usernameSubmission(.usernameTaken, minimum: nil, onAddMoney: {}),
            .usernameSubmission(.reservedWord, minimum: nil, onAddMoney: {}),
            .usernameSubmission(.moderated(.other), minimum: nil, onAddMoney: {}),
            .usernameSubmission(.invalidUsername, minimum: nil, onAddMoney: {}),
            .usernameMinimumBalance(minimum: .usd(100), onAddMoney: {}),
        ]

        for rejection in rejections {
            #expect(rejection.style == .standard, "\(rejection.title ?? "?") should be informational")
        }
    }

    @Test("The unexplained failure keeps the red banner")
    func genericFailure_isDestructive() {
        // The one dialog in the flow the user cannot act on, so it stays an
        // error — and stays tracked, which `.info` is not.
        #expect(DialogItem.usernameGenericFailure.style == .destructive)
        #expect(DialogItem.usernameGenericFailure.tracked)
    }
}
