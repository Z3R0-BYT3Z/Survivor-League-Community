#!/usr/bin/env python3
from __future__ import annotations
import argparse, filecmp, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "SurvivorLeagueCommunity"
FORBIDDEN_SUFFIXES = {".bak", ".old", ".tmp", ".zip"}
errors: list[str] = []

def fail(message: str) -> None:
    errors.append(message); print(f"::error::{message}")

def forbidden(path: Path) -> bool:
    parts = [p.lower() for p in path.parts]
    return path.suffix.lower() in FORBIDDEN_SUFFIXES or any("backup" in p for p in parts)

def compare_trees(source: Path, packaged: Path) -> None:
    left = {p.relative_to(source) for p in source.rglob("*") if p.is_file()}
    right = {p.relative_to(packaged) for p in packaged.rglob("*") if p.is_file()}
    if left != right:
        fail(f"Package file set differs: missing={sorted(map(str,left-right))}, extra={sorted(map(str,right-left))}")
    for rel in sorted(left & right):
        if source.joinpath(rel).read_bytes() != packaged.joinpath(rel).read_bytes(): fail(f"Package byte mismatch: {rel}")

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package")
    args = parser.parse_args()
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    for info in (ROOT / "mod.info", ROOT / "42/mod.info"):
        text = info.read_text(encoding="utf-8-sig")
        if f"version={version}" not in text: fail(f"{info.relative_to(ROOT)} version does not match VERSION={version}")
        if f"id={PREFIX}" not in text: fail(f"{info.relative_to(ROOT)} has the wrong Mod ID")
    for note in (ROOT / "WORKSHOP_CHANGE_NOTE.txt", ROOT / "workshop.txt", ROOT / "CHANGELOG.md"):
        if f"v{version}" not in note.read_text(encoding="utf-8-sig") and f"## {version}" not in note.read_text(encoding="utf-8-sig"):
            fail(f"{note.relative_to(ROOT)} does not reference {version}")
    for path in ROOT.rglob("*"):
        if path.is_file() and ".git" not in path.parts and "dist" not in path.parts and forbidden(path.relative_to(ROOT)):
            fail(f"Forbidden repository artifact: {path.relative_to(ROOT)}")
    sandbox = (ROOT / "42/media/sandbox-options.txt").read_text(encoding="utf-8-sig")
    config = (ROOT / "42/media/lua/shared/SurvivorLeagueCommunity_Config.lua").read_text(encoding="utf-8-sig")
    option_names = set(re.findall(rf"\boption\s+{PREFIX}\.([A-Za-z0-9_]+)", sandbox))
    config_names = set(re.findall(r"\broot\.([A-Za-z0-9_]+)", config))
    config_names.update(f"JoinMessage{i}" for i in range(1,21))
    # LeaderboardSize is deliberately hidden in new presets. The config still
    # reads it so existing server presets remain backward-compatible.
    config_names.discard("LeaderboardSize")
    missing_options = sorted(config_names - option_names)
    if missing_options: fail("Config keys missing Sandbox options: " + ", ".join(missing_options))
    txt = (ROOT / "42/media/lua/shared/Translate/EN/Sandbox_EN.txt").read_text(encoding="utf-8-sig")
    data = json.loads((ROOT / "42/media/lua/shared/Translate/EN/Sandbox.json").read_text(encoding="utf-8-sig"))
    for name in sorted(option_names):
        key = f"Sandbox_{PREFIX}_{name}"
        if key not in txt: fail(f"Missing TXT translation: {key}")
        if key not in data: fail(f"Missing JSON translation: {key}")
    client = (ROOT / "42/media/lua/client/SurvivorLeagueCommunity_Client.lua").read_text(encoding="utf-8-sig")
    server = (ROOT / "42/media/lua/server/SurvivorLeagueCommunity_Server.lua").read_text(encoding="utf-8-sig")
    sent = set(re.findall(r'sendClientCommand\([^\n]*?"([A-Za-z0-9_]+)"', client))
    handled = set(re.findall(r'command\s*[~=]=\s*"([A-Za-z0-9_]+)"', server))
    if sent - handled: fail("Client commands without server handlers: " + ", ".join(sorted(sent-handled)))
    if "SurvivorLeagueCommunityScoreCorrection" not in server or "SL.AdminAPI.correctScore" not in server:
        fail("Audited administrator score correction is missing")
    if "PreviewLegacyRecovery" not in server or "SurvivorLeagueCommunityRecovery" not in server:
        fail("Read-only legacy recovery export is missing")
    if "next(value.scores)" in server or "next(value.pending)" in server or "next(value.history)" in server:
        fail("Kahlua-incompatible legacy dataset checks are present")
    if "drawTextCenteredInBox" not in client:
        fail("Font-measured box label centering is missing")
    if "textWidth(tab[2], UIFont.Small)" not in client or "wrapTwoLines" not in client:
        fail("Responsive tab sizing or two-line reward wrapping is missing")
    if "pageSize = 10" in client or "rowsPerPageForHeight" not in client:
        fail("Responsive leaderboard request sizing is missing")
    if "if index > rowsPerPage then break end" not in client:
        fail("Defensive leaderboard row clipping is missing")
    if "requestId = boardRequestSequence" not in client or "responseId < boardRequestSequence" not in client:
        fail("Stale leaderboard response protection is missing")
    if 'requestId = math.max(0, math.floor(tonumber(request.requestId) or 0))' not in server:
        fail("Server leaderboard response correlation is missing")
    if 'trackingMode = opts.allowClientKillReports' not in server or "CLIENT-FALLBACK TRACKING" not in client:
        fail("Truthful synchronization-mode reporting is missing")
    if 'fitText(string.upper(Appearance.title), 300, UIFont.Large)' in client:
        fail("Duplicate navigation-row branding still collides with search controls")
    if "serverPollTicks[key]" not in server:
        fail("Independent per-player server polling is missing")
    if "opts.clientKillMaxPerMinute" not in server or "KillReportAck" not in server:
        fail("Configured hosted kill-rate enforcement or report acknowledgements are missing")
    if "captureFinalAuthoritativeKills" not in server:
        fail("Final authoritative death synchronization is missing")
    if "rewardId = \"season:\"" not in server or "settlementInProgress" not in server:
        fail("Idempotent settlement safeguards are missing")
    if not re.search(r"InterfaceTheme\s*\{[^\n]*default\s*=\s*2", sandbox):
        fail("Meeks Protocol pink is not the default interface theme")
    if args.package:
        package = (ROOT / args.package).resolve() / "Contents/mods/SurvivorLeagueCommunity"
        compare_trees(ROOT / "42", package / "42")
        if (ROOT / "mod.info").read_bytes() != (package / "mod.info").read_bytes(): fail("Packaged root mod.info differs")
        for path in package.rglob("*"):
            if path.is_file() and forbidden(path.relative_to(package)): fail(f"Forbidden package artifact: {path.relative_to(package)}")
    if errors: raise SystemExit(1)
    print(f"Release audit passed for Survivor League Community v{version}")

if __name__ == "__main__": main()
