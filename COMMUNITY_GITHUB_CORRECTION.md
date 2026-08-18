# GitHub correction and unified v1.6.0 release

The public commit titled v1.4.0 accidentally added only an empty repository-root file named `type`. Before publishing v1.6.0:

1. Remove `type` without adding it to the release.
2. Replace the repository from the prepared unified GitHub source archive.
3. Confirm both `mod.info` files report `1.6.0`.
4. Parse all Lua files and validate `Sandbox.json`.
5. Test a fresh Community world, a copied Meeks world, and a deliberate dual-dataset conflict.

Suggested commands after copying the source:

```text
git rm --ignore-unmatch type
git add -A
git commit -m "Unify Survivor League v1.6.0"
git tag -a v1.6.0 -m "Unified Survivor League v1.6.0"
git push origin main
git push origin v1.6.0
```

Do not publish the retired Meeks migration package until the live Meeks server has switched to Workshop `3784151798` and Mod ID `SurvivorLeagueCommunity`.
