# Changelog

## 1.9.1

- Made leaderboard page size responsive to the panel height and active UI font scale.
- Synchronized the calculated page size across client requests and server responses.
- Prevented oversized or stale leaderboard responses from drawing over newer pages.
- Reserved independent vertical regions for rows, pagination, personal statistics, controls, and the footer.
- Removed the duplicate navigation-row branding that collided with the search field.
- Vertically centered row content using measured font height and wrapped season reward summaries to two lines.
- Increased the gap between leaderboard and reward panels and made the tracking label report the actual synchronization mode.
- Bumped the internal handshake version to prevent mixed 1.9.0 and 1.9.1 installations.

## 1.9.0

- Refined Command Center spacing and identity presentation.
- Leaderboard, My Stats, and Season History now prioritize account usernames while retaining display and character-name fallbacks.
- Server payloads now carry `username`, `displayName`, `accountName`, and `characterName` separately.
- GUIDE now uses a valid project URL and displays the URL in chat/logs when the game cannot open a browser.
- Added the GUIDE fallback localization key.
- Corrected release metadata and auditing for the intentionally hidden legacy `LeaderboardSize` preset option.
- Bumped the internal handshake version to prevent mixed 1.8.6 and 1.9.0 installations.

## 1.8.6

- Changed player join notices to use chat-only delivery on each client.
- Removed the Build 42 red server-alert presentation from join notices.
- Preserved the `[SurvivorLeagueCommunityJoin]` server log marker used by Discord and website relays.
- Bumped the internal handshake version to prevent mixed 1.8.5 and 1.8.6 installations.

## 1.8.5

- Added a one-time, idempotent reconciliation between `SurvivorLeagueData` and `SurvivorLeagueCommunityData` when both contain scores.
- Automatically imports legacy-only players and restores unambiguous zero-season historical baselines without resetting current-season kills or streaks.
- Preserves complete pre-migration canonical and legacy score snapshots inside canonical ModData and never modifies or deletes the legacy dataset.
- Records a dedicated reconciliation version so the migration cannot run again after completion.
- Logs ambiguous overlapping records and preserves them unchanged for administrator review.
- Bumped the internal handshake version to prevent mixed 1.8.4 and 1.8.5 installations.

## 1.8.4

- Corrected `media/sandbox-options.txt` to Build 42 `VERSION = 2`, allowing Project Zomboid to register and generate the Survivor League SandboxVars block, including the F6 `InterfaceKey`.
- An F6 press made before the client/server handshake finishes now opens the Command Center automatically as soon as the server acknowledges the client; a second keypress is no longer required.
- Added focused client startup and handshake diagnostics to `console.txt`.
- Bumped the internal handshake version to prevent mixed 1.8.3 and 1.8.4 installations.

## 1.8.3

- Fixed admin score corrections leaving an online player's vanilla kill baseline behind, which could duplicate a pending kill after correcting a zeroed leaderboard record.
- Score corrections now re-baseline online targets by canonical username and synchronize client-report and server-observation state.
- Added the corrected baseline (or `unchanged-offline`) to the server audit entry for every correction.
- Bumped the internal client/server release handshake to prevent mixed 1.8.2 and 1.8.3 installations.

## 1.8.1

- Replaced player speech-bubble delivery for protocol, reward, score, streak-reset, and season-settlement notices with server/system chat messages.
- Restricted the Admin tab and all protected administrative commands to the Project Zomboid `Admin` access level.
- Automatically treats kill-streak tiers with no items and zero XP as disabled, preventing empty grants and misleading notifications.
- Synchronized the root and Build 42 manifests at version 1.8.1 and declared Build 42 compatibility in both manifests.
- Bumped the internal client/server release handshake to reject mixed 1.8.0 and 1.8.1 installations.
- Documented permissions, empty-tier behavior, Build 42.20 support, and the 1.8.0 upgrade procedure.

## Planned after 1.8.1

Season controls, granular permissions, moderator status, reward retry, player search, exports, notification preferences, integrations, challenges, and achievements remain outside this hardening release.
## 1.8.2

- Fixed leaderboard rows overlapping pagination and the personal-stat cards at larger UI/font scales.
- Leaderboard pagination now derives its page size from the panel's actual available height.
- Improved command-center tab spacing at narrower resolutions and larger UI scales.
- Retained Meeks Protocol as the packaged default interface theme.
