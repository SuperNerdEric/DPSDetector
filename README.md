# DPS Detector

Shared repo for the **WoW addon** and the **Warcraft Logs snapshot pipeline**.

## Layout

```
addon/DPSDetector/           # Core addon — copy this folder into Interface/AddOns/
addon/DPSDetector_DB_US/     # Americas DB pack (sibling folder in AddOns)
addon/DPSDetector_DB_EU/     # Europe pack (empty until crawled)
addon/DPSDetector_DB_KR/
addon/DPSDetector_DB_TW/
tools/                       # Offline WCL crawler (region-specific)
scripts/sync-to-wow.ps1      # Copy addon packs into your live AddOns folder
.github/workflows/           # Region-specific snapshot jobs
```

Install for testing:

```powershell
powershell -File scripts/sync-to-wow.ps1 -Regions us
```

Or copy `addon/DPSDetector` and `addon/DPSDetector_DB_US` into:

`...\World of Warcraft\_retail_\Interface\AddOns\`

## Region-specific crawls

Americas / US (default):

```powershell
cd tools
node update-db.mjs --discover
node update-db.mjs --region us --pages 5 --delay 1200
```

Aliases for Americas: `us`, `americas`, `na`, `oceanic`.

The crawler only requests `serverRegion` for the chosen region and only rewrites that region’s Lua files.

## Local secrets

Create `tools/.env` (gitignored):

```
WCL_CLIENT_ID=...
WCL_CLIENT_SECRET=...
```

## GitHub Actions secrets

Repo → **Settings → Secrets and variables → Actions** → New repository secret:

| Secret name | Value |
| --- | --- |
| `WCL_CLIENT_ID` | Your WCL API client id |
| `WCL_CLIENT_SECRET` | Your WCL API client secret |

Workflows:

- **Update WCL Snapshot (US / Americas)** — daily + manual
- **Update region snapshot (reusable)** — manual region picker (`us` / `eu` / `kr` / `tw`)

Each run discovers encounters, crawls that region, writes Lua under `addon/DPSDetector/db/`, and commits the bundled data.

## In-game

`/reload`, enable both addons, then:

```
/dpsd status
/dpsd search Name Realm
```

## Cursor skill

Project skill: `.cursor/skills/update-dpsdetector-db/` — use when asking the agent to refresh or sync DPS Detector data.
