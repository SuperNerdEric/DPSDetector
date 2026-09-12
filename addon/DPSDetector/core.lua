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

function ns.IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function TooltipLeft1(tooltip)
    if not tooltip then
        return ""
    end
    local fontString = tooltip.TextLeft1
    if not fontString and tooltip.GetName then
        fontString = _G[tooltip:GetName() .. "TextLeft1"]
    end
    local text = fontString and fontString.GetText and fontString:GetText()
    if type(text) ~= "string" then
        return ""
    end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
end

function ns.TooltipShowsName(tooltip, name)
    if not tooltip or not name or name == "" then
        return false
    end
    local title = TooltipLeft1(tooltip)
    if title == "" then
        return false
    end
    return title:lower():find(name:lower(), 1, true) ~= nil
end

-- Identify the player the tooltip is actually showing. Never fall back to
-- mouseover: party/raid frames can point the tooltip at one unit while
-- mouseover is still another, which swaps names and parses.
function ns.GetTooltipPlayer(tooltip)
    if not tooltip then
        return nil, nil, nil
    end
    if tooltip.IsTooltipType and Enum and Enum.TooltipDataType and not tooltip:IsTooltipType(Enum.TooltipDataType.Unit) then
        return nil, nil, nil
    end

    local tooltipName, unitFromTooltip
    if tooltip.GetUnit then
        tooltipName, unitFromTooltip = tooltip:GetUnit()
        if ns.IsSecret(tooltipName) then
            tooltipName = nil
        end
        if ns.IsSecret(unitFromTooltip) then
            unitFromTooltip = nil
        end
    end

    local guid
    if tooltip.GetPrimaryTooltipData then
        local data = tooltip:GetPrimaryTooltipData()
        guid = data and data.guid
        if ns.IsSecret(guid) then
            guid = nil
        end
    end

    local unit
    if guid and UnitTokenFromGUID then
        local fromGuid = UnitTokenFromGUID(guid)
        if fromGuid and not ns.IsSecret(fromGuid) then
            unit = fromGuid
        end
    end
    if not unit and unitFromTooltip and UnitExists(unitFromTooltip) then
        if not guid or UnitGUID(unitFromTooltip) == guid then
            unit = unitFromTooltip
        end
    end

    if tooltipName and tooltipName ~= "" then
        local name, realm = ns.SplitNameRealm(tooltipName, ns.PLAYER_REALM)
        if name then
            if unit then
                local unitName, unitRealm = ns.GetUnitNameRealm(unit)
                if unitName and ns.NormalizeName(unitName) == ns.NormalizeName(name) then
                    return unitName, unitRealm or realm, unit
                end
                return name, realm, nil
            end
            return name, realm, nil
        end
    end

    if unit and UnitIsPlayer(unit) then
        local name, realm = ns.GetUnitNameRealm(unit)
        if name then
            return name, realm, unit
        end
    end

    return nil, nil, nil
end

function ns.GetTooltipUnit(tooltip)
    local _, _, unit = ns.GetTooltipPlayer(tooltip)
    return unit
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
    if not unit or ns.IsSecret(unit) or not UnitExists(unit) then
        return nil, nil
    end

    if UnitIsUnit(unit, "player") and ns.PLAYER_NAME and ns.PLAYER_REALM then
        return ns.PLAYER_NAME, ns.PLAYER_REALM
    end

    local name, realm
    if UnitNameUnmodified then
        name, realm = UnitNameUnmodified(unit)
    else
        name, realm = UnitName(unit)
    end

    if ns.IsSecret(name) or ns.IsSecret(realm) or not name or name == "" then
        return nil, nil
    end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName() or GetRealmName()
    end
    return ns.SplitNameRealm(name, realm)
end

local function SafeAccountField(accountInfo, key)
    if not accountInfo then
        return nil
    end
    local value = accountInfo[key]
    if value == nil or ns.IsSecret(value) then
        return nil
    end
    return value
end

function ns.AccountCharacterNameRealm(accountInfo)
    if not accountInfo or ns.IsSecret(accountInfo) then
        return nil, nil
    end

    local characterName = SafeAccountField(accountInfo, "characterName")
    if (not characterName or characterName == "") and accountInfo.richPresence then
        local presence = SafeAccountField(accountInfo, "richPresence")
        if type(presence) == "string" then
            characterName = presence:match("^([^%-]+)%s*%-%s*(.+)$")
            if characterName then
                characterName = strtrim(characterName)
            end
        end
    end
    if not characterName or characterName == "" then
        return nil, nil
    end

    local client = SafeAccountField(accountInfo, "clientProgram")
    if client and BNET_CLIENT_WOW and client ~= BNET_CLIENT_WOW then
        return nil, nil
    end

    local project = SafeAccountField(accountInfo, "wowProjectID")
    if project and WOW_PROJECT_MAINLINE and project ~= WOW_PROJECT_MAINLINE then
        return nil, nil
    end

    local realm = SafeAccountField(accountInfo, "realmName")
        or SafeAccountField(accountInfo, "realmDisplayName")
    if type(realm) == "string" then
        realm = realm:gsub("%s+", "")
    end
    if not realm or realm == "" then
        local presence = SafeAccountField(accountInfo, "richPresence")
        if type(presence) == "string" then
            realm = presence:match("^[^%-]+%s*%-%s*(.+)$")
            if realm then
                realm = realm:gsub("%s+", "")
            end
        end
    end

    return ns.SplitNameRealm(characterName, realm or ns.PLAYER_REALM)
end

local function AddBNetCandidate(candidates, seen, name, realm)
    if not name or not realm then
        return
    end
    local key = ns.NormalizeName(name) .. "#" .. ns.NormalizeRealm(realm)
    if seen[key] then
        return
    end
    seen[key] = true
    candidates[#candidates + 1] = { name, realm }
end

local function AddBNetAccount(candidates, seen, accountInfo)
    AddBNetCandidate(candidates, seen, ns.AccountCharacterNameRealm(accountInfo))
end

function ns.GetNameRealmForBNetFriend(bnetAccountID, friendIndex)
    if not C_BattleNet then
        return nil, nil
    end

    local index = friendIndex
    if not index and bnetAccountID and BNGetFriendIndex then
        index = BNGetFriendIndex(bnetAccountID)
    end

    local candidates, seen = {}, {}

    if index then
        local numAccounts = C_BattleNet.GetFriendNumGameAccounts(index) or 0
        for i = 1, numAccounts do
            AddBNetAccount(candidates, seen, C_BattleNet.GetFriendGameAccountInfo(index, i))
        end
        local friendInfo = C_BattleNet.GetFriendAccountInfo(index)
        if friendInfo then
            AddBNetAccount(candidates, seen, friendInfo.gameAccountInfo)
        end
    end

    if bnetAccountID and C_BattleNet.GetAccountInfoByID then
        local accountInfo = C_BattleNet.GetAccountInfoByID(bnetAccountID)
        if accountInfo then
            AddBNetAccount(candidates, seen, accountInfo.gameAccountInfo)
        end
    end

    for i = 1, #candidates do
        local name, realm = candidates[i][1], candidates[i][2]
        if ns.GetPlayerRecord and ns.GetPlayerRecord(name, realm, ns.PLAYER_REGION) then
            return name, realm
        end
    end

    if candidates[1] then
        return candidates[1][1], candidates[1][2]
    end
    return nil, nil
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

_G.DPSDetector = ns
