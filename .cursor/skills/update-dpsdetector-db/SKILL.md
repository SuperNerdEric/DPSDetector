---
name: update-dpsdetector-db
description: >-
  Updates DPS Detector Warcraft Logs Mythic+ ranking snapshots for a region,
  regenerates bundled Lua DB files under addon/, and optionally syncs into the
  live WoW AddOns folder. Use when the user asks to refresh DPS Detector data,
  rebuild the US/Americas (or eu/kr/tw) database, run the WCL crawl, sync the
  addon into WoW, or maintain the GitHub Action snapshot pipeline.
disable-model-invocation: true
---

# Update DPS Detector DB

## Layout

Monorepo root: `C:\Users\Eric\Projects\DPSDetector` (or the opened repo root).

| Path | Purpose |
| --- | --- |
| `addon/DPSDetector/` | Core WoW addon (copy this folder into `Interface/AddOns/`) |
| `addon/DPSDetector_DB_US/` | Americas region pack TOC (sibling folder in AddOns) |
| `addon/DPSDetector_DB_EU/` etc. | Other region packs (same pattern) |
| `tools/update-db.mjs` | WCL crawl → Lua snapshot writer |
| `tools/rebuild-from-cache.mjs` | Rebuild Lua from `tools/.cache` (no API) |
| `tools/.env` | Local secrets only (`WCL_CLIENT_ID`, `WCL_CLIENT_SECRET`) |
| `scripts/sync-to-wow.ps1` | Copies `addon/*` packs into the live AddOns directory |

The crawl is **region-specific**. Americas = `us` (aliases: `americas`, `na`, `oceanic`).

## Credentials

Local: `tools/.env` (gitignored)

```
WCL_CLIENT_ID=...
WCL_CLIENT_SECRET=...
```

GitHub Actions repo secrets (Settings → Secrets and variables → Actions):

- `WCL_CLIENT_ID`
- `WCL_CLIENT_SECRET`

Never write secrets into `addon/` or the WoW AddOns tree.

## Refresh a region (API crawl)

Default pacing is safe for the free 3600 points/hour budget:

```powershell
cd tools
node update-db.mjs --discover
node update-db.mjs --region us --pages 5 --delay 1200
```

Americas alias works the same:

```powershell
node update-db.mjs --region americas --pages 5 --delay 1200
```

Other regions later:

```powershell
node update-db.mjs --region eu --pages 5 --delay 1200
```

Outputs (bundled into the addon tree automatically):

- `addon/DPSDetector/db/<region>_characters.lua`
- `addon/DPSDetector/db/<region>_lookup.lua`
- `addon/DPSDetector/season.lua` (from `tools/season.json`)

## Rebuild from cache only

If `.cache` already has pages and you only need to regenerate Lua:

```powershell
cd tools
node rebuild-from-cache.mjs --region us --pages 5
```

## Sync into WoW for testing

```powershell
powershell -File scripts/sync-to-wow.ps1 -Regions us
```

Then `/reload` in-game. Enable **DPS Detector** and **DPS Detector Database (Americas)**.

## GitHub Actions

- `update-us.yml` — scheduled + manual Americas crawl
- `update-region.yml` — reusable / manual chooser for `us|eu|kr|tw`

After a successful run the workflow commits refreshed Lua under `addon/DPSDetector/db/`.

## Agent checklist

1. Confirm region (`us` for Americas unless user specifies otherwise)
2. Ensure `tools/.env` exists locally (do not print secrets)
3. Run discover, then region crawl with `--delay 1200` (or rebuild-from-cache if requested)
4. Verify `addon/DPSDetector/db/<region>_*.lua` timestamps/sizes
5. If the user wants in-game testing, run `scripts/sync-to-wow.ps1`
6. Do not commit `tools/.env` or `tools/.cache/`
