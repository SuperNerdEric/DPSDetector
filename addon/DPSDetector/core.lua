local addonName, ns = ...

ns.addonName = addonName
ns.ADDON_TITLE = "DPS Detector"
ns.VERSION = "1.0.0"

---@class DPSDetectorNamespace
ns.PLAYER_REGION = nil
ns.PLAYER_REALM = nil
ns.PLAYER_NAME = nil

local REGION_BY_ID = {
    [1] = "us",
    [2] = "kr",
    [3] = "eu",
    [4] = "tw",
    [5] = "cn",
}

function ns.Print(...)
    print("|cffE5CC80DPS Detector|r:", ...)
end

function ns.NormalizeRealm(realm)
    if type(realm) ~= "string" or realm == "" then
        return ""
    end
    realm = realm:gsub("['’%-]", ""):gsub("%s+", "")
    return realm:lower()
end

function ns.NormalizeName(name)
    if type(name) ~= "string" then
        return ""
    end
    return name:lower()
end

function ns.SplitNameRealm(fullName, fallbackRealm)
    if type(fullName) ~= "string" or fullName == "" then
        return nil, nil
    end

    local name, realm = fullName:match("^([^-]+)%-(.+)$")
    if not name then
        name = fullName
        realm = fallbackRealm
    end

    if name then
        name = name:gsub("%s+", "")
    end
    if (not realm or realm == "") and fallbackRealm then
        realm = fallbackRealm
    end

    if not name or name == "" or not realm or realm == "" then
        return nil, nil
    end

    return name, realm
end

function ns.GetUnitNameRealm(unit)
    if not unit or not UnitExists(unit) then
        return nil, nil
    end

    local name, realm = UnitNameUnmodified and UnitNameUnmodified(unit) or UnitName(unit)
    if not name or name == "" then
        return nil, nil
    end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName() or GetRealmName()
    end
    return ns.SplitNameRealm(name, realm)
end

function ns.DetectPlayerRegion()
    local regionID = GetCurrentRegion()
    ns.PLAYER_REGION = REGION_BY_ID[regionID] or "us"
    ns.PLAYER_REALM = GetNormalizedRealmName() or GetRealmName()
    ns.PLAYER_NAME = UnitName("player")
    return ns.PLAYER_REGION
end

function ns.FormatNumber(value)
    value = tonumber(value) or 0
    if value >= 1000000 then
        return format("%.2fM", value / 1000000)
    end
    if value >= 1000 then
        return format("%.1fk", value / 1000)
    end
    return format("%d", value)
end

function ns.FormatPercent(percentile)
    percentile = tonumber(percentile) or 0
    if percentile >= 99.5 then
        return "100%"
    end
    if percentile >= 10 then
        return format("%d%%", math.floor(percentile + 0.5))
    end
    return format("%.1f%%", percentile)
end

_G.DPSDetector = ns
