# Favorite public groups on profiles (flipcash2 0.18.0)

Contract + wrappers already on main (257a089d, 721fb442): `FlipClient.getFeaturedGroups(owner:username:)`,
`setFeaturedGroups(owner:conversationIDs:)`. This plan is the app layer and UI only.

Branch `feat/profile-featured-groups`, cut from `feat/profile-refresh-copy` (#990) with `origin/main` merged in
(the stack predates the 0.18.0 wrappers).

## Proto facts that shape the design
- Ordered list, max 10 (PGV `max_items`, so exceeding it is a transport invalid-argument — cap client-side).
- Written whole; empty clears. Only public groups (`.denied` otherwise, names no group).
- Featuring is independent of membership: leaving a group does not unfeature it.
- `GetFeaturedGroups` returns list-view `Metadata` (no members, viewer state, last message, cover).

## Shape
- `FeaturedGroups` (`@MainActor @Observable`, `let` on `SessionContainer`): the signed-in user's list,
  shared by the You tab section, the Edit Profile row ("N selected") and the picker. Closures injected
  (fetch/save) like `EditBioModel`. Never seated into `ConversationStore`.
- `UserProfileViewModel.featuredGroups`: fetched after the profile (needs `username`).
- `FeaturedGroupsSection` view: "Favorite Public Groups" header + rows (group avatar, title,
  description ?? people count); tap → `router.push(.tipConversation(id))`. Hidden when empty.
- Edit Profile: `FieldCard` "Favorite Public Groups" → new `.editFeaturedGroups` destination.
- Picker `EditFeaturedGroupsScreen` + `EditFeaturedGroupsModel`: candidates = current featured (server
  order) ∪ joined public groups from `loadGroupFeed()`'s result (`isPrivate` isn't persisted, so the
  store's copy can't be trusted offline; fallback = store joined groups with `!isPrivate && !useE2Ee`).
  Search by title, ordered selection, cap 10, bottom filled Save like `EditBioScreen`.
