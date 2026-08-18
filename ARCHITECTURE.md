# Unified Survivor League Architecture

Survivor League uses one runtime, one Lua module, one Sandbox namespace, and one persistent-data key. Server identity is now configuration rather than a separate codebase.

## Canonical identifiers

- Module: `SurvivorLeagueCommunity`
- Data: `SurvivorLeagueCommunityData`
- Workshop: `3784151798`
- Mod ID: `SurvivorLeagueCommunity`

The interface obtains every visual color from the selected palette. Gameplay, rewards, protocol validation, announcements, settlement, and persistence do not branch by theme.

The retired Meeks item `3783695026` contains only migration notices and must not be used as the active scoring mod after consolidation. Its `SurvivorLeagueData` table remains in the world save so the canonical runtime can copy it safely.
