/**
 * Rebuilds Lua snapshots from tools/.cache without hitting the API.
 * Fixes percentile estimation: WCL characterRankings.count is the page
 * size (~100), not the global population.
 */
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

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
const PAGES = Number(process.argv.find((a, i, arr) => arr[i - 1] === "--pages") || 5);

function normalizeRealm(realm) {
  return String(realm || "")
    .replace(/['’\-]/g, "")
    .replace(/\s+/g, "")
    .toLowerCase();
}

function playerKey(name, realm) {
  return `${String(name).toLowerCase()}#${normalizeRealm(realm)}`;
}

function luaString(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function cachePath(parts) {
  const hash = createHash("sha1").update(JSON.stringify(parts)).digest("hex");
  return join(CACHE_DIR, `${hash}.json`);
}

function rankingServer(row) {
  if (typeof row.server === "string") return row.server;
  return row.server?.name || row.server?.slug || "";
}

function estimatePercentile(absoluteRank, page, rankingsLength, hasMorePages) {
  // When the board ends on this page, we know the exact population.
  if (!hasMorePages) {
    const total = (page - 1) * 100 + rankingsLength;
    if (total <= 0) return 0;
    return Math.max(0, Math.min(100, (100 * (total - absoluteRank + 1)) / total));
  }

  // Still more pages beyond what we fetched. Map the fetched window onto a
  // high parse band so top ranks stay gold/pink and page-5 stays ~blue.
  // Rank 1 => ~99, rank (pages*100) => ~50.
  const window = Math.max(PAGES * 100, absoluteRank);
  return Math.max(50, Math.min(99, 100 - ((absoluteRank - 1) / window) * 50));
}

function emptyMetric(dungeonCount) {
  return {
    overall: { amount: 0, percentile: 0, spec: 0 },
    dungeons: Array.from({ length: dungeonCount }, () => ({ amount: 0, percentile: 0, spec: 0 })),
  };
}

function consider(slot, amount, percentile, specId, dungeonIndex) {
  if (!amount || amount <= 0) return;
  const current = slot.dungeons[dungeonIndex];
  if (amount > current.amount) {
    slot.dungeons[dungeonIndex] = { amount, percentile, spec: specId };
  }
  if (amount > slot.overall.amount) {
    slot.overall = { amount, percentile, spec: specId };
  }
}

function packMetric(slot) {
  if (!slot || slot.overall.amount <= 0) return "";
  const parts = [
    `${Math.round(slot.overall.amount)},${Math.round(slot.overall.percentile)},${slot.overall.spec}`,
  ];
  for (const dungeon of slot.dungeons) {
    if (!dungeon.amount) parts.push("0,0,0");
    else parts.push(`${Math.round(dungeon.amount)},${Math.round(dungeon.percentile)},${dungeon.spec}`);
  }
  return parts.join("|");
}

const dungeonCount = season.dungeons.length;
const players = new Map();
let loadedPages = 0;
let missingPages = 0;

for (const [dungeonIndex, dungeon] of season.dungeons.entries()) {
  if (!dungeon.wclEncounterId) continue;
  for (const spec of season.specs) {
    const metric = spec.role === "healer" ? "hps" : "dps";
    for (let page = 1; page <= PAGES; page += 1) {
      const key = {
        encounterId: dungeon.wclEncounterId,
        className: spec.className,
        specName: spec.specName,
        metric,
        region: REGION,
        page,
        difficulty: season.wclDifficulty ?? null,
      };
      const path = cachePath(key);
      if (!existsSync(path)) {
        missingPages += 1;
        break;
      }
      const parsed = JSON.parse(readFileSync(path, "utf8"));
      loadedPages += 1;
      const rankings = parsed.rankings || [];
      for (const [rowIndex, row] of rankings.entries()) {
        const name = row.name;
        const realm = rankingServer(row);
        if (!name || !realm) continue;
        const pk = playerKey(name, realm);
        if (!players.has(pk)) {
          players.set(pk, {
            name,
            realm,
            damage: emptyMetric(dungeonCount),
            tank: emptyMetric(dungeonCount),
            healing: emptyMetric(dungeonCount),
          });
        }
        const player = players.get(pk);
        const amount = Number(row.amount) || 0;
        const absoluteRank = ((parsed.page || page) - 1) * 100 + rowIndex + 1;
        const percentile = estimatePercentile(
          absoluteRank,
          parsed.page || page,
          rankings.length,
          Boolean(parsed.hasMorePages)
        );
        const specId = Number(row.specID ?? row.specId ?? spec.specId ?? 0);
        if (spec.role === "healer") consider(player.healing, amount, percentile, specId, dungeonIndex);
        else if (spec.role === "tank") consider(player.tank, amount, percentile, specId, dungeonIndex);
        else consider(player.damage, amount, percentile, specId, dungeonIndex);
      }
      if (!parsed.hasMorePages || rankings.length === 0) break;
    }
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
