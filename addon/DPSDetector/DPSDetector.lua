local addonName, ns = ...

local function PrintHelp()
    ns.Print("Commands:")
    print("  /dpsd status          - database and season info")
    print("  /dpsd search Name Realm")
    print("  /dpsd unit            - lookup your current target")
    print("  /dpsd toggle lfg      - toggle LFG tooltips")
    print("  /dpsd toggle unit     - toggle unit tooltips")
    print("  /dpsd toggle guild    - toggle guild roster tooltips")
    print("  /dpsd toggle friends  - toggle Battle.net / friends tooltips")
end

local LOOKUP_ERRORS = {
    ["no-provider"] = "No %s snapshot is loaded. Enable DPSDetector_DB_%s in the AddOns list.",
    ["no-lookup"] = "The %s character index loaded, but the lookup file did not. Check db/%s_lookup.lua.",
    ["no-realm"] = "No %s snapshot entries for realm %s.",
    ["no-realm-lookup"] = "Realm %s is in the index, but its lookup table is missing.",
    ["no-name"] = "No snapshot data for %s-%s (%s).",
    ["missing-name"] = "Need a character name and realm.",
}

local function PrintRecord(name, realm, region, role)
    local record, reason = ns.GetPlayerRecord(name, realm, region)
    if not record then
        local tag = (region or ns.PLAYER_REGION or "us"):upper()
        if reason == "no-provider" then
            ns.Print(format(LOOKUP_ERRORS["no-provider"], tag, tag))
        elseif reason == "no-lookup" then
            ns.Print(format(LOOKUP_ERRORS["no-lookup"], tag, tag:lower()))
        elseif reason == "no-realm" then
            ns.Print(format(LOOKUP_ERRORS["no-realm"], tag, realm))
        elseif reason == "no-realm-lookup" then
            ns.Print(format(LOOKUP_ERRORS["no-realm-lookup"], realm))
        else
            ns.Print(format(LOOKUP_ERRORS["no-name"], name, realm, tag))
        end
        return
    end

    local function FormatParse(parse)
        if not parse or not parse.amount or parse.amount <= 0 then
            return nil
        end
        local text = ns.FormatNumber(parse.amount)
        local shortName = parse.dungeon and parse.dungeon.shortName
        if parse.level and parse.level > 0 and shortName then
            return format("%s (+%d %s)", text, parse.level, shortName)
        end
        return text
    end

    local function PrintMetric(label, metricSet)
        local slot = metricSet and (metricSet.overall or metricSet)
        local key = slot and (slot.key or slot)
        if not key then
            return false
        end
        ns.Print(format("%s-%s  %s %s", record.name, realm, label, FormatParse(key)))
        if slot.peak then
            print(format("  %s", FormatParse(slot.peak)))
        end
        local focused = ns.GetFocusedDungeon()
        if focused and metricSet.dungeons[focused.index] then
            local dungeonMetric = metricSet.dungeons[focused.index]
            print(format("  %s: %s", focused.name, FormatParse(dungeonMetric.key or dungeonMetric)))
            if dungeonMetric.peak then
                print(format("    %s", FormatParse(dungeonMetric.peak)))
            end
        end
        return true
    end

    local shown = false
    if role == ns.ROLES.HEALER then
        shown = PrintMetric("HPS", record.healing)
    elseif role == ns.ROLES.TANK then
        shown = PrintMetric("Tank DPS", record.tank) or PrintMetric("DPS", record.damage)
    else
        shown = PrintMetric("DPS", record.damage)
        if record.healing then
            PrintMetric("HPS", record.healing)
            shown = true
        end
    end

    if not shown then
        ns.Print(format("No parses for %s-%s.", name, realm))
    end
end

local function HandleSlash(msg)
    msg = strtrim(msg or "")
    local command, rest = msg:match("^(%S+)%s*(.-)$")
    command = command and command:lower() or ""

    if command == "" or command == "help" then
        PrintHelp()
    elseif command == "status" then
        local region = ns.PLAYER_REGION or "us"
        local provider = ns.GetProvider(region)
        ns.Print(format("Season: %s (%s)", ns.SEASON.name, ns.SEASON.id))
        ns.EnsureRegionDatabase(region)
        provider = ns.GetProvider(region)
        if provider and provider.db and provider.lookup then
            ns.Print(format("Loaded %s snapshot from %s (%s characters).",
                provider.region:upper(),
                provider.date or "unknown date",
                tostring(provider.numCharacters or "?")))
        elseif provider and provider.db then
            ns.Print(format("%s character index is loaded, but the lookup file is missing.", region:upper()))
        else
            local pack = format("DPSDetector_DB_%s", region:upper())
            local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
            if isLoaded and isLoaded(pack) then
                ns.Print(format("%s is enabled but registered no snapshot. Check for a Lua error on load.", pack))
            else
                ns.Print(format("No %s database loaded. Enable %s.", region:upper(), pack))
            end
        end
        local dungeon = ns.GetFocusedDungeon()
        if dungeon then
            ns.Print(format("Focused dungeon: %s", dungeon.name))
        else
            ns.Print("No focused dungeon (open LFG or enter a season dungeon).")
        end
    elseif command == "search" then
        local name, realm = rest:match("^(%S+)%s+(.+)$")
        if not name then
            ns.Print("Usage: /dpsd search Name Realm")
            return
        end
        PrintRecord(name, realm, ns.PLAYER_REGION, ns.ROLES.DAMAGER)
    elseif command == "unit" then
        local unit = UnitExists("target") and "target" or "player"
        local name, realm = ns.GetUnitNameRealm(unit)
        if not name then
            ns.Print("No player unit to look up.")
            return
        end
        PrintRecord(name, realm, ns.PLAYER_REGION, ns.GetUnitRole(unit))
    elseif command == "toggle" then
        local which = (rest or ""):lower()
        if which == "lfg" then
            ns.SetOption("enableLFGTooltips", not ns.GetOption("enableLFGTooltips"))
            ns.Print("LFG tooltips:", ns.GetOption("enableLFGTooltips") and "on" or "off")
        elseif which == "unit" then
            ns.SetOption("enableUnitTooltips", not ns.GetOption("enableUnitTooltips"))
            ns.Print("Unit tooltips:", ns.GetOption("enableUnitTooltips") and "on" or "off")
        elseif which == "guild" then
            ns.SetOption("enableGuildTooltips", not ns.GetOption("enableGuildTooltips"))
            ns.Print("Guild tooltips:", ns.GetOption("enableGuildTooltips") and "on" or "off")
        elseif which == "friends" then
            ns.SetOption("enableFriendsTooltips", not ns.GetOption("enableFriendsTooltips"))
            ns.Print("Friends tooltips:", ns.GetOption("enableFriendsTooltips") and "on" or "off")
        else
            ns.Print("Usage: /dpsd toggle lfg|unit|guild|friends")
        end
    else
        PrintHelp()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            ns.InitConfig()
        elseif arg1 == "Blizzard_Communities" or arg1 == "Blizzard_FriendsFrame" then
            if ns.InitSocialTooltips then
                ns.InitSocialTooltips()
            end
        end
    elseif event == "PLAYER_LOGIN" then
        ns.DetectPlayerRegion()
        ns.EnsureRegionDatabase(ns.PLAYER_REGION)
        ns.InitTooltips()
        if not ns.HasProvider(ns.PLAYER_REGION) then
            ns.Print(format("No %s snapshot loaded. Enable DPSDetector_DB_%s or run tools/update-db.mjs.",
                (ns.PLAYER_REGION or "us"):upper(),
                (ns.PLAYER_REGION or "us"):upper()))
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.DetectPlayerRegion()
    end
end)

SLASH_DPSDETECTOR1 = "/dpsd"
SLASH_DPSDETECTOR2 = "/dpsdetector"
SlashCmdList.DPSDETECTOR = HandleSlash
