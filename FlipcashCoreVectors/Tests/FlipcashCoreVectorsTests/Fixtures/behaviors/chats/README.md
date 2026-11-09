# Chats

The chat list.

## Seed

| Id | Name | Type | Unread | Archived |
|---|---|---|---|---|
| `0101…` (32 digits) | Ballers | GROUP | 3 | no |
| `0202…` | Ava | TIP_DM | 0 | no |
| `0303…` | Book club | GROUP | 0 | no |
| `0404…` | Sam | TIP_DM | 1 | no |
| — | Old crew | GROUP | 2 | yes |

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

## Where the platforms differ

- **Starting a selection on a row.** On Android a long-press on a row opens select mode with that row
  picked (`SelectionStarted` with `chatId`). On iOS a long-press opens the row's context menu, and
  select mode only opens from the More menu with nothing picked. Shared files send
  `SelectionStarted` without `chatId`; Android's `ChatListSelectionTest` covers the row case.
