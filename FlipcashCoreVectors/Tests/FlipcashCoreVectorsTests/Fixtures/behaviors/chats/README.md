# Chats

The chat list.

## Seed

| Id | Name | Type | Unread | Archived |
|---|---|---|---|---|
| `0101…` (32 digits) | Ballers | GROUP | 3 | no |
| `0202…` | Ava | TIP_DM | 0 | no |
| `0303…` | Book club | GROUP | 0 | no |
| `0404…` | Sam | TIP_DM | 1 | no |
| `0505…` | Old crew | GROUP | 2 | yes |

Ids repeat their two-digit prefix sixteen times, e.g. `01010101010101010101010101010101`.

## State keys

| Key | Type | Means |
|---|---|---|
| `loading` | boolean | The list hasn't loaded yet. |
| `filter` | `All` \| `Unread` \| `Groups` | The selected chip. |
| `chipsRevealed`, `showsChips` | boolean | The filter chips were pulled into view, and whether they show. |
| `isSelecting`, `selection` | boolean, string[] or null | Multi-select mode and the selected ids, sorted. |
| `canReadAll` | boolean | "Read all" is offered. |
| `showsArchivedRow` | boolean | The archived row shows (All filter only). |
| `hasNoChatsAtAll` | boolean | The empty state shows. |
| `chats` | object[] | Every unarchived chat: `id`, `name`, `isGroup`, `chatType`, `unreadCount`, `markedUnread`, `isUnread`. |
| `visibleChatIds` | string[] | The rows the current filter shows, in order. |
| `chips` | object | Each filter's ids. |
| `unreadChipCount`, `groupsChipCount` | number | The chip badges. |
| `archivedRowCount` | number | Unread archived chats (chats, not messages). |
| `tabBadge` | number | The Chats tab badge. |

## Actions

| Action | Input |
|---|---|
| `FilterSelected` | `filter` (required) |
| `ChipsRevealed` | none |
| `SelectionStarted` | `chatId` (optional, Android only; see below) |
| `SelectionToggled` | `chatId` (required) |
| `SelectionEnded` | none |
| `ChatOpened` | `chatId` (required). Pushes `Chat`. |
| `ArchivedOpened` | none. Pushes `ArchivedChats`. |
| `NewChatOpened` | none. Pushes `NewChat`. |
| `Back` | none. Lent by the host on every screen above Chats; Chats itself has no `Back`. |

### ArchivedChats

Pushed by `ArchivedOpened`, and hosted: a view model of its own over the same seeded chats, so a
change made here shows on Chats after `Back`.

| Key | Type | Means |
|---|---|---|
| `loading` | boolean | The archived chats haven't loaded yet. |
| `chatIds` | string[] | The archived chats, newest first, the order the screen lists them in. |
| `chats` | object[] | The same chats: `id`, `name`, `unreadCount`. Android only; see below. |

| Action | Input |
|---|---|
| `Unarchive` | `chatId` (required). The row's swipe action; the chat goes back to the main list. |
| `Back` | none. |

Android's archive also has select mode; iOS's doesn't, so no shared file uses it.

## Route and screens

`launch` opens `/tab/chats`, the form both apps' deep links already use; hosts refuse any other
route with `bad_input`. Opening the archive pushes the hosted `ArchivedChats` above. Opening a
chat or a new chat pushes a screen the host doesn't drive yet: its node names the screen, shows
what it was opened with (`Chat`: `chatId`), and offers only `Back`. Chats stays alive underneath, so `Back` returns to the list as it was.

Not covered yet: switching tabs (Android's tab tap clears the stack, iOS keeps a stack per tab),
muting from a row, and tapping a row in select mode.

## Where the platforms differ

- **Starting a selection on a row.** On Android a long-press on a row opens select mode with that row
  picked (`SelectionStarted` with `chatId`). On iOS a long-press opens the row's context menu, and
  select mode only opens from the More menu with nothing picked. Shared files send
  `SelectionStarted` without `chatId`; Android's `ChatListSelectionTest` covers the row case.
- **Row details.** The iOS host works on chat ids: rows, names and the Read all state need
  `Conversation` and `ConversationController`, which live in the app. So Chats' `chats` and
  `canReadAll`, and the archive's `chats`, are Android only, and no shared file asserts them.
