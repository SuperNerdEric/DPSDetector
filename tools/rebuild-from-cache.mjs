/**
 * Rebuilds Lua snapshots from tools/.cache without hitting the API.
 */
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  buildSpecIndex,
  ingestRow,
  luaString,
  normalizeRealm,
  packMetric,
  rankingCacheKey,
} from "./snapshot-lib.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ADDON_ROOT =
  process.env.DPSDETECTOR_ADDON_ROOT ||
  join(__dirname, "..", "addon", "DPSDetector");
const CACHE_DIR = join(__dirname, ".cache");
const season = JSON.parse(readFileSync(join(__dirname, "season.json"), "utf8"));

const REGION_ALIASES = {
  us: "us",
  americas: "us",
  na: "us",
  oceanic: "us",
  eu: "eu",
  europe: "eu",
  kr: "kr",
  korea: "kr",
  tw: "tw",
  taiwan: "tw",
};

function normalizeRegion(value) {
  const key = String(value || "us").trim().toLowerCase();
  return REGION_ALIASES[key] || key;
}

const REGION = normalizeRegion(
  process.argv.find((a, i, arr) => arr[i - 1] === "--region") || "us"
);
const PAGES = Number(process.argv.find((a, i, arr) => arr[i - 1] === "--pages") || 20);

function cachePath(parts) {
  const hash = createHash("sha1").update(JSON.stringify(parts)).digest("hex");
  return join(CACHE_DIR, `${hash}.json`);
}

const dungeonCount = season.dungeons.length;
const specIndex = buildSpecIndex(season.specs);
const players = new Map();
let loadedPages = 0;
let missingPages = 0;

function seriesList() {
  const series = [];
  for (const [dungeonIndex, dungeon] of season.dungeons.entries()) {
    if (!dungeon.wclEncounterId) continue;
    for (const metric of ["dps", "hps"]) {
      series.push({ dungeon, dungeonIndex, metric, className: null, specName: null, bracket: null });
    }
    for (const spec of season.specs) {
      for (const metric of ["dps", "hps"]) {
        series.push({
          dungeon,
          dungeonIndex,
          metric,
          className: spec.className,
          specName: spec.specName,
          bracket: null,
        });
      }
    }
    for (let bracket = 1; bracket <= 30; bracket += 1) {
      for (const metric of ["dps", "hps"]) {
        series.push({
          dungeon,
          dungeonIndex,
          metric,
          className: null,
          specName: null,
          bracket,
        });
      }
    }
  }
  return series;
}

for (const series of seriesList()) {
  for (let page = 1; page <= PAGES; page += 1) {
    const key = rankingCacheKey({
      encounterId: series.dungeon.wclEncounterId,
      className: series.className,
      specName: series.specName,
      metric: series.metric,
      region: REGION,
      page,
      difficulty: season.wclDifficulty ?? null,
      bracket: series.bracket,
    });
    const path = cachePath(key);
    if (!existsSync(path)) {
      missingPages += 1;
      break;
    }
    const parsed = JSON.parse(readFileSync(path, "utf8"));
    loadedPages += 1;
    const rankings = parsed.rankings || [];
    for (const row of rankings) {
      ingestRow(players, row, specIndex, dungeonCount, series.dungeonIndex, series.metric);
    }
    if (!parsed.hasMorePages || rankings.length === 0) break;
  }
}

const byRealm = new Map();
for (const player of players.values()) {
  const realmKey = normalizeRealm(player.realm);
  if (!byRealm.has(realmKey)) byRealm.set(realmKey, []);
  byRealm.get(realmKey).push(player);
}

const date = new Date().toISOString().replace(/\.\d+Z$/, "Z");
const realmKeys = [...byRealm.keys()].sort();
let numCharacters = 0;

const characterLines = [
  "--",
  `-- Generated snapshot for ${REGION.toUpperCase()} on ${date}`,
  "-- Do not edit by hand; use tools/update-db.mjs / rebuild-from-cache.mjs",
  "--",
  "local provider = {",
  `    name = ${luaString(`DPSDetector_DB_${REGION.toUpperCase()}`)},`,
  `    region = ${luaString(REGION)},`,
  `    date = ${luaString(date)},`,
  `    seasonId = ${luaString(season.id)},`,
  "    numCharacters = 0,",
  "    db = {},",
  "}",
  "",
];

const lookupLines = [
  "--",
  `-- Generated snapshot for ${REGION.toUpperCase()} on ${date}`,
  "-- Do not edit by hand; use tools/update-db.mjs / rebuild-from-cache.mjs",
  "--",
  "local provider = {",
  `    name = ${luaString(`DPSDetector_DB_${REGION.toUpperCase()}`)},`,
  `    region = ${luaString(REGION)},`,
  `    date = ${luaString(date)},`,
  `    seasonId = ${luaString(season.id)},`,
  "    lookup = {},",
  "}",
  "",
];

for (const realmKey of realmKeys) {
  const list = byRealm
    .get(realmKey)
    .sort((a, b) => a.name.localeCompare(b.name, "en", { sensitivity: "base" }));
  numCharacters += list.length;
  characterLines.push(
    `provider.db[${luaString(realmKey)}] = { ${list.map((p) => luaString(p.name)).join(", ")} }`
  );
  lookupLines.push(`provider.lookup[${luaString(realmKey)}] = {`);
  lookupLines.push(`    damage = { ${list.map((p) => luaString(packMetric(p.damage))).join(", ")} },`);
  lookupLines.push(`    tank = { ${list.map((p) => luaString(packMetric(p.tank))).join(", ")} },`);
  lookupLines.push(`    healing = { ${list.map((p) => luaString(packMetric(p.healing))).join(", ")} },`);
  lookupLines.push("}");
  lookupLines.push("");
}

characterLines[characterLines.findIndex((l) => l.includes("numCharacters"))] =
  `    numCharacters = ${numCharacters},`;
characterLines.push("", "DPSDetector.AddProvider(provider)", "");
lookupLines.push("DPSDetector.AddProvider(provider)", "");

mkdirSync(join(ADDON_ROOT, "db"), { recursive: true });
writeFileSync(join(ADDON_ROOT, "db", `${REGION}_characters.lua`), characterLines.join("\n"));
writeFileSync(join(ADDON_ROOT, "db", `${REGION}_lookup.lua`), lookupLines.join("\n"));

console.log(`Loaded ${loadedPages} cached pages (${missingPages} gaps)`);
console.log(`Wrote ${numCharacters} ${REGION.toUpperCase()} characters`);
