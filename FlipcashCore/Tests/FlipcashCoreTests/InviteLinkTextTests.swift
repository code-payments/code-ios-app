import Testing
import Foundation
@testable import FlipcashCore

@Suite("Invite links in preview text")
struct InviteLinkTextTests {

    private let secret = "kQ3vR8mZp2LxT7yW9bN4cD6fH1jK5sA0eG3iU8oQ2rY"

    @Test("A bare invite URL becomes \"Invite link\"")
    func bareInviteURL() {
        let text = "https://app.flipcash.com/chat/invite#s=\(secret)"
        #expect(InviteLinkText.redacting(text) == "Invite link")
    }

    @Test("The text around an invite URL stays")
    func surroundingText() {
        let text = "join us https://app.flipcash.com/chat/invite#s=\(secret) tonight"
        let redacted = InviteLinkText.redacting(text)
        #expect(redacted == "join us Invite link tonight")
        #expect(!redacted.contains(secret))
    }

    @Test("An invite URL with a bad secret is hidden too, fragment and all")
    func badSecret() {
        let text = "here https://app.flipcash.com/chat/invite#s=not-a-secret"
        let redacted = InviteLinkText.redacting(text)
        #expect(redacted == "here Invite link")
        #expect(!redacted.contains("not-a-secret"))
    }

    @Test("A plain join link is left alone")
    func plainJoinLink() {
        let text = "come say hi https://app.flipcash.com/chat/2c5b8f0e-6b1a-4c1e-9d4b-3f0a7c2e8d11"
        #expect(InviteLinkText.redacting(text) == text)
    }

    @Test("A reply quote hides an invite link")
    func previewSites() {
        let text = "https://app.flipcash.com/chat/invite#s=\(secret)"
        #expect(ChatQuote.snippet(forText: text) == "Invite link")
    }

    @Test("A photo caption's invite link reads \"Invite link\" in a quote and a list preview")
    func captionPreviews() {
        let caption = "https://app.flipcash.com/chat/invite#s=\(secret)"
        #expect(ChatMediaStrings.quoteSnippet(caption: caption) == "Invite link")
        #expect(ChatMediaStrings.listPreview(caption: caption) == "📷 Invite link")
    }
}
