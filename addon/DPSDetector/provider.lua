local addonName, ns = ...

local providers = {}

local function GetExistingProvider(region)
    for i = 1, #providers do
        if providers[i].region == region then
            return providers[i]
        end
    end
end

local function BinarySearchName(names, name)
    local needle = ns.NormalizeName(name)
    local lo, hi = 1, #names
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local current = ns.NormalizeName(names[mid])
        if current == needle then
            return mid
        elseif current < needle then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
end

local function ParseMetric(packed)
    if type(packed) ~= "string" or packed == "" then
        return nil
    end

    local parts = { strsplit("|", packed) }
    local overallRaw = parts[1]
    if not overallRaw or overallRaw == "" then
        return nil
    end

    local amount, percentile, spec = strsplit(",", overallRaw)
    local record = {
        overall = {
            amount = tonumber(amount) or 0,
            percentile = tonumber(percentile) or 0,
            spec = tonumber(spec) or 0,
        },
        dungeons = {},
    }

    if record.overall.amount <= 0 then
        record.overall = nil
    end

    for i = 1, ns.GetDungeonCount() do
        local raw = parts[i + 1]
        if raw and raw ~= "" then
            local dAmount, dPercentile, dSpec = strsplit(",", raw)
            dAmount = tonumber(dAmount) or 0
            if dAmount > 0 then
                record.dungeons[i] = {
                    amount = dAmount,
                    percentile = tonumber(dPercentile) or 0,
                    spec = tonumber(dSpec) or 0,
                    dungeon = ns.DUNGEONS[i],
                }
            end
        end
    end

    if not record.overall and not next(record.dungeons) then
        return nil
    end

    return record
end

function ns.AddProvider(data)
    assert(type(data) == "table", "DPSDetector.AddProvider expects a table")
    assert(type(data.region) == "string" and type(data.date) == "string", "Provider is missing region/date")

    data.region = data.region:lower()
    local provider = GetExistingProvider(data.region)
    if provider then
        for key, value in pairs(data) do
            if provider[key] == nil then
                provider[key] = value
            elseif key == "db" or key == "lookup" then
                -- already assigned by the first file; keep the existing table
            end
        end
        -- Merge missing top-level fields from the second snapshot file.
        provider.db = provider.db or data.db
        provider.lookup = provider.lookup or data.lookup
        provider.seasonId = provider.seasonId or data.seasonId
        provider.numCharacters = provider.numCharacters or data.numCharacters
        if data.date and provider.date and data.date ~= provider.date then
            provider.desynced = true
        end
    else
        providers[#providers + 1] = data
        provider = data
    end

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

local function GetRealmTables(provider, realm)
    if not provider or not provider.db then
        return
    end

    local slug = ns.NormalizeRealm(realm)
    local names = provider.db[slug]
    if names then
        return names, provider.lookup and provider.lookup[slug], slug
    end

    -- WCL slugs sometimes keep a hyphen ("area-52"); try a few variants.
    for key, value in pairs(provider.db) do
        if ns.NormalizeRealm(key) == slug then
            return value, provider.lookup and provider.lookup[key], key
        end
    end
end

function ns.GetPlayerRecord(name, realm, region)
    if not name or not realm then
        return nil
    end

    local provider = ns.GetProvider(region)
    if not provider then
        return nil
    end

    local names, lookup = GetRealmTables(provider, realm)
    if not names or not lookup then
        return nil
    end

    local index = BinarySearchName(names, name)
    if not index then
        return nil
    end

    return {
        name = names[index],
        realm = realm,
        region = provider.region,
        date = provider.date,
        seasonId = provider.seasonId,
        damage = ParseMetric(lookup.damage and lookup.damage[index]),
        tank = ParseMetric(lookup.tank and lookup.tank[index]),
        healing = ParseMetric(lookup.healing and lookup.healing[index]),
    }
end

function ns.SelectMetric(record, role)
    if not record then
        return nil, nil
    end

    if role == ns.ROLES.HEALER then
        return record.healing, "hps"
    end

    if role == ns.ROLES.TANK then
        if record.tank then
            return record.tank, "dps"
        end
        return record.damage, "dps"
    end

    return record.damage, "dps"
end

_G.DPSDetector.AddProvider = ns.AddProvider
