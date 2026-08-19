#!/usr/bin/env python3
from __future__ import annotations
import argparse
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN_SUFFIXES = {".bak", ".old", ".tmp", ".zip"}

def forbidden(path: Path) -> bool:
    lower_parts = [part.lower() for part in path.parts]
    return path.suffix.lower() in FORBIDDEN_SUFFIXES or any("backup" in part for part in lower_parts)

def main() -> None:
    parser = argparse.ArgumentParser(description="Build a clean Survivor League Workshop package.")
    parser.add_argument("--output", default="dist/SurvivorLeagueCommunity-Workshop")
    args = parser.parse_args()
    output = (ROOT / args.output).resolve()
    if output.exists(): shutil.rmtree(output)
    mod_root = output / "Contents/mods/SurvivorLeagueCommunity"
    mod_root.mkdir(parents=True)
    shutil.copy2(ROOT / "mod.info", mod_root / "mod.info")
    shutil.copytree(ROOT / "42", mod_root / "42")
    bad = [p for p in mod_root.rglob("*") if p.is_file() and forbidden(p.relative_to(mod_root))]
    if bad: raise SystemExit("Forbidden release artifacts: " + ", ".join(str(p) for p in bad))
    print(output)

if __name__ == "__main__": main()
