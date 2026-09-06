# GitHub publishing copy

## Repository name

`survivor-league-community`

## About description

Open-source Project Zomboid Build 42 multiplayer leaderboard with persistent lifetime kills, survival streaks, seasons, configurable rewards, and death notices.

## Suggested topics

`project-zomboid` `project-zomboid-mod` `build-42` `lua` `multiplayer` `leaderboard` `server-side` `open-source`

## Release title

Survivor League v1.10.9 — Death Relay Hotfix

## Release description

Survivor League is a unified Project Zomboid Build 42 multiplayer competition mod for community servers.

The F6 Command Center tracks cumulative Season Kills, permanent Total Kills, Current Streak, and Best Streak as separate statistics.

Server owners can configure season duration, minimum qualifying kills, podium item bundles, perk XP, traits, five kill-streak reward tiers, death notices, and randomized join announcements. All registered scores are sent and paginated; the legacy leaderboard-size field remains only for Sandbox preset compatibility.

Version 1.10.9 restores death announcements on Build 42 dedicated multiplayer servers. It detects the death screen through multiple client-side paths, authenticates reports through the accepted client/server session, suppresses duplicates, and corrects the Sandbox Options schema header that caused the `invalid or missing VERSION` startup error.

The host validates kill deltas and performs persistence and reward settlement to reduce duplicated or manipulated credit. Created and maintained by Z3R0X92 and released under the MIT License for free community use and modification.
