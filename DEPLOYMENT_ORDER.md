# Consolidation deployment order

1. Do not upload the legacy transition package yet.
2. Back up the Meeks server save and configuration.
3. Upload unified Survivor League v1.6.0 to Workshop item `3784151798`.
4. In the server configuration, add Workshop `3784151798` and Mod ID `SurvivorLeagueCommunity`.
5. Remove Workshop `3783695026` and Mod ID `SurvivorLeague` from the active server list.
6. Set Interface Theme to Meeks Protocol, then configure title and subtitle.
7. Start the server and verify a `SUCCESS` migration log rather than `CONFLICT`.
8. Verify season number, timer, standings, streaks, history, pending rewards, announcements, and F6.
9. Only after the live migration succeeds, upload the legacy transition package to `3783695026` so remaining subscribers receive the retirement notice.

Never enable both Mod IDs together. If migration logs `CONFLICT`, stop the server and restore the backup before making further changes.
