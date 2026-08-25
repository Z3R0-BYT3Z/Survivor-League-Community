# Migrating from Survivor League for Meeks Protocol

Canonical release:

- Workshop ID: `3784151798`
- Mod ID: `SurvivorLeagueCommunity`
- Sandbox namespace: `SurvivorLeagueCommunity`
- Data key: `SurvivorLeagueCommunityData`

## Safe server transition

1. Stop the server and back up its save and configuration files.
2. Add Workshop ID `3784151798` and Mod ID `SurvivorLeagueCommunity`.
3. Remove Mod ID `SurvivorLeague` from the active mod list.
4. Set Interface Theme to Meeks Protocol and configure the desired title/subtitle.
5. Start the server and locate `[SurvivorLeagueCommunityMigration]` in the log.
6. Confirm the F6 standings, season timer, streaks, history, and pending rewards.

If `SurvivorLeagueCommunityData` is empty and `SurvivorLeagueData` contains data, the canonical mod copies the legacy dataset and records a migration marker. The legacy table is never deleted.

If both datasets contain data, version 1.8.5 performs one guarded reconciliation. Legacy-only players are imported, and a legacy record with zero season kills may supply a missing historical baseline without changing the canonical current-season score or streak. Exact duplicates and canonical records that already contain the legacy history are left unchanged. Ambiguous overlaps are logged as `REVIEW` and are not changed automatically.

Before reconciliation, the server stores complete canonical and legacy score snapshots in `legacyReconciliationBackupV1`. The legacy `SurvivorLeagueData` table is never modified or deleted. After the first completed pass, `legacyReconciliationVersion=1` prevents the migration from running again.

After a successful legacy migration, server gameplay settings temporarily fall back to the old `SurvivorLeague` Sandbox namespace while `LegacyMeeksSettingsFallback` remains enabled. Copy the intended settings into the canonical namespace, verify them, and then disable the fallback.

Do not enable both scoring editions together.
