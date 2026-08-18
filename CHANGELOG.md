# Changelog

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
