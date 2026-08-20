# Changelog

## 1.8.1 — 2026-08-20

- Replaced player speech delivery for protocol, reward, score, streak-reset, and settlement notices with server/system messages.
- Restricted the Admin tab and protected administrative commands to the Project Zomboid Admin access level.
- Automatically disabled kill-streak tiers that contain no items and zero XP.
- Synchronized root and Build 42 manifests, declared Build 42.20 compatibility, and strengthened mixed-version detection.
- Updated permissions, upgrade notes, and release documentation.

## 1.7.5 — 2026-08-19

- Removed the unstable in-game text-entry score-correction form that caused Admin-tab errors and severe font overlap.
- Rebuilt the Admin tab around supported, font-safe score-snapshot and confirmation-gated season-settlement controls.
- Preserved the server-authorized score-correction API for controlled administrative use.

## 1.7.4 — 2026-08-19

- Matched the complete Meeks Protocol palette to Radio Frequencies, including background, panels, primary/bright magenta, muted text, borders, and online status colors.

## 1.7.3 — 2026-08-19

- Integrated the unreleased v1.7.2 stabilization backup into the canonical GitHub source.
- Replaced shared multiplayer polling with independent per-player polling and disconnect cleanup.
- Added acknowledged, retryable hosted/co-op kill reports with the configured per-minute limit and verified final-death synchronization.
- Added malformed reward diagnostics, milestone retry pacing, stable settlement reward IDs, and restart-safe settlement markers.
- Preserved raw account keys for administration while keeping UI-safe display names.
- Kept legacy gameplay settings and score migration without allowing them to override unified interface settings.
- Made migrated Meeks Protocol servers select the pink theme automatically and changed the fresh-install default to Meeks Protocol pink.
- Rebuilt the Command Center header, tabs, leaderboard columns, reward rows, text wrapping, and footer around measured font dimensions.
- Bumped the client/server compatibility schema to 11 and protocol to 4.

## 1.7.1 — 2026-08-19

- Replaced the unsupported Kahlua `next()` migration check with a guarded `pairs()` scan.
- Added an administrator-only, read-only export of current and preserved legacy score datasets.
- Added record counts and structured recovery lines without automatically changing or merging scores.
- Added font-measured vertical centering for leaderboard rank and podium-place boxes.
- Bumped the client/server compatibility version to 9.

## 1.7.0 — 2026-08-19

- Restored the `LeaderboardSize` Sandbox option and kept ten-player pagination as the default.
- Added permission-gated administrator score correction with structured before/after audit logging.
- Added blocking Lua 5.1 syntax, Sandbox/config/translation parity, forbidden-artifact, version, package-parity, and protocol checks.
- Added a clean release builder that creates the Workshop `Contents/mods/SurvivorLeagueCommunity` tree from canonical source.
- Synchronized release version metadata across descriptors, Workshop notes, and validation.

## 1.6.0 — 2026-08-18

- Consolidated Community and Meeks Protocol gameplay into one canonical Mod ID and Workshop item.
- Added Project Zomboid, Meeks Protocol, and Military interface themes.
- Added configurable interface title/subtitle and optional per-player cosmetic theme cycling.
- Added guarded `SurvivorLeagueData` migration that preserves legacy data and refuses to merge two populated datasets.
- Added a temporary legacy-Meeks Sandbox settings fallback after successful migration.
- Bumped the compatibility protocol to v2 and persistent schema to v8.
- Converted the old Meeks Workshop package into a non-scoring migration notice for staged deployment.

## 1.5.0 — 2026-08-18

- Added exact client/server protocol and release verification before commands are accepted.
- Added UTF-8-safe name sanitization, measurement, and truncation.
- Added a configurable Command Center key code with F6 (`64`) as the safe default.
- Expanded audit logs for accepted/rejected protocols, automatic settlement triggers, admin requests, authorization failures, failures, and completed settlements.
- Established a reproducible shared-core variant builder; Community client/server Lua is mechanically derived from the branded canonical feature core.
- Preserved cumulative Season Kills, separate per-life streaks, 10-player pagination, edition-specific IDs, and edition-specific branding.
- Added Community Workshop change notes and GitHub correction guidance.

## 1.4.0 — 2026-08-18

- Separated cumulative Season Kills from the per-life kill streak; death now resets only streak progress and milestone claims.
- Added the full tabbed Community Command Center with leaderboard, personal stats, season history, rewards, and authorized admin tabs.
- Standardized leaderboard pagination at 10 registered players per page.
- Added client/server leaderboard request throttling and server-side player-name sanitization.
- Hid the deprecated `LeaderboardSize` option while continuing to read existing saved preset values.
- Disabled verified client death reports by default.
- Preserved Community Edition identifiers, off-white branding, scheduled settlement, reward safeguards, and optional radio integration.

## 1.3.6 — 2026-08-18

- publishes season podium results and completed kill-streak milestones through the optional Radio Frequencies server integration API;
- remains fully functional when Radio Frequencies is not installed.

## 1.3.5 — 2026-08-18

- Added startup and once-per-minute season-expiry checks so seasons settle even when no player-update callback reaches the timer path.
- Added an in-progress settlement guard and protected settlement execution to prevent duplicate rewards and overlapping season resets.
- Improved leaderboard sizing and screen-edge clamping for smaller resolutions while preserving the existing layout and pagination rules.
- Truncated unusually long display names to protect score-column alignment.
- Added separate Sandbox controls for death announcements in server chat and above players; chat remains enabled and halos disabled by default.
- Removed client-provided survival duration from the death-report payload.
- Removed redundant XP retry handling so each reward component is attempted once per retry cycle.

## 1.3.4 — 2026-08-18

- Resumed server-first kill tracking safely when the hosted/co-op client fallback is disabled, without importing existing character kills.
- Removed client-provided survival time from verified death processing; announcements now use the server player object's survival duration.
- Kept failed milestone and podium rewards pending instead of silently marking or clearing them.
- Added structured diagnostics for invalid items, perks, traits, and failed reward delivery.
- Deprecated the inactive `LeaderboardSize` setting without removing it from existing Sandbox presets; all registered scores remain paginated.
- Clarified that Season Kills intentionally represent the current survivor life and reset on death.

## 1.3.3 — 2026-08-17

- Made server-side zombie-kill tracking the default and disabled client kill reports by default.
- Added Sandbox controls for hosted/co-op client reporting, minimum report intervals, and maximum accepted kills per minute.
- Changed the first accepted client report into a baseline so existing character kills cannot be imported as new league progress.
- Added time-based rate limiting and detailed rejection logs for suspicious client kill reports.
- Required the server to confirm that a player is dead before accepting the optional client death-report fallback.
- Applied the master Enabled setting consistently to tracking, commands, rewards, announcements, and leaderboard requests.
- Updated Community Edition documentation for the safer server-first behavior.

## 1.3.2 — 2026-08-16

- Fixed a Build 42 Lua reload freeze caused by invalid empty string defaults.
- Corrected all 20 join-message Sandbox declarations.
- Preserved built-in randomized messages when all custom slots are blank.
- Cleaned corrupted saved join-message values from affected test presets.
- Restored complete kill-streak reward configuration compatibility.


## 1.3.1 — 2026-08-16

- Fixed Build 42 custom Sandbox parsing for all 20 join-message slots.
- Moved the five built-in welcome messages to a Lua fallback used when every custom slot is blank.
- Preserved `{name}` replacement for messages entered by administrators.
- Normalized quoted Sandbox strings so prefixes, messages, rewards, traits, and perk names are used without visible outer quotes.
- Made reward item lists accept both commas and semicolons while using parser-safe semicolon defaults.

## 1.3.0 — 2026-08-16

- Added randomized server-wide player join announcements.
- Added a retry-and-acknowledgment connection handshake to prevent missed or duplicate announcements during Build 42 initialization.
- Added native Sandbox controls for enabling join announcements, editing the prefix, setting the duplicate cooldown, and customizing 20 individual message slots.
- Added automatic `{name}` replacement and blank-message filtering.
- Fixed Build 42 chat rendering by binding `zombie.chat.ChatManager` explicitly with a safe halo fallback.
- Fixed an unresolved client-file merge artifact and restored a single valid server-command handler.
- Added missing JSON and legacy English translations for all five kill-streak reward tiers.
- Updated the README and release documentation for the complete current feature set.

## 1.2.2 — 2026-08-15

- Added leaderboard pagination to prevent larger player lists from overlapping the lower UI.
- Page 1 displays the podium ranks 1–3; later pages display five players each.
- Added previous/next controls and a current-page indicator.
- Adjusted the season heading and countdown spacing to prevent text overlap.
- Preserved the Community Edition's off-white interface and neutral branding.

## 1.2.1 — 2026-08-15

- Changed the leaderboard accent from bright blue to an off-white Project Zomboid-style theme.
- Added hosted Build 42 client kill-counter synchronization for sessions where the server-side player object remains at zero.
- Added bounded delta validation and warning logs for implausible submitted kill increases.
- Synced kills when the leaderboard opens, when Refresh is selected, during play, and immediately before a death report.
- Updated the UI and documentation from server-authoritative to host-validated tracking language.

## 1.2.0 — 2026-08-15

- Added generic `[SurvivorLeagueKill]` aggregated kill-delta markers for optional external relays.
- Added username and character metadata to server-side death markers while keeping player-facing announcements clean.
- Added a client death-report fallback and server-side survival/kill reset detection for hosted and dedicated servers that miss `OnPlayerDeath`.
- Added duplicate-death suppression across the native event and fallback paths.
- Documented the brand-neutral relay contract; no webhook URLs, credentials, or server-specific hosting details are included in the mod.

All notable changes to Survivor League Community Edition are documented here.

## 1.1.1 — 2026-08-15

- Added death announcements directly to Project Zomboid's server chat.
- Kept the on-screen halo and structured server-log notification.
- Improved short survival durations to display minutes instead of `0h`.

## 1.1.0 — 2026-08-15

- Added configurable server-wide player-death announcements.
- Added survival time, final Season Kills, and Total Kills to death notices.
- Added a minimum survival-time threshold and custom announcement prefix.
- Added structured `[SurvivorLeagueDeath]` server-log output for external Discord relays.
- Preserved the final Season Kills value in the announcement before resetting it on death.

## 1.0.1 — 2026-08-15

- Changed reward text fields to Build 42-compatible string Sandbox options.
- Added Build 42.15+ JSON Sandbox translations.
- Restored readable option labels for items, perk XP, and trait rewards.

## 1.0.0

- Initial brand-neutral public edition.
- Added persistent Season Kills and Total Kills leaderboards.
- Added server-authoritative tracking, season settlement, and configurable rewards.
