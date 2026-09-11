local addonName, ns = ...

local SPEC_NAMES = {
    [62] = "Arcane", [63] = "Fire", [64] = "Frost",
    [65] = "Holy", [66] = "Protection", [70] = "Retribution",
    [71] = "Arms", [72] = "Fury", [73] = "Protection",
    [102] = "Balance", [103] = "Feral", [104] = "Guardian", [105] = "Restoration",
    [250] = "Blood", [251] = "Frost", [252] = "Unholy",
    [253] = "Beast Mastery", [254] = "Marksmanship", [255] = "Survival",
    [256] = "Discipline", [257] = "Holy", [258] = "Shadow",
    [259] = "Assassination", [260] = "Outlaw", [261] = "Subtlety",
    [262] = "Elemental", [263] = "Enhancement", [264] = "Restoration",
    [265] = "Affliction", [266] = "Demonology", [267] = "Destruction",
    [268] = "Brewmaster", [269] = "Windwalker", [270] = "Mistweaver",
    [577] = "Havoc", [581] = "Vengeance",
    [1467] = "Devastation", [1468] = "Preservation", [1473] = "Augmentation",
}

local function SpecLabel(specID)
    if not ns.GetOption("showSpec") then
        return ""
    end
    local specName = SPEC_NAMES[specID]
    if not specName then
        return ""
    end
    return format(" %s", specName)
end

local function AddMetricLine(tooltip, label, metric, highlight)
    if not metric or not metric.amount or metric.amount <= 0 then
        return false
    end

    local text = format("%s (%s)%s", ns.FormatNumber(metric.amount), ns.FormatPercent(metric.percentile), SpecLabel(metric.spec))
    local r1, g1, b1 = 1, 1, 1
    if highlight then
        r1, g1, b1 = 0, 1, 0
    end
    local r2, g2, b2 = ns.GetParseColor(metric.percentile)
    tooltip:AddDoubleLine(label, text, r1, g1, b1, r2, g2, b2)
    return true
end

function ns.AppendTooltip(tooltip, name, realm, region, role, activityID)
    if not tooltip or not name then
        return false
    end

    local record = ns.GetPlayerRecord(name, realm, region)
    if not record then
        return false
    end

    local metricSet, kind = ns.SelectMetric(record, role)
    if not metricSet then
        return false
    end

    local focusedDungeon = ns.GetFocusedDungeon(activityID)
    local overallLabel = kind == "hps" and "Best M+ HPS" or "Best M+ DPS"
    local dungeonLabelPrefix = kind == "hps" and "Best HPS for" or "Best DPS for"

    tooltip:AddLine(" ")
    if ns.GetOption("showSeasonLine") then
        tooltip:AddLine(format("%s (%s)", ns.ADDON_TITLE, ns.SEASON.name), 1, 0.85, 0)
    else
        tooltip:AddLine(ns.ADDON_TITLE, 1, 0.85, 0)
    end

    local added = AddMetricLine(tooltip, overallLabel, metricSet.overall, false)

    if focusedDungeon then
        local dungeonMetric = metricSet.dungeons[focusedDungeon.index]
        local highlight = dungeonMetric and metricSet.overall and dungeonMetric.amount == metricSet.overall.amount
        added = AddMetricLine(tooltip, format("%s %s", dungeonLabelPrefix, focusedDungeon.shortName), dungeonMetric, highlight) or added
    end

    return added
end

local function AppendUnitTooltip(tooltip)
    if not ns.GetOption("enableUnitTooltips") then
        return
    end

    local _, unit = tooltip:GetUnit()
    if not unit or not UnitIsPlayer(unit) then
        return
    end

    local name, realm = ns.GetUnitNameRealm(unit)
    if not name then
        return
    end

    ns.AppendTooltip(tooltip, name, realm, ns.PLAYER_REGION, ns.GetUnitRole(unit), nil)
end

local function GetSearchActivityID(resultID)
    local searchResultInfo = C_LFGList.GetSearchResultInfo(resultID)
    if not searchResultInfo then
        return nil, nil
    end
    local activityID = searchResultInfo.activityID
    if type(activityID) ~= "number" and searchResultInfo.activityIDs then
        activityID = searchResultInfo.activityIDs[1]
    end
    return activityID, searchResultInfo
end

local function HookSearchTooltip(tooltip, resultID)
    if not ns.GetOption("enableLFGTooltips") then
        return
    end

    local activityID, searchResultInfo = GetSearchActivityID(resultID)
    if not searchResultInfo or not searchResultInfo.leaderName then
        return
    end

    local name, realm = ns.SplitNameRealm(searchResultInfo.leaderName, ns.PLAYER_REALM)
    if not name then
        return
    end

    local role = ns.ROLES.DAMAGER
    if C_LFGList.GetSearchResultPlayerInfo then
        local ok, leaderInfo = pcall(C_LFGList.GetSearchResultPlayerInfo, resultID, 1)
        if ok and type(leaderInfo) == "table" and leaderInfo.assignedRole then
            role = ns.GetUnitRole(nil, leaderInfo.assignedRole)
        elseif ok and type(leaderInfo) == "string" then
            -- older signature returned assignedRole later in the vararg list
        end
    end

    ns.AppendTooltip(tooltip, name, realm, ns.PLAYER_REGION, role, activityID)
end

local function ShowApplicantTooltip(owner, applicantID, memberIdx)
    if not ns.GetOption("enableLFGTooltips") then
        return
    end

    local fullName, _, _, _, _, _, _, _, _, assignedRole = C_LFGList.GetApplicantMemberInfo(applicantID, memberIdx)
    if not fullName then
        return
    end

    local name, realm = ns.SplitNameRealm(fullName, ns.PLAYER_REALM)
    if not name then
        return
    end

    local activityID
    local entryInfo = C_LFGList.GetActiveEntryInfo()
    if entryInfo then
        activityID = entryInfo.activityID
        if type(activityID) ~= "number" and entryInfo.activityIDs then
            activityID = entryInfo.activityIDs[1]
        end
    end

    -- The default LFG OnEnter already owns GameTooltip. Append like Raider.IO.
    if not GameTooltip:IsShown() then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(fullName, 1, 1, 1)
    end
    ns.AppendTooltip(GameTooltip, name, realm, ns.PLAYER_REGION, ns.GetUnitRole(nil, assignedRole), activityID)
    GameTooltip:Show()
end

local hookedButtons = {}

local function HideTooltip()
    if GameTooltip and GameTooltip:IsShown() then
        GameTooltip:Hide()
    end
end

local function HookButton(button, onEnter, onLeave)
    if not button or hookedButtons[button] then
        return
    end
    hookedButtons[button] = true
    button:HookScript("OnEnter", onEnter)
    button:HookScript("OnLeave", onLeave or HideTooltip)
end

local function OnApplicantMemberEnter(self)
    local parent = self:GetParent()
    if parent and parent.applicantID and self.memberIdx then
        ShowApplicantTooltip(self, parent.applicantID, self.memberIdx)
    end
end

local function OnApplicantRowEnter(self)
    if self.applicantID and self.Members then
        for _, member in pairs(self.Members) do
            HookButton(member, OnApplicantMemberEnter, HideTooltip)
        end
    elseif self.memberIdx then
        OnApplicantMemberEnter(self)
    end
end

local function HookScrollBox(scrollBox, onEnter)
    if not scrollBox then
        return
    end

    local function HookVisible()
        if scrollBox.GetFrames then
            for _, frame in ipairs(scrollBox:GetFrames()) do
                HookButton(frame, onEnter, HideTooltip)
            end
        end
    end

    if scrollBox.RegisterCallback then
        scrollBox:RegisterCallback("OnUpdate", HookVisible, addonName)
        scrollBox:RegisterCallback("OnDataRangeChanged", HookVisible, addonName)
    end
    HookVisible()
end

function ns.InitTooltips()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AppendUnitTooltip)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", AppendUnitTooltip)
    end

    if hooksecurefunc then
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", HookSearchTooltip)
    end

    if LFGListFrame and LFGListFrame.ApplicationViewer then
        HookScrollBox(LFGListFrame.ApplicationViewer.ScrollBox, OnApplicantRowEnter)
    end
end
