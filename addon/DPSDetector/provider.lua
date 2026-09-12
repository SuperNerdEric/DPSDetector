local addonName, ns = ...

local providers = {}

local REGION_PACKS = {
    us = "DPSDetector_DB_US",
    eu = "DPSDetector_DB_EU",
    kr = "DPSDetector_DB_KR",
    tw = "DPSDetector_DB_TW",
}

local function GetExistingProvider(region)
    for i = 1, #providers do
        if providers[i].region == region then
            return providers[i]
        end
    end
end

local function CompareNames(a, b)
    if strcmputf8i then
        return strcmputf8i(a, b)
    end
    a, b = ns.NormalizeName(a), ns.NormalizeName(b)
    if a == b then
        return 0
    end
    return a < b and -1 or 1
end

-- Raider.IO: binary search with strcmputf8i on a list sorted by the same compare.
local function BinarySearchName(names, name)
    local lo, hi = 1, #names
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local cmp = CompareNames(names[mid], name)
        if cmp == 0 then
            return mid
        elseif cmp < 0 then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
end

local function PermuteArray(source, order)
    if not source then
        return
    end
    local dest = {}
    for i = 1, #order do
        dest[i] = source[order[i]]
    end
    return dest
end

-- Generator sort (JS localeCompare) is not guaranteed to match strcmputf8i.
-- Re-order each realm so search and storage use the same compare.
local function SortProviderRealms(provider)
    if not provider or not provider.db or not provider.lookup or provider.sorted then
        return
    end

    for realm, names in pairs(provider.db) do
        local order = {}
        for i = 1, #names do
            order[i] = i
        end
        table.sort(order, function(i, j)
            return CompareNames(names[i], names[j]) < 0
        end)

        local changed = false
        for i = 1, #order do
            if order[i] ~= i then
                changed = true
                break
            end
        end
        if changed then
            provider.db[realm] = PermuteArray(names, order)
            local lookup = provider.lookup[realm]
            if lookup then
                lookup.damage = PermuteArray(lookup.damage, order)
                lookup.tank = PermuteArray(lookup.tank, order)
                lookup.healing = PermuteArray(lookup.healing, order)
            end
        end
    end

    provider.sorted = true
end

local function ParseParse(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end

    local amount, specOrPct, dungeonOrSpec, level = strsplit(",", raw)
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return nil
    end

    -- New: amount,spec,dungeonIndex,level  Old: amount,percentile,spec
    local spec, dungeonIndex, keyLevel
    if level ~= nil then
        spec = tonumber(specOrPct) or 0
        dungeonIndex = tonumber(dungeonOrSpec) or 0
        keyLevel = tonumber(level) or 0
    else
        spec = tonumber(dungeonOrSpec) or 0
        dungeonIndex = 0
        keyLevel = 0
    end

    return {
        amount = amount,
        spec = spec,
        dungeonIndex = dungeonIndex,
        level = keyLevel,
        dungeon = dungeonIndex > 0 and ns.DUNGEONS[dungeonIndex] or nil,
    }
end

local function ParseSlot(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end

    local keyRaw, peakRaw = strsplit(";", raw)
    local key = ParseParse(keyRaw)
    if not key then
        return nil
    end

    local peak = ParseParse(peakRaw)
    if peak and (peak.level >= key.level or peak.amount <= key.amount) then
        peak = nil
    end

    return {
        key = key,
        peak = peak,
        amount = key.amount,
        spec = key.spec,
        level = key.level,
        dungeon = key.dungeon,
    }
end

local function ParseMetric(packed)
    if type(packed) ~= "string" or packed == "" then
        return nil
    end

    local parts = { strsplit("|", packed) }
    local overall = ParseSlot(parts[1])
    local record = {
        overall = overall,
        key = overall and overall.key,
        peak = overall and overall.peak,
        dungeons = {},
    }

    for i = 1, ns.GetDungeonCount() do
        local slot = ParseSlot(parts[i + 1])
        if slot then
            slot.dungeon = ns.DUNGEONS[i]
            if slot.key and not slot.key.dungeon then
                slot.key.dungeon = ns.DUNGEONS[i]
            end
            if slot.peak and not slot.peak.dungeon then
                slot.peak.dungeon = ns.DUNGEONS[i]
            end
            record.dungeons[i] = slot
        end
    end

    if not record.overall and not next(record.dungeons) then
        return nil
    end

    return record
end

local function MergeMaps(dest, src)
    if type(src) ~= "table" then
        return dest
    end
    dest = dest or {}
    for key, value in pairs(src) do
        dest[key] = value
    end
    return dest
end

function ns.AddProvider(data)
    assert(type(data) == "table", "DPSDetector.AddProvider expects a table")
    assert(type(data.region) == "string" and type(data.date) == "string", "Provider is missing region/date")

    data.region = data.region:lower()
    local provider = GetExistingProvider(data.region)
    if provider then
        for key, value in pairs(data) do
            if key ~= "db" and key ~= "lookup" and provider[key] == nil then
                provider[key] = value
            end
        end
        provider.db = MergeMaps(provider.db, data.db)
        provider.lookup = MergeMaps(provider.lookup, data.lookup)
        provider.seasonId = provider.seasonId or data.seasonId
        provider.numCharacters = provider.numCharacters or data.numCharacters
        if data.date and provider.date and data.date ~= provider.date then
            provider.desynced = true
        end
        provider.sorted = nil
    else
        providers[#providers + 1] = data
        provider = data
    end

    SortProviderRealms(provider)
    return true
end

function ns.GetProviders()
    return providers
end

function ns.GetProvider(region)
    region = (region or ns.PLAYER_REGION or "us"):lower()
    return GetExistingProvider(region)
end

function ns.GetProviderDate(region)
    local provider = ns.GetProvider(region)
    return provider and provider.date
end

function ns.HasProvider(region)
    local provider = ns.GetProvider(region)
    return provider and provider.db and provider.lookup
end

function ns.EnsureRegionDatabase(region)
    region = (region or ns.PLAYER_REGION or "us"):lower()
    if ns.HasProvider(region) then
        return true
    end

    local pack = REGION_PACKS[region]
    if not pack then
        return false
    end

    local enable = C_AddOns and C_AddOns.EnableAddOn or EnableAddOn
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

    if enable then
        pcall(enable, pack)
    end
    if load and not (isLoaded and isLoaded(pack)) then
        pcall(load, pack)
    end

    return ns.HasProvider(region)
end

local function GetRealmTables(provider, realm)
    if not provider or not provider.db then
        return
    end

    local slug = ns.NormalizeRealm(realm)
    local names = provider.db[slug]
    if names then
        return names, provider.lookup and provider.lookup[slug], slug
    end

    -- Raider.IO falls back to strcmputf8i when the exact realm key misses.
    for key, value in pairs(provider.db) do
        if ns.NormalizeRealm(key) == slug or CompareNames(key, slug) == 0 or CompareNames(key, realm) == 0 then
            return value, provider.lookup and provider.lookup[key], key
        end
    end
end

function ns.GetPlayerRecord(name, realm, region)
    if not name or not realm then
        return nil, "missing-name"
    end

    ns.EnsureRegionDatabase(region)

    local provider = ns.GetProvider(region)
    if not provider then
        return nil, "no-provider"
    end
    if not provider.lookup then
        return nil, "no-lookup"
    end

    SortProviderRealms(provider)

    local function RecordAt(realmKey, realmNames, realmLookup, index)
        return {
            name = realmNames[index],
            realm = realmKey,
            region = provider.region,
            date = provider.date,
            seasonId = provider.seasonId,
            damage = ParseMetric(realmLookup.damage and realmLookup.damage[index]),
            tank = ParseMetric(realmLookup.tank and realmLookup.tank[index]),
            healing = ParseMetric(realmLookup.healing and realmLookup.healing[index]),
        }
    end

    local names, lookup, realmKey = GetRealmTables(provider, realm)
    if names and lookup then
        local index = BinarySearchName(names, name)
        if index then
            return RecordAt(realmKey or realm, names, lookup, index)
        end
    end

    -- BNet often reports a connected-realm name that is not the WCL realm.
    local matchKey, matchNames, matchLookup, matchIndex
    for key, realmNames in pairs(provider.db) do
        local realmLookup = provider.lookup[key]
        if realmLookup then
            local index = BinarySearchName(realmNames, name)
            if index then
                if matchIndex then
                    return nil, "ambiguous-name"
                end
                matchKey, matchNames, matchLookup, matchIndex = key, realmNames, realmLookup, index
            end
        end
    end
    if matchIndex then
        return RecordAt(matchKey, matchNames, matchLookup, matchIndex)
    end

    if not names then
        return nil, "no-realm"
    end
    return nil, "no-name"
end

local function MetricHasData(metricSet)
    if not metricSet then
        return false
    end
    local slot = metricSet.overall or metricSet
    local parse = slot and (slot.key or slot)
    return parse and parse.amount and parse.amount > 0
end

function ns.SelectMetric(record, role)
    if not record then
        return nil, nil
    end

    local order
    if role == ns.ROLES.HEALER then
        order = { { record.healing, "hps" }, { record.damage, "dps" }, { record.tank, "dps" } }
    elseif role == ns.ROLES.TANK then
        order = { { record.tank, "dps" }, { record.damage, "dps" }, { record.healing, "hps" } }
    else
        order = { { record.damage, "dps" }, { record.healing, "hps" }, { record.tank, "dps" } }
    end

    for i = 1, #order do
        if MetricHasData(order[i][1]) then
            return order[i][1], order[i][2]
        end
    end
end

_G.DPSDetector.AddProvider = ns.AddProvider
