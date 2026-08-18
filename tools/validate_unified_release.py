#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
legacy = root.parent / "meeks-protocol-work" / "Contents" / "mods" / "SurvivorLeague"

client = (root / "42/media/lua/client/SurvivorLeagueCommunity_Client.lua").read_text(encoding="utf-8")
server = (root / "42/media/lua/server/SurvivorLeagueCommunity_Server.lua").read_text(encoding="utf-8")
config = (root / "42/media/lua/shared/SurvivorLeagueCommunity_Config.lua").read_text(encoding="utf-8")
sandbox = (root / "42/media/sandbox-options.txt").read_text(encoding="utf-8")

assert "version=1.6.0" in (root / "42/mod.info").read_text(encoding="utf-8")
assert "id=SurvivorLeagueCommunity" in (root / "42/mod.info").read_text(encoding="utf-8")
assert 'existingModData("SurvivorLeagueData")' in server
assert "CONFLICT canonical and legacy Meeks datasets" in server
assert "legacy data was preserved" in server
assert "ProjectZomboid" in config and "MeeksProtocol" in config and "Military" in config
assert "AllowPlayerThemeOverride" in sandbox and "LegacyMeeksSettingsFallback" in sandbox
assert "onCycleTheme" in client
json.loads((root / "42/media/lua/shared/Translate/EN/Sandbox.json").read_text(encoding="utf-8"))

assert not (legacy / "42/media/lua/server/SurvivorLeague_Server.lua").exists()
assert not (legacy / "42/media/lua/client/SurvivorLeague_Client.lua").exists()
assert (legacy / "42/media/lua/server/SurvivorLeague_Legacy_Server.lua").exists()
assert "version=1.5.1" in (legacy / "42/mod.info").read_text(encoding="utf-8")

print("Unified Survivor League release structure is valid")
