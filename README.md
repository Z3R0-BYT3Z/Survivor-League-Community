# Survivor League Community Edition

Survivor League Community Edition is a free, open-source Project Zomboid Build 42 multiplayer mod that adds persistent seasonal competition, lifetime stat tracking, configurable rewards, server announcements, and an in-game leaderboard to community servers.

## Features

- **Season and lifetime kill tracking:** Season Kills follow the survivor's active life and reset on death, while Total Kills remain persistent across deaths, reconnects, seasons, and server restarts.
- **Live F6 leaderboard:** View current rankings, the top-three podium, season countdown, reward previews, and paginated player lists without leaving the game.
- **Configurable seasons and podium rewards:** Admins can set season duration, qualifying kills, leaderboard size, item bundles, perk XP, and traits through native Sandbox Options.
- **Five kill-streak reward tiers:** Each tier can award configurable items and perk XP once per survivor life, then resets on death.
- **Death announcements:** Optional server-wide notices can include survival time, Season Kills, Total Kills, and a custom prefix.
- **Randomized join announcements:** Welcome connecting players with up to 20 admin-editable messages. `{name}` automatically inserts the player's name; prefix, cooldown, and enable/disable controls are available through Sandbox Options.
- **Build 42 chat compatibility:** Announcement rendering explicitly binds the current chat API and falls back to an on-screen notice when necessary.
- **Server-first synchronization:** Dedicated servers track kills from the server player object. An optional hosted/co-op client fallback is disabled by default and protected by configurable time-based rate limits.
- **Verified death fallback:** Optional client death reports are accepted only when the server confirms that the player is dead.
- **Master enable control:** Disabling the mod now stops tracking, commands, rewards, join notices, death notices, and leaderboard requests consistently.
- **Relay-ready logging:** Structured `[SurvivorLeagueKill]`, `[SurvivorLeagueDeath]`, and `[SurvivorLeagueCommunityJoin]` markers can be consumed by optional Discord or website relays.

## Configuration

All supported server-owner settings are available through Project Zomboid's native Sandbox Options. Admins do not need to edit Lua files to change seasons, rewards, death notices, or join messages.

Blank join-message slots are ignored. Use `{name}` anywhere the connecting player's display name should appear.

Dedicated servers should leave **Allow hosted/co-op client kill-report fallback** disabled. Enable it only when a hosted/co-op session does not expose updated zombie kills to the server player object. The fallback's report interval and maximum kills per minute can be adjusted in Sandbox Options.

## Installation

1. Install the mod through Steam Workshop or copy `SurvivorLeagueCommunity` into the Project Zomboid mods directory.
2. Add `SurvivorLeagueCommunity` to the server's `Mods=` setting.
3. Configure the mod under **Survivor League Community Edition** in Sandbox Options.
4. Restart the server after changing settings.

- Workshop ID: `3784151798`
- Mod ID: `SurvivorLeagueCommunity`
- Build: Project Zomboid 42.15+

## License and credits

Created and maintained by **Z3R0X92**. Released under the MIT License for free community use and modification. Credit the original creator when redistributing modified versions.
