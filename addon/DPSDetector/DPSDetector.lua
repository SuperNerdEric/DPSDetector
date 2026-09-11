local addonName, ns = ...

local function PrintHelp()
    ns.Print("Commands:")
    print("  /dpsd status          - database and season info")
    print("  /dpsd search Name Realm")
    print("  /dpsd unit            - lookup your current target")
    print("  /dpsd toggle lfg      - toggle LFG tooltips")
    print("  /dpsd toggle unit     - toggle unit tooltips")
end

local function PrintRecord(name, realm, region, role)
    local record = ns.GetPlayerRecord(name, realm, region)
    if not record then
        ns.Print(format("No snapshot data for %s-%s (%s).", name, realm, (region or "us"):upper()))
        return
    end

    local function PrintMetric(label, metricSet)
        if not metricSet or not metricSet.overall then
            return false
        end
        ns.Print(format("%s-%s  %s %s (%s)",
            record.name,
            realm,
            label,
            ns.FormatNumber(metricSet.overall.amount),
            ns.FormatPercent(metricSet.overall.percentile)))
        local focused = ns.GetFocusedDungeon()
        if focused and metricSet.dungeons[focused.index] then
            local dungeonMetric = metricSet.dungeons[focused.index]
            print(format("  %s: %s (%s)", focused.name, ns.FormatNumber(dungeonMetric.amount), ns.FormatPercent(dungeonMetric.percentile)))
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
        if provider then
            ns.Print(format("Loaded %s snapshot from %s (%s characters).",
                provider.region:upper(),
                provider.date or "unknown date",
                tostring(provider.numCharacters or "?")))
        else
            ns.Print(format("No %s database loaded. Enable DPSDetector_DB_%s.", region:upper(), region:upper()))
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
        else
            ns.Print("Usage: /dpsd toggle lfg|unit")
        end
    else
        PrintHelp()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ns.InitConfig()
    elseif event == "PLAYER_LOGIN" then
        ns.DetectPlayerRegion()
        ns.InitTooltips()
        if not ns.HasProvider(ns.PLAYER_REGION) then
            ns.Print(format("No %s snapshot loaded. Enable DPSDetector_DB_%s or run tools/update-db.mjs.",
                (ns.PLAYER_REGION or "us"):upper(),
                (ns.PLAYER_REGION or "us"):upper()))
        end
    end
end)

SLASH_DPSDETECTOR1 = "/dpsd"
SLASH_DPSDETECTOR2 = "/dpsdetector"
SlashCmdList.DPSDETECTOR = HandleSlash
