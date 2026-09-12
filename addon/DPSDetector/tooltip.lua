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

local function ParseText(parse)
    if not parse or not parse.amount or parse.amount <= 0 then
        return nil
    end

    local text = format("%s%s", ns.FormatNumber(parse.amount), SpecLabel(parse.spec))
    local shortName = parse.dungeon and parse.dungeon.shortName
    if parse.level and parse.level > 0 and shortName then
        text = format("%s (+%d %s)", text, parse.level, shortName)
    elseif parse.level and parse.level > 0 then
        text = format("%s (+%d)", text, parse.level)
    end
    return text
end

local function AddParseLine(tooltip, label, parse, highlight)
    local text = ParseText(parse)
    if not text then
        return false
    end

    local r1, g1, b1 = 1, 1, 1
    if highlight then
        r1, g1, b1 = 0, 1, 0
    end
    tooltip:AddDoubleLine(label or " ", text, r1, g1, b1, 1, 0.85, 0)
    return true
end

local function AddSlotLines(tooltip, label, slot, highlight)
    if not slot then
        return false
    end
    local added = AddParseLine(tooltip, label, slot.key or slot, highlight)
    if slot.peak then
        added = AddParseLine(tooltip, " ", slot.peak, false) or added
    end
    return added
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
    tooltip:AddLine(ns.ADDON_TITLE, 1, 0.85, 0)

    local added = AddSlotLines(tooltip, overallLabel, metricSet.overall or metricSet, false)

    if focusedDungeon then
        local dungeonMetric = metricSet.dungeons[focusedDungeon.index]
        local highlight = dungeonMetric and metricSet.key and dungeonMetric.key
            and dungeonMetric.key.dungeonIndex == metricSet.key.dungeonIndex
            and dungeonMetric.key.level == metricSet.key.level
        added = AddSlotLines(
            tooltip,
            format("%s %s", dungeonLabelPrefix, focusedDungeon.shortName),
            dungeonMetric,
            highlight
        ) or added
    end

    return added
end

-- Post-calls run in registration order. We register early, so Blizzard item
-- level and Raider.IO land below us unless we wait until the frame is done.
local flushPending = {}
local appendedKey = {}

local function ResetUnitTooltipState(tooltip)
    appendedKey[tooltip] = nil
end

local function FlushUnitTooltip(tooltip)
    flushPending[tooltip] = nil
    if not tooltip.IsShown or not tooltip:IsShown() then
        return
    end

    local name, realm, unit = ns.GetTooltipPlayer(tooltip)
    if not name then
        return
    end

    local key = name .. "-" .. realm
    if appendedKey[tooltip] == key then
        return
    end

    if ns.AppendTooltip(tooltip, name, realm, ns.PLAYER_REGION, ns.GetUnitRole(unit), nil) then
        appendedKey[tooltip] = key
        tooltip:Show()
    end
end

local function AppendUnitTooltip(tooltip)
    if not ns.GetOption("enableUnitTooltips") then
        return
    end
    if flushPending[tooltip] then
        return
    end
    flushPending[tooltip] = true
    C_Timer.After(0, function()
        FlushUnitTooltip(tooltip)
    end)
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
    local leave = onLeave or HideTooltip
    if button.HookScript then
        button:HookScript("OnEnter", onEnter)
        button:HookScript("OnLeave", leave)
    end
    if hooksecurefunc then
        if type(button.OnEnter) == "function" then
            hooksecurefunc(button, "OnEnter", onEnter)
        end
        if type(button.OnLeave) == "function" then
            hooksecurefunc(button, "OnLeave", leave)
        end
    end
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
        scrollBox:RegisterCallback("OnDataRangeChanged", function()
            HookVisible()
            if scrollBox.IsMouseOver and scrollBox:IsMouseOver() and scrollBox.GetFrames then
                for _, frame in ipairs(scrollBox:GetFrames()) do
                    if frame:IsMouseOver() then
                        onEnter(frame)
                    end
                end
            end
        end, addonName .. "Range")
    end
    HookVisible()
end

local function ShowNamedProfile(owner, fullName, role, anchor, offsetX, offsetY, opts)
    if not owner or not fullName then
        return
    end
    opts = opts or {}

    C_Timer.After(0, function()
        if not GameTooltip or not GameTooltip.IsShown then
            return
        end

        local name, realm = ns.SplitNameRealm(fullName, ns.PLAYER_REALM)
        if not name then
            return
        end

        local mouseOverOwner = owner.IsMouseOver and owner:IsMouseOver()
        local tipOwner = GameTooltip.GetOwner and GameTooltip:GetOwner()
        local ownedByUs = tipOwner == owner or (tipOwner and tipOwner.GetParent and tipOwner:GetParent() == owner)
        local ownerStillShown = opts.requireHover == false and owner.IsShown and owner:IsShown()
        if not mouseOverOwner and not ownedByUs and not ownerStillShown and not ns.TooltipShowsName(GameTooltip, name) then
            return
        end

        if not GameTooltip:IsShown() then
            if not mouseOverOwner and not ownerStillShown then
                return
            end
            GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT", offsetX or 0, offsetY or 0)
        end

        local key = name .. "-" .. realm
        if appendedKey[GameTooltip] == key then
            return
        end

        if ns.AppendTooltip(GameTooltip, name, realm, ns.PLAYER_REGION, role or ns.ROLES.DAMAGER, nil) then
            appendedKey[GameTooltip] = key
            GameTooltip:Show()
        elseif GameTooltip:NumLines() == 0 then
            GameTooltip:Hide()
        end
    end)
end

local function ResolveFriendsButton(button)
    if not button then
        return nil, nil
    end

    local candidates, seen = {}, {}
    local function consider(name, realm)
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

    local elementData = button.elementData
    local accountInfo = elementData and elementData.accountInfo
    if accountInfo then
        consider(ns.AccountCharacterNameRealm(accountInfo.gameAccountInfo))
        if accountInfo.bnetAccountID then
            consider(ns.GetNameRealmForBNetFriend(accountInfo.bnetAccountID, elementData.friendIndex))
        end
    end

    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET and button.id and C_BattleNet then
        local info = C_BattleNet.GetFriendAccountInfo(button.id)
        if not info and C_BattleNet.GetAccountInfoByID then
            info = C_BattleNet.GetAccountInfoByID(button.id)
        end
        if info then
            consider(ns.AccountCharacterNameRealm(info.gameAccountInfo))
            consider(ns.GetNameRealmForBNetFriend(info.bnetAccountID or button.id, button.id))
        else
            consider(ns.GetNameRealmForBNetFriend(button.id))
        end
    end

    if button.buttonType == FRIENDS_BUTTON_TYPE_WOW and button.id and C_FriendList then
        local friendInfo = C_FriendList.GetFriendInfoByIndex(button.id)
        if friendInfo and friendInfo.name then
            consider(ns.SplitNameRealm(friendInfo.name, ns.PLAYER_REALM))
        end
    end

    for i = 1, #candidates do
        local name, realm = candidates[i][1], candidates[i][2]
        if ns.GetPlayerRecord(name, realm, ns.PLAYER_REGION) then
            return name, realm
        end
    end
    if candidates[1] then
        return candidates[1][1], candidates[1][2]
    end
    return nil, nil
end

local function OnFriendsButtonEnter(self)
    if not ns.GetOption("enableFriendsTooltips") then
        return
    end
    local name, realm = ResolveFriendsButton(self)
    if name and realm then
        ShowNamedProfile(self, name .. "-" .. realm, ns.ROLES.DAMAGER, "ANCHOR_RIGHT")
    end
end

local function CollectFrameTexts(frame, into, depth)
    if not frame or (depth or 0) > 5 then
        return
    end
    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetText then
                local text = region:GetText()
                if type(text) == "string" and text ~= "" then
                    into[#into + 1] = text
                end
            end
        end
    end
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            CollectFrameTexts(children[i], into, (depth or 0) + 1)
        end
    end
end

local function NameRealmFromTexts(texts)
    local name, realm
    for i = 1, #texts do
        local text = texts[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local realmLine = text:match("^[Rr]ealm:%s*(.+)$")
        if realmLine then
            realm = realmLine:gsub("%s+", "")
        end
        local named = text:match("^([^,]+),%s*%d+")
        if named then
            name = strtrim(named)
        end
    end
    if name and realm then
        return ns.SplitNameRealm(name, realm)
    end
end

local function AppendFriendsProfile(name, realm, owner)
    if not name or not realm or not GameTooltip then
        return
    end
    if not GameTooltip:IsShown() then
        if owner and owner.IsShown and owner:IsShown() then
            GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT", -(owner.GetWidth and owner:GetWidth() or 0), -4)
        else
            return
        end
    end
    local key = name .. "-" .. realm
    if appendedKey[GameTooltip] == key then
        return
    end
    if ns.AppendTooltip(GameTooltip, name, realm, ns.PLAYER_REGION, ns.ROLES.DAMAGER, nil) then
        appendedKey[GameTooltip] = key
        GameTooltip:Show()
    end
end

local friendsTooltipHooked = false

local function HookFriendsTooltip()
    local friendsTooltip = _G.FriendsTooltip
    if not friendsTooltip or friendsTooltipHooked or not hooksecurefunc then
        return
    end
    friendsTooltipHooked = true

    -- FriendsTooltip:Show can run every frame. Raider.IO SetOwner-clears
    -- GameTooltip each time, so we must append in this same hook — After(0)
    -- is always one frame late and gets wiped.
    hooksecurefunc(friendsTooltip, "Show", function(self)
        if not ns.GetOption("enableFriendsTooltips") then
            return
        end
        local name, realm = ResolveFriendsButton(self.button)
        if not name then
            local texts = {}
            CollectFrameTexts(self, texts)
            CollectFrameTexts(GameTooltip, texts)
            name, realm = NameRealmFromTexts(texts)
        end
        AppendFriendsProfile(name, realm, self)
    end)
    hooksecurefunc(friendsTooltip, "Hide", function()
        if GameTooltip:IsShown() and appendedKey[GameTooltip] and not ns.GetTooltipUnit(GameTooltip) then
            GameTooltip:Hide()
        end
    end)
end

local function OnGuildRosterEnter(self)
    if not ns.GetOption("enableGuildTooltips") then
        return
    end
    local index = self.index or self.guildIndex
    if not index or not GetGuildRosterInfo then
        return
    end
    local fullName = GetGuildRosterInfo(index)
    if ns.IsSecret(fullName) or not fullName then
        return
    end
    local name, realm = ns.SplitNameRealm(fullName, ns.PLAYER_REALM)
    local role = ns.ROLES.DAMAGER
    if name and ns.PLAYER_NAME and ns.NormalizeName(name) == ns.NormalizeName(ns.PLAYER_NAME) then
        role = ns.GetUnitRole("player")
    end
    ShowNamedProfile(self, fullName, role, "ANCHOR_TOPLEFT")
end

local function CommunityMemberName(button)
    local info
    if type(button.GetMemberInfo) == "function" then
        info = button:GetMemberInfo()
    end
    if not info then
        info = button.memberInfo
    end
    if info and not ns.IsSecret(info) then
        if info.clubType and Enum and Enum.ClubType then
            if info.clubType ~= Enum.ClubType.Guild and info.clubType ~= Enum.ClubType.Character then
                return nil, nil
            end
        end
        local guid = info.guid
        if guid and not ns.IsSecret(guid) and UnitGUID("player") == guid then
            return ns.PLAYER_NAME, ns.PLAYER_REALM
        end
        if info.name and not ns.IsSecret(info.name) then
            local realm = info.realm
            if realm and ns.IsSecret(realm) then
                realm = nil
            end
            return ns.SplitNameRealm(info.name, realm or ns.PLAYER_REALM)
        end
    end
    if button.guid and not ns.IsSecret(button.guid) and UnitGUID("player") == button.guid then
        return ns.PLAYER_NAME, ns.PLAYER_REALM
    end
    return nil, nil
end

local function OnCommunityMemberEnter(self)
    if not ns.GetOption("enableGuildTooltips") then
        return
    end
    local name, realm = CommunityMemberName(self)
    if not name then
        local unitName, unitRealm = ns.GetTooltipPlayer(GameTooltip)
        if unitName then
            name, realm = unitName, unitRealm
        end
    end
    if not name then
        return
    end
    local role = ns.ROLES.DAMAGER
    local _, _, unit = ns.GetTooltipPlayer(GameTooltip)
    if unit then
        role = ns.GetUnitRole(unit)
    elseif ns.PLAYER_NAME and ns.NormalizeName(name) == ns.NormalizeName(ns.PLAYER_NAME) then
        role = ns.GetUnitRole("player")
    end
    ShowNamedProfile(self, name .. "-" .. (realm or ns.PLAYER_REALM), role, "ANCHOR_LEFT")
end

local function OnWhoEnter(self)
    if not ns.GetOption("enableWhoTooltips") then
        return
    end
    local index = self.index or self.whoIndex
    if not index or not C_FriendList or not C_FriendList.GetWhoInfo then
        return
    end
    local info = C_FriendList.GetWhoInfo(index)
    if not info or not info.fullName then
        return
    end
    ShowNamedProfile(self, info.fullName, ns.ROLES.DAMAGER, "ANCHOR_LEFT")
end

local function EachScrollBox(getter, onEnter)
    local ok, scrollBox = pcall(getter)
    if ok and scrollBox then
        HookScrollBox(scrollBox, onEnter, HideTooltip)
    end
end

function ns.InitSocialTooltips()
    HookFriendsTooltip()

    EachScrollBox(function()
        return FriendsListFrame and FriendsListFrame.ScrollBox
    end, OnFriendsButtonEnter)
    EachScrollBox(function()
        return FriendsFrame and FriendsFrame.ScrollBox
    end, OnFriendsButtonEnter)
    EachScrollBox(function()
        return FriendsFrame and FriendsFrame.FriendsList and FriendsFrame.FriendsList.ScrollBox
    end, OnFriendsButtonEnter)
    EachScrollBox(function()
        return SocialUIFrame and SocialUIFrame.FriendsList and SocialUIFrame.FriendsList.ScrollBox
    end, OnFriendsButtonEnter)

    EachScrollBox(function()
        return GuildRosterContainer
    end, OnGuildRosterEnter)
    EachScrollBox(function()
        return CommunitiesFrame and CommunitiesFrame.MemberList and CommunitiesFrame.MemberList.ScrollBox
    end, OnCommunityMemberEnter)
    EachScrollBox(function()
        return WhoFrame and WhoFrame.ScrollBox
    end, OnWhoEnter)
    EachScrollBox(function()
        return WhoListScrollFrame
    end, OnWhoEnter)
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

    GameTooltip:HookScript("OnTooltipCleared", ResetUnitTooltipState)
    GameTooltip:HookScript("OnHide", ResetUnitTooltipState)

    ns.InitSocialTooltips()
end
