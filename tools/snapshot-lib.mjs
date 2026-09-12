/** Shared snapshot packing for update-db.mjs and rebuild-from-cache.mjs. */

export function foldName(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

export function normalizeRealm(realm) {
  return String(realm || "")
    .replace(/['’\-]/g, "")
    .replace(/\s+/g, "")
    .toLowerCase();
}

export function playerKey(name, realm) {
  return `${String(name).toLowerCase()}#${normalizeRealm(realm)}`;
}

export function luaString(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

export function rankingServer(row) {
  if (typeof row.server === "string") return row.server;
  return row.server?.name || row.server?.slug || "";
}

export function rankingLevel(row) {
  return Number(row.hardModeLevel ?? row.bracketData ?? row.level ?? 0) || 0;
}

export function buildSpecIndex(specs) {
  const byFolded = new Map();
  for (const spec of specs) {
    byFolded.set(`${foldName(spec.className)}#${foldName(spec.specName)}`, spec);
  }
  return byFolded;
}

export function specFromRow(row, specIndex) {
  if (!row || !specIndex) return null;
  return specIndex.get(`${foldName(row.class)}#${foldName(row.spec)}`) || null;
}

export function emptyMetric(dungeonCount) {
  return {
    overall: { key: null, peak: null },
    dungeons: Array.from({ length: dungeonCount }, () => ({ key: null, peak: null })),
  };
}

function betterKey(current, next) {
  if (!current) return true;
  if (next.level > current.level) return true;
  if (next.level === current.level && next.amount > current.amount) return true;
  return false;
}

function applyParse(target, parse) {
  if (betterKey(target.key, parse)) {
    target.key = { ...parse };
  }
  if (!target.peak || parse.amount > target.peak.amount) {
    target.peak = { ...parse };
  }
}

export function consider(slot, amount, specId, dungeonIndex, level) {
  if (!amount || amount <= 0) return;
  const parse = {
    amount,
    spec: specId || 0,
    dungeon: dungeonIndex + 1,
    level: level || 0,
  };
  applyParse(slot.overall, parse);
  applyParse(slot.dungeons[dungeonIndex], parse);
}

export function shouldShowPeak(key, peak) {
  return Boolean(
    key &&
      peak &&
      peak.level < key.level &&
      peak.amount > key.amount + 0.5
  );
}

function packParse(parse) {
  if (!parse || !parse.amount) return "";
  return `${Math.round(parse.amount)},${parse.spec || 0},${parse.dungeon || 0},${parse.level || 0}`;
}

export function packSlot(slot) {
  if (!slot?.key?.amount) return "";
  const key = packParse(slot.key);
  if (shouldShowPeak(slot.key, slot.peak)) {
    return `${key};${packParse(slot.peak)}`;
  }
  return key;
}

export function packMetric(slot) {
  if (!slot?.overall?.key?.amount) return "";
  const parts = [packSlot(slot.overall)];
  for (const dungeon of slot.dungeons) {
    parts.push(packSlot(dungeon));
  }
  return parts.join("|");
}

export function slotForRole(player, spec, metric) {
  if (!spec) return null;
  if (metric === "hps") {
    return spec.role === "healer" ? player.healing : null;
  }
  if (spec.role === "tank") return player.tank;
  if (spec.role === "dps") return player.damage;
  return null;
}

export function metricForSpec(spec) {
  return spec.role === "healer" ? "hps" : "dps";
}

export function rankingCacheKey({
  encounterId,
  className = null,
  specName = null,
  metric,
  region,
  page,
  difficulty = null,
  bracket = null,
}) {
  const key = {
    encounterId,
    className,
    specName,
    metric,
    region,
    page,
    difficulty,
  };
  if (bracket != null) key.bracket = Number(bracket);
  return key;
}

export function ingestRow(players, row, specIndex, dungeonCount, dungeonIndex, metric) {
  const name = row?.name;
  const realm = rankingServer(row);
  const spec = specFromRow(row, specIndex);
  if (!name || !realm || !spec) return;
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
  const slot = slotForRole(players.get(key), spec, metric);
  if (!slot) return;
  consider(slot, Number(row.amount) || 0, spec.specId, dungeonIndex, rankingLevel(row));
}
