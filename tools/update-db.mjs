#!/usr/bin/env node
/**
 * Builds Raider.IO-style Lua snapshot files from the Warcraft Logs v2 API.
 *
 *   set WCL_CLIENT_ID and WCL_CLIENT_SECRET
 *   node tools/update-db.mjs --region us --pages 15
 *
 * Warcraft Logs rate-limits ranking queries. This script pages rankings
 * per dungeon + spec (instead of looking up every character) and caches
 * pages under tools/.cache so you can resume.
 */

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, "..");
// Generated Lua snapshots are written into the live WoW addon folder.
const ADDON_ROOT =
  process.env.DPSDETECTOR_ADDON_ROOT ||
  "C:\\Program Files (x86)\\World of Warcraft\\_retail_\\Interface\\AddOns\\DPSDetector";
const ROOT = ADDON_ROOT;
const CACHE_DIR = join(__dirname, ".cache");
const SEASON_PATH = join(__dirname, "season.json");

const TOKEN_URL = "https://www.warcraftlogs.com/oauth/token";
const GQL_URL = "https://www.warcraftlogs.com/api/v2/client";

const args = parseArgs(process.argv.slice(2));
const season = JSON.parse(readFileSync(SEASON_PATH, "utf8"));

const PAGES = Number(args.pages ?? 15);
const DELAY_MS = Number(args.delay ?? 400);
const REGIONS = String(args.region ?? "us")
  .split(",")
  .map((value) => value.trim().toLowerCase())
  .filter(Boolean);
const DISCOVER_ONLY = Boolean(args.discover);
const SEASON_ONLY = Boolean(args["season-only"]);

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      out[key] = true;
    } else {
      out[key] = next;
      i += 1;
    }
  }
  return out;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

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

function luaArray(values) {
  return `{ ${values.join(", ")} }`;
}

function loadEnvFile() {
  const envPath = join(__dirname, ".env");
  if (!existsSync(envPath)) return;
  for (const line of readFileSync(envPath, "utf8").split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.+?)\s*$/);
    if (!match || process.env[match[1]]) continue;
    process.env[match[1]] = match[2].replace(/^["']|["']$/g, "");
  }
}

async function getToken() {
  loadEnvFile();
  const id = process.env.WCL_CLIENT_ID;
  const secret = process.env.WCL_CLIENT_SECRET;
  if (!id || !secret) {
    throw new Error("Set WCL_CLIENT_ID and WCL_CLIENT_SECRET (or tools/.env).");
  }

  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${id}:${secret}`).toString("base64")}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });

  if (!response.ok) {
    throw new Error(`OAuth failed: ${response.status} ${await response.text()}`);
  }

  const payload = await response.json();
  return payload.access_token;
}

async function graphql(token, query, variables = {}) {
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const response = await fetch(GQL_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query, variables }),
    });

    if (response.status === 429) {
      const wait = Number(response.headers.get("retry-after") || 30) * 1000;
      console.warn(`Rate limited. Waiting ${wait}ms...`);
      await sleep(wait);
      continue;
    }

    const payload = await response.json();
    if (payload.errors) {
      const message = payload.errors.map((error) => error.message).join("; ");
      if (/rate|too many/i.test(message) && attempt < 5) {
        await sleep(15000 * (attempt + 1));
        continue;
      }
      throw new Error(message);
    }

    return payload.data;
  }

  throw new Error("Warcraft Logs request failed after retries.");
}

function namesMatch(left, right) {
  const a = String(left || "").toLowerCase().replace(/[^a-z0-9]/g, "");
  const b = String(right || "").toLowerCase().replace(/[^a-z0-9]/g, "");
  return a === b || a.includes(b) || b.includes(a);
}

async function discoverEncounters(token) {
  const data = await graphql(
    token,
    `{
      worldData {
        expansions {
          id
          name
          zones {
            id
            name
            encounters { id name }
          }
        }
      }
    }`
  );

  const expansions = data.worldData.expansions || [];
  const zones = expansions.flatMap((expansion) =>
    (expansion.zones || []).map((zone) => ({
      ...zone,
      expansionName: expansion.name,
    }))
  );

  let zone = null;
  if (season.wclZoneId) {
    zone = zones.find((entry) => entry.id === season.wclZoneId);
  }
  if (!zone) {
    zone = zones.find((entry) => namesMatch(entry.name, season.wclZoneName));
  }
  if (!zone) {
    zone = zones.find((entry) =>
      /mythic\+|m\+/i.test(entry.name) && /season\s*2|s2/i.test(entry.name) && /midnight/i.test(entry.name + entry.expansionName)
    );
  }
  if (!zone) {
    const scored = zones
      .map((entry) => {
        const hits = season.dungeons.filter((dungeon) =>
          (entry.encounters || []).some((encounter) => namesMatch(encounter.name, dungeon.name))
        ).length;
        return { entry, hits };
      })
      .sort((a, b) => b.hits - a.hits);
    if (scored[0]?.hits >= 4) {
      zone = scored[0].entry;
    }
  }

  if (!zone) {
    console.log("Available zones:");
    for (const entry of zones) {
      if (/midnight|mythic|season/i.test(`${entry.expansionName} ${entry.name}`)) {
        console.log(`  [${entry.id}] ${entry.expansionName} / ${entry.name} (${(entry.encounters || []).length} encounters)`);
      }
    }
    throw new Error(`Could not find Warcraft Logs zone matching "${season.wclZoneName}". Pass wclZoneId in season.json.`);
  }

  season.wclZoneId = zone.id;
  season.wclZoneName = zone.name;
  console.log(`Using zone ${zone.id} "${zone.name}" (${zone.expansionName})`);

  for (const dungeon of season.dungeons) {
    const encounter = (zone.encounters || []).find((entry) => namesMatch(entry.name, dungeon.name));
    if (!encounter) {
      console.warn(`No encounter named "${dungeon.name}" in zone ${zone.name}`);
      continue;
    }
    dungeon.wclEncounterId = encounter.id;
    console.log(`  ${dungeon.shortName} -> encounter ${encounter.id} (${encounter.name})`);
  }

  writeFileSync(SEASON_PATH, `${JSON.stringify(season, null, 2)}\n`);
  return zone;
}

function cachePath(parts) {
  const hash = createHash("sha1").update(JSON.stringify(parts)).digest("hex");
  return join(CACHE_DIR, `${hash}.json`);
}

function readCache(parts) {
  const path = cachePath(parts);
  if (!existsSync(path)) return null;
  return JSON.parse(readFileSync(path, "utf8"));
}

function writeCache(parts, data) {
  mkdirSync(CACHE_DIR, { recursive: true });
  writeFileSync(cachePath(parts), JSON.stringify(data));
}

function rankingList(raw) {
  const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
  if (!parsed) return { rankings: [], hasMorePages: false };
  return {
    rankings: parsed.rankings || parsed.pageData?.rankings || [],
    hasMorePages: Boolean(parsed.hasMorePages),
  };
}

function rankingPercent(row) {
  return Number(row.rankPercent ?? row.percentile ?? row.historicalPercent ?? 0);
}

function rankingSpecId(row, spec) {
  return Number(row.specID ?? row.specId ?? spec.specId ?? 0);
}

function rankingServer(row) {
  if (typeof row.server === "string") return row.server;
  return row.server?.name || row.server?.slug || "";
}

async function fetchRankings(token, encounterId, spec, metric, region, page) {
  const key = {
    encounterId,
    className: spec.className,
    specName: spec.specName,
    metric,
    region,
    page,
    difficulty: season.wclDifficulty ?? null,
  };
  const cached = readCache(key);
  if (cached) return cached;

  const difficultyArg = season.wclDifficulty ? ", $difficulty: Int" : "";
  const difficultyField = season.wclDifficulty ? ", difficulty: $difficulty" : "";
  const variables = {
    encounterID: encounterId,
    page,
    serverRegion: region.toUpperCase(),
    className: spec.className,
    specName: spec.specName,
    metric,
  };
  if (season.wclDifficulty) {
    variables.difficulty = season.wclDifficulty;
  }

  const data = await graphql(
    token,
    `query Rankings($encounterID: Int!, $page: Int!, $serverRegion: String, $className: String, $specName: String, $metric: CharacterRankingMetricType${difficultyArg}) {
      worldData {
        encounter(id: $encounterID) {
          characterRankings(
            page: $page
            serverRegion: $serverRegion
            className: $className
            specName: $specName
            metric: $metric${difficultyField}
          )
        }
      }
    }`,
    variables
  );

  const parsed = rankingList(data.worldData?.encounter?.characterRankings);
  writeCache(key, parsed);
  await sleep(DELAY_MS);
  return parsed;
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
    if (!dungeon.amount) {
      parts.push("0,0,0");
    } else {
      parts.push(`${Math.round(dungeon.amount)},${Math.round(dungeon.percentile)},${dungeon.spec}`);
    }
  }
  return parts.join("|");
}

function writeSeasonLua() {
  const lines = [
    "local _, ns = ...",
    "",
    "-- Generated from tools/season.json. Edit that file, then rerun update-db.mjs.",
    "",
    "ns.SEASON = {",
    `    id = ${luaString(season.id)},`,
    `    name = ${luaString(season.name)},`,
    `    wclZoneName = ${luaString(season.wclZoneName)},`,
    `    wclZoneId = ${season.wclZoneId ?? "nil"},`,
    "}",
    "",
    "ns.ROLES = {",
    '    DAMAGER = "DAMAGER",',
    '    HEALER = "HEALER",',
    '    TANK = "TANK",',
    "}",
    "",
    "ns.DUNGEONS = {",
  ];

  for (const dungeon of season.dungeons) {
    lines.push("    {");
    lines.push(`        id = ${luaString(dungeon.id)},`);
    lines.push(`        name = ${luaString(dungeon.name)},`);
    lines.push(`        shortName = ${luaString(dungeon.shortName)},`);
    lines.push(`        rioId = ${dungeon.rioId},`);
    lines.push(`        keystoneInstance = ${dungeon.keystoneInstance},`);
    lines.push(`        instanceMapId = ${dungeon.instanceMapId},`);
    lines.push(`        lfdActivityIds = ${luaArray(dungeon.lfdActivityIds)},`);
    lines.push(`        wclEncounterId = ${dungeon.wclEncounterId ?? "nil"},`);
    lines.push("    },");
  }

  lines.push(
    "}",
    "",
    "ns.DUNGEON_BY_ACTIVITY = {}",
    "ns.DUNGEON_BY_MAP = {}",
    "ns.DUNGEON_BY_KEYSTONE = {}",
    "ns.DUNGEON_BY_ID = {}",
    "",
    "for index, dungeon in ipairs(ns.DUNGEONS) do",
    "    dungeon.index = index",
    "    ns.DUNGEON_BY_ID[dungeon.id] = dungeon",
    "    ns.DUNGEON_BY_MAP[dungeon.instanceMapId] = dungeon",
    "    ns.DUNGEON_BY_KEYSTONE[dungeon.keystoneInstance] = dungeon",
    "    for _, activityID in ipairs(dungeon.lfdActivityIds) do",
    "        ns.DUNGEON_BY_ACTIVITY[activityID] = dungeon",
    "    end",
    "end",
    "",
    "function ns.GetDungeonCount()",
    "    return #ns.DUNGEONS",
    "end",
    "",
    "function ns.GetDungeonByActivityID(activityID)",
    "    return ns.DUNGEON_BY_ACTIVITY[activityID]",
    "end",
    "",
    "function ns.GetDungeonByMapID(mapID)",
    "    return ns.DUNGEON_BY_MAP[mapID]",
    "end",
    "",
    "function ns.GetDungeonByKeystone(challengeMapID)",
    "    return ns.DUNGEON_BY_KEYSTONE[challengeMapID]",
    "end",
    ""
  );

  writeFileSync(join(ROOT, "season.lua"), lines.join("\n"));
}

function writeRegionLua(region, players) {
  const byRealm = new Map();
  for (const player of players.values()) {
    const realmKey = normalizeRealm(player.realm);
    if (!byRealm.has(realmKey)) {
      byRealm.set(realmKey, []);
    }
    byRealm.get(realmKey).push(player);
  }

  const date = new Date().toISOString().replace(/\.\d+Z$/, "Z");
  const realmKeys = [...byRealm.keys()].sort();
  let numCharacters = 0;

  const characterLines = [
    "--",
    `-- Generated snapshot for ${region.toUpperCase()} on ${date}`,
    "-- Do not edit by hand; use tools/update-db.mjs",
    "--",
    "local provider = {",
    `    name = ${luaString(`DPSDetector_DB_${region.toUpperCase()}`)},`,
    `    region = ${luaString(region)},`,
    `    date = ${luaString(date)},`,
    `    seasonId = ${luaString(season.id)},`,
    "    numCharacters = 0,",
    "    db = {},",
    "}",
    "",
  ];

  const lookupLines = [
    "--",
    `-- Generated snapshot for ${region.toUpperCase()} on ${date}`,
    "-- Do not edit by hand; use tools/update-db.mjs",
    "--",
    "local provider = {",
    `    name = ${luaString(`DPSDetector_DB_${region.toUpperCase()}`)},`,
    `    region = ${luaString(region)},`,
    `    date = ${luaString(date)},`,
    `    seasonId = ${luaString(season.id)},`,
    "    lookup = {},",
    "}",
    "",
  ];

  for (const realmKey of realmKeys) {
    const list = byRealm.get(realmKey).sort((a, b) => a.name.localeCompare(b.name, "en", { sensitivity: "base" }));
    numCharacters += list.length;
    characterLines.push(`provider.db[${luaString(realmKey)}] = { ${list.map((player) => luaString(player.name)).join(", ")} }`);
    lookupLines.push(`provider.lookup[${luaString(realmKey)}] = {`);
    lookupLines.push(`    damage = { ${list.map((player) => luaString(packMetric(player.damage))).join(", ")} },`);
    lookupLines.push(`    tank = { ${list.map((player) => luaString(packMetric(player.tank))).join(", ")} },`);
    lookupLines.push(`    healing = { ${list.map((player) => luaString(packMetric(player.healing))).join(", ")} },`);
    lookupLines.push("}");
    lookupLines.push("");
  }

  characterLines[characterLines.findIndex((line) => line.includes("numCharacters"))] = `    numCharacters = ${numCharacters},`;
  characterLines.push("", "DPSDetector.AddProvider(provider)", "");
  lookupLines.push("DPSDetector.AddProvider(provider)", "");

  writeFileSync(join(ROOT, "db", `${region}_characters.lua`), characterLines.join("\n"));
  writeFileSync(join(ROOT, "db", `${region}_lookup.lua`), lookupLines.join("\n"));
  console.log(`Wrote ${numCharacters} ${region.toUpperCase()} characters`);
}

async function collectRegion(token, region) {
  const dungeonCount = season.dungeons.length;
  const players = new Map();

  const jobs = [];
  for (const [dungeonIndex, dungeon] of season.dungeons.entries()) {
    if (!dungeon.wclEncounterId) continue;
    for (const spec of season.specs) {
      const metric = spec.role === "healer" ? "hps" : "dps";
      jobs.push({ dungeon, dungeonIndex, spec, metric });
    }
  }

  console.log(`${region.toUpperCase()}: ${jobs.length} ranking series, up to ${PAGES} pages each`);

  for (const [jobIndex, job] of jobs.entries()) {
    for (let page = 1; page <= PAGES; page += 1) {
      process.stdout.write(`\r${region.toUpperCase()} ${jobIndex + 1}/${jobs.length} ${job.dungeon.shortName} ${job.spec.className}-${job.spec.specName} p${page}   `);
      let parsed;
      try {
        parsed = await fetchRankings(token, job.dungeon.wclEncounterId, job.spec, job.metric, region, page);
      } catch (error) {
        console.warn(`\nFailed ${job.dungeon.shortName} ${job.spec.specName} p${page}: ${error.message}`);
        break;
      }

      for (const row of parsed.rankings) {
        const name = row.name;
        const realm = rankingServer(row);
        if (!name || !realm) continue;
        const key = playerKey(name, realm);
        if (!players.has(key)) {
          players.set(key, {
            name,
            realm,
            damage: emptyMetric(dungeonCount),
            tank: emptyMetric(dungeonCount),
            healing: emptyMetric(dungeonCount),
          });
        }

        const player = players.get(key);
        const amount = Number(row.amount) || 0;
        const percentile = rankingPercent(row);
        const specId = rankingSpecId(row, job.spec);
        if (job.spec.role === "healer") {
          consider(player.healing, amount, percentile, specId, job.dungeonIndex);
        } else if (job.spec.role === "tank") {
          consider(player.tank, amount, percentile, specId, job.dungeonIndex);
        } else {
          consider(player.damage, amount, percentile, specId, job.dungeonIndex);
        }
      }

      if (!parsed.hasMorePages || parsed.rankings.length === 0) {
        break;
      }
    }
  }

  console.log(`\n${region.toUpperCase()}: collected ${players.size} unique players`);
  return players;
}

async function main() {
  writeSeasonLua();
  if (SEASON_ONLY) {
    console.log("Wrote season.lua");
    return;
  }

  const token = await getToken();
  await discoverEncounters(token);
  writeSeasonLua();

  if (DISCOVER_ONLY) {
    console.log("Discovery complete. Encounter IDs saved to tools/season.json");
    return;
  }

  for (const region of REGIONS) {
    const players = await collectRegion(token, region);
    writeRegionLua(region, players);
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
