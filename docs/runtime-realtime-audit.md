# Roomly — Runtime & Realtime Architecture (2026-11-10)

## Layers and ownership

- `src/main.js`: Vue mount and fatal-error recovery UI. The browser entry point mounts **once**.
- `src/App.vue`: authentication, room membership, screens, and user actions.
- `src/syncController.js`: **the sole coordinator** for normal data resynchronization. It receives table topics, coalesces events, serializes requests, and discards queued events on unmount.
- `src/scheduler.js`: pure business rules for chore rotations and busy times.
- Supabase Postgres: RLS-protected source of truth; Vercel serves only the compiled static Vue application.
- `public/sw.js`: network-first navigation; does not cache API calls or asset bundles, and never calls `location.reload` or `clients.openWindow`.

## State transitions

1. **Login / initial session**: only a changed account ID may run `reset()` and room bootstrap. A duplicate `SIGNED_IN` after tab focus and `TOKEN_REFRESHED` do not restart the UI.
2. **Room membership bootstrap**: the loading/join screen is shown **only** before confirming whether the current account belongs to a room.
3. **Realtime changes**: a database table change enqueues only its corresponding data slice. `room_members` also fetches display names. No normal database change resets the workspace.
4. **Owner removes another member**: the owner sees a member-list and related assignment refresh, not an auth or room reset. The removed user is checked separately; a confirmed *own* removal is allowed to move that account to onboarding.
5. **Tab changes**: `currentTab` is local Vue state. No URL navigation, remounting of `#app`, room lookup or fetch occurs.
6. **Browser tab refocus**: a slow reconciliation happens only when the WebSocket is disconnected or data has been stale for at least three minutes, with a one-minute throttle.
7. **Week navigation**: only assignments for the selected week are refetched. Stale results from a previous week, room or account are ignored.
8. **Offline/PWA**: navigation tries the network, then static offline message; it does not serve stale JavaScript from cache.

## Test cases

Run `npm test` for:
- repeated auth events for the same account;
- 100 Realtime messages coalescing into one request batch;
- serialization when another message arrives mid-request;
- deterministic re-fetch after recoverable errors;
- disposal during an in-flight or pending synchronization;
- member removal without triggering room bootstrap;
- tab visibility, navigation and PWA behavior;
- seven-day round-robin chores, busy slots and dishwashing.

Run `npm run build` before promoting any production deployment.

## Verification limits

The tests and production build verify logic and compile correctness, not a user's private authenticated browser session. For a live end-to-end confirmation use two signed-in devices: keep one on **Nhóm trọ** and remove another member using the other device. The first device must update its list **without** displaying the Roomly boot splash or changing the active screen. If a full browser navigation is observed, inspect DevTools → Network with **Preserve log** to distinguish an actual document request from a Vue component rerender.
