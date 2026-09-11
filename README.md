# DPS Detector (tools + credentials)

This folder holds the **Warcraft Logs snapshot pipeline** and secrets.
The playable WoW addon stays in:

`C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\DPSDetector`

## Secrets

Credentials live only in `tools/.env` (gitignored). Never copy them into the AddOns tree.

```
WCL_CLIENT_ID=...
WCL_CLIENT_SECRET=...
```

## Commands

```powershell
cd C:\Users\Eric\Projects\DPSDetector\tools
node update-db.mjs --discover
node update-db.mjs --region us --pages 15
```

Optional: override the addon output path

```powershell
$env:DPSDETECTOR_ADDON_ROOT = "C:\path\to\DPSDetector"
```
