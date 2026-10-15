# Sender-built link previews (flipcash2 0.19.0)

Spec: orchestrator docs/specs/link-preview-send.md; contract comments on TextContent.link_previews,
LinkPreview, EncryptedContent in flipcash2 model.proto.

## Model
- FlipcashCore `SentLinkPreview { url: String, title: String, description: String?, image: MediaAttachment? }`
  (Codable, Hashable, Sendable). `ConversationMessage.linkPreview: SentLinkPreview?` stored property,
  like `repliedTo` (init, replacingContent). Only on `.text` content.
- Proto out: `ChatSeal.plaintext(text:repliedTo:linkPreview:)` builds `linkPreviews` — one builder for
  plaintext and sealed. Image: plaintext = ORIGINAL rendition + blobID only; sealed = ORIGINAL with
  sender-set metadata (reuse SealedPhoto.media / MediaAttachment.proto).
- Proto in: `ConversationMessage.init(proto)` text + reply-text, and `ChatSeal.readable` for sealed.
  Image decoded like MediaContent items (plain via MediaAttachment(proto), sealed via the sealed
  validator). A preview whose url fails the whole-link check against its text, or whose title cleans
  to nothing, is dropped on read (defensive: the sealed path is not server-checked).
- Storage: `conversation_message.linkPreviewJson: Data?`; schemaVersion 51 -> 52; drop LinkPreviewTable
  creation (store is rebuilt, so dropping the create is enough).

## Sender
- Composer: detect via LinkCardClassifier first web card of the draft. Per conversation a
  `ComposerLinkPreview` @Observable: state loading / ready(SentLinkPreview, thumbnail) / failed,
  `dismissedURLs`. Fetch = PinnedLinkMetadataSource (flag gate removed) -> WebImageSource image bytes
  (memory only) -> ChatMediaUploader.upload(UIImage) -> MediaAttachment. Loading covers the fetch and
  the image upload; image failure -> ready without image.
- Chip strip shows the thumbnail (image or a link glyph + host) with the remove control.
- Send: only `ready` attaches; run isWholeLink(url, in: sentText) + cleanTitle/cleanDescription;
  never on media captions. After send the draft's preview resets.
- Edit: no refetch; re-attach the message's stored preview iff isWholeLink(url, in: newText) still
  passes, else send none. Local mutation rewrite keeps/clears linkPreview to match. Retry: resends the
  pending message's preview as it was checked at send.
- Photo + link draft: the preview chip is hidden while photo chips exist and nothing attaches
  (captions carry no preview).
- Chip shows a loading state during fetch+upload; fetch/upload task cancelled on remove and on send.
- Plaintext upload has no dims: capture width/height from onPrepared for the pending row.

## Recipient
- Mapper builds `.web` card only from `message.linkPreview` (range of url found as a whole link in the
  text; no classifier/isFetchable/marketing rules on read). Detected web links without a preview stay
  plain linkified text. `Resolved` stays the parser's output; the card draws a separate received type
  (title, description?, host, image: ChatMediaContent?). Read drops only per contract (url not a whole
  link, empty title); no cleaning on read, clamp in the view. Card image loads through the chat media pipeline (ChatMediaURLResolver +
  ChatMediaImageSource), passed down from ChatViewController.
- Delete: receive fetch/prefetch/memo web paths, WebImageDiskCache, LinkPreviewStoring, Database+LinkPreviews,
  WebLinkPreviewMode/WebPreviewRequests/tap-to-load chip, ConversationScreen first-paint gate,
  `.webLinkPreviews` beta flag and `webLinks:` classifier parameter.
- Keep: PinnedHTTPClient, HTTP1ResponseReader, WebAddress, WebPageParser, WebLinks, PinnedLinkMetadataSource,
  WebImageSource (sender).
