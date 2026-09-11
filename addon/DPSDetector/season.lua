local _, ns = ...

-- Generated from tools/season.json. Edit that file, then rerun update-db.mjs.

ns.SEASON = {
    id = "mn-2",
    name = "Midnight Season 2",
    wclZoneName = "Mythic+ Season 2",
    wclZoneId = 55,
}

ns.ROLES = {
    DAMAGER = "DAMAGER",
    HEALER = "HEALER",
    TANK = "TANK",
}

ns.DUNGEONS = {
    {
        id = "KR",
        name = "Kings' Rest",
        shortName = "KR",
        rioId = 9526,
        keystoneInstance = 249,
        instanceMapId = 1762,
        lfdActivityIds = { 512, 513, 514, 515, 660, 661 },
        wclEncounterId = 61762,
    },
    {
        id = "TOS",
        name = "Temple of Sethraliss",
        shortName = "TOS",
        rioId = 9527,
        keystoneInstance = 250,
        instanceMapId = 1877,
        lfdActivityIds = { 503, 504, 505, 542, 645 },
        wclEncounterId = 61877,
    },
    {
        id = "RLP",
        name = "Ruby Life Pools",
        shortName = "RLP",
        rioId = 14063,
        keystoneInstance = 399,
        instanceMapId = 2521,
        lfdActivityIds = { 1173, 1174, 1175, 1176 },
        wclEncounterId = 112521,
    },
    {
        id = "MR",
        name = "Murder Row",
        shortName = "MR",
        rioId = 16091,
        keystoneInstance = 587,
        instanceMapId = 2813,
        lfdActivityIds = { 1749, 1750, 1751, 1950 },
        wclEncounterId = 12813,
    },
    {
        id = "BV",
        name = "The Blinding Vale",
        shortName = "BV",
        rioId = 16359,
        keystoneInstance = 584,
        instanceMapId = 2859,
        lfdActivityIds = { 1699, 1700, 1701, 1949 },
        wclEncounterId = 12859,
    },
    {
        id = "DON",
        name = "Den of Nalorakk",
        shortName = "DON",
        rioId = 16368,
        keystoneInstance = 586,
        instanceMapId = 2825,
        lfdActivityIds = { 1721, 1722, 1723, 1952 },
        wclEncounterId = 12825,
    },
    {
        id = "VSA",
        name = "Voidscar Arena",
        shortName = "VSA",
        rioId = 16425,
        keystoneInstance = 585,
        instanceMapId = 2923,
        lfdActivityIds = { 1754, 1755, 1756, 1951 },
        wclEncounterId = 12923,
    },
    {
        id = "AOF",
        name = "Altar of Fangs",
        shortName = "AOF",
        rioId = 16865,
        keystoneInstance = 588,
        instanceMapId = 2993,
        lfdActivityIds = { 1930, 1931, 1932, 1933 },
        wclEncounterId = 12993,
    },
}

ns.DUNGEON_BY_ACTIVITY = {}
ns.DUNGEON_BY_MAP = {}
ns.DUNGEON_BY_KEYSTONE = {}
ns.DUNGEON_BY_ID = {}

for index, dungeon in ipairs(ns.DUNGEONS) do
    dungeon.index = index
    ns.DUNGEON_BY_ID[dungeon.id] = dungeon
    ns.DUNGEON_BY_MAP[dungeon.instanceMapId] = dungeon
    ns.DUNGEON_BY_KEYSTONE[dungeon.keystoneInstance] = dungeon
    for _, activityID in ipairs(dungeon.lfdActivityIds) do
        ns.DUNGEON_BY_ACTIVITY[activityID] = dungeon
    end
end

function ns.GetDungeonCount()
    return #ns.DUNGEONS
end

function ns.GetDungeonByActivityID(activityID)
    return ns.DUNGEON_BY_ACTIVITY[activityID]
end

function ns.GetDungeonByMapID(mapID)
    return ns.DUNGEON_BY_MAP[mapID]
end

function ns.GetDungeonByKeystone(challengeMapID)
    return ns.DUNGEON_BY_KEYSTONE[challengeMapID]
end
