# Survivor League

Current version: **1.10.0**

Survivor League is the unified, open-source Project Zomboid Build 42 multiplayer competition mod. It combines the former Community and Meeks Protocol editions through selectable interface themes while retaining one authoritative scoring and persistence system.

## Features

- **Separate season, lifetime, and streak tracking:** Season Kills accumulate for the entire season, Total Kills remain persistent, and the independent kill streak resets on death.
- **Tabbed Command Center:** Press F6 by default to view the 10-player-per-page leaderboard, personal stats, season history, podium and streak rewards, and authorized admin controls. The key code is configurable in Sandbox Options.
- **Configurable seasons and podium rewards:** Admins can set season duration, qualifying kills, item bundles, perk XP, and traits through native Sandbox Options.
- **Five kill-streak reward tiers:** Each tier can award configurable items and perk XP once per survivor life, then resets on death.
- **Death announcements:** Optional server-wide notices can include survival time, Season Kills, Total Kills, and a custom prefix. Server chat and above-player halo delivery can be controlled separately; chat is enabled and halos are disabled by default.
- **Randomized join announcements:** Welcome connecting players with up to 20 admin-editable messages. `{name}` automatically inserts the player's name; prefix, cooldown, and enable/disable controls are available through Sandbox Options.
- **Build 42 chat compatibility:** Join notices are inserted into chat without creating Build 42's red server alert; death and administrative notices retain their independently configured delivery behavior.
- **System-delivered status notices:** Protocol, reward, correction, streak-reset, and settlement notices appear as server/system messages instead of making the player's character speak.
- **Hybrid synchronization:** Dedicated servers prefer the server player object. The Build 42 compatibility fallback records client-sourced increases separately, rate-limits them, compares them with reliable server counters, and quarantines suspicious reports.
- **Reward trust controls:** Unverified client-fallback increases do not grant milestone rewards by default. Trusted communities may explicitly enable fallback milestone rewards in Sandbox Options.
- **Verified death fallback:** Optional client death reports are accepted only when the server confirms that the player is dead.
- **Master enable control:** Disabling the mod now stops tracking, commands, rewards, join notices, death notices, and leaderboard requests consistently.
- **Protocol verification:** Clients must complete an exact protocol and release handshake before gameplay or administrative commands are accepted.
- **UTF-8-safe names:** Multibyte player and character names are sanitized and truncated only at valid character boundaries.
- **Three interface themes:** Choose Project Zomboid, Meeks Protocol, or Military styling through Sandbox Options, with optional cosmetic player overrides.
- **White-label branding:** Configure the Command Center title and subtitle without maintaining a separate build.
- **Guarded legacy migration:** Empty Community datasets can import the former `SurvivorLeagueData` table without deleting it. Populated datasets are never merged automatically.
- **Relay-ready logging:** Structured `[SurvivorLeagueKill]`, `[SurvivorLeagueDeath]`, and `[SurvivorLeagueCommunityJoin]` markers can be consumed by optional Discord or website relays.

## Configuration

All supported server-owner settings are available through Project Zomboid's native Sandbox Options. Admins do not need to edit Lua files to change seasons, rewards, death notices, or join messages.

Kill-streak tiers with no configured items and zero XP are treated as disabled, even when their enable checkbox is selected. This prevents empty reward grants and misleading reward notifications.

Blank join-message slots are ignored. Use `{name}` anywhere the connecting player's display name should appear.

Build 42 dedicated servers that do not expose updated zombie kills to the server player object may leave **Allow hosted/co-op client kill-report fallback** enabled. This is a compatibility mode, not cryptographic proof of a kill. Reports are source-attributed, rate-limited, compared with a server counter once that counter proves reliable, and suspicious values are quarantined. Keep **Allow unverified client-fallback milestone rewards** disabled unless every connected client is trusted.

Season expiry is checked when the server starts, once per minute, and during normal player polling. A settlement guard prevents overlapping timer or admin requests from issuing duplicate podium rewards.

**Season Kills are cumulative for the active season.** Death resets only Current Streak and its once-per-life milestone claims. Total Kills and Best Streak remain persistent. The legacy `LeaderboardSize` value is still read from saved presets for compatibility, but the option is hidden and the Command Center always paginates all registered scores at 10 players per page.

Leaderboard requests are throttled on both client and server, and player names are sanitized and length-limited before being sent to the interface. Verified client death reports are disabled by default and should only be enabled for hosted/co-op sessions that miss native death events.

The Command Center key defaults to Project Zomboid key code `64` (F6). Set **Command Center key code** to another valid key code to rebind it. Server logs include structured protocol decisions, automatic-settlement triggers, admin settlement requests, rejected unauthorized settlement attempts, and settlement completion summaries.

See `ARCHITECTURE.md` and `MIGRATION.md` for the unified runtime and legacy Meeks transition procedure.

## Administrative permissions

Administrators always receive all Survivor League management permissions. Moderator and Overseer accounts can receive four independent server-controlled permissions through Sandbox Options: operational status, score/archive management, reward retry, and season settlement. These permissions default to status-only. Every protected command is authorized again by the server; hiding a tab or button is not the security boundary.

## Updating from 1.8.0

Replace both the client and server copies with the complete 1.10.0 package, then restart Project Zomboid and the server. Mixed installations are intentionally rejected by the version handshake. Existing standings, season history, and Sandbox settings are upgraded in place to data schema 2.

## Installation

1. Install the mod through Steam Workshop or copy `SurvivorLeagueCommunity` into the Project Zomboid mods directory.
2. Add `SurvivorLeagueCommunity` to the server's `Mods=` setting.
3. Configure the mod under **Survivor League** in Sandbox Options.
4. Restart the server after changing settings.

- Workshop ID: `3784151798`
- Mod ID: `SurvivorLeagueCommunity`
- Build: Project Zomboid 42.20+

## License and credits

Created and maintained by **Z3R0X92**. Released under the MIT License for free community use and modification. Credit the original creator when redistributing modified versions.
