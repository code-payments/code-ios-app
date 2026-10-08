import XCTest

/// Spike probe, not for merge. Hardware-keyboard, selection-after-format and undo rows.
@MainActor
final class ComposerSpikeProbeTests: BaseUITestCase {
    override var requiresAuthentication: Bool { true }
    private var conversation: ConversationUIScreen { ConversationUIScreen(app: app) }

    private func open() throws {
        assertMainScreenReached()
        let chats = TipsUIScreen(app: app)
        chats.open(from: self)
        guard let row = chats.firstConversationRow(timeout: 30) else { throw XCTSkip("no chat") }
        row.tap()
        XCTAssertTrue(conversation.messageField.waitForExistence(timeout: 30))
        conversation.clearDraft()
    }

    private func log(_ s: String) { print("PROBE: \(s) => '\(conversation.draftValue)'") }

    func testMenuFormatSelectionAndUndo() throws {
        try open()
        let f = conversation.messageField
        print("PROBE: elementType=\(f.elementType.rawValue) (textField=49 textView=50)")
        f.tap()
        f.typeText("hello world")
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).doubleTap()
        sleep(1)
        print("PROBE: menu buttons=\(app.buttons.allElementsBoundByIndex.map { $0.label }.filter { ["Bold","Italic","Strikethrough","Code","Link","Format","Cut","Copy"].contains($0) })")
        print("PROBE: menuItems=\(app.menuItems.allElementsBoundByIndex.map { $0.label })")
        let bold = app.menuItems["Bold"].exists ? app.menuItems["Bold"] : app.buttons["Bold"]
        if bold.waitForExistence(timeout: 3) { bold.tap() } else { print("PROBE: no Bold item") }
        log("after menu Bold")
        f.typeText("X")
        log("typed X over selection")
        f.typeKey("z", modifierFlags: .command)
        log("undo 1")
        f.typeKey("z", modifierFlags: .command)
        log("undo 2")
        f.typeKey("z", modifierFlags: .command)
        log("undo 3")
    }

    func testDraftRestoreCaret() throws {
        try open()
        let f = conversation.messageField
        f.tap()
        f.typeText("hello world")
        // Leave and come back.
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
        let chats = TipsUIScreen(app: app)
        guard let row = chats.firstConversationRow(timeout: 30) else { throw XCTSkip("no chat") }
        row.tap()
        XCTAssertTrue(conversation.messageField.waitForExistence(timeout: 30))
        sleep(1)
        log("restored")
        print("PROBE: keyboardUp=\(app.keyboards.count > 0)")
        if app.keyboards.count > 0 {
            conversation.messageField.typeText("X")
            log("typed X without tapping")
        } else {
            conversation.messageField.tap()
            conversation.messageField.typeText("X")
            log("tapped then typed X")
        }
    }

    func testFormatSelectionAndUndo() throws {
        try open()
        let f = conversation.messageField
        f.tap()
        f.typeText("hello world")
        log("typed")
        f.typeKey("a", modifierFlags: .command)
        f.typeKey("b", modifierFlags: .command)
        log("after cmd+B")
        f.typeText("X")
        log("typed X over selection")
        f.typeKey("z", modifierFlags: .command)
        log("undo 1")
        f.typeKey("z", modifierFlags: .command)
        log("undo 2")
        f.typeKey("z", modifierFlags: .command)
        log("undo 3")
        f.typeKey("z", modifierFlags: [.command, .shift])
        log("redo 1")
    }
}
