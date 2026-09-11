local _, ns = ...

local function GetActivityIDFromTable(data)
    if type(data) ~= "table" then
        return nil
    end
    if type(data.activityID) == "number" then
        return data.activityID
    end
    if type(data.activityIDs) == "table" and type(data.activityIDs[1]) == "number" then
        return data.activityIDs[1]
    end
end

function ns.GetDungeonFromActivityID(activityID)
    if type(activityID) ~= "number" then
        return nil
    end
    return ns.GetDungeonByActivityID(activityID)
end

function ns.GetInstanceDungeon()
    local _, instanceType, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    if instanceType ~= "party" then
        return nil
    end
    return ns.GetDungeonByMapID(instanceMapID)
end

function ns.GetOwnedKeystoneDungeon()
    if not C_MythicPlus or not C_MythicPlus.GetOwnedKeystoneChallengeMapID then
        return nil
    end
    local challengeMapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    if challengeMapID and challengeMapID > 0 then
        return ns.GetDungeonByKeystone(challengeMapID)
    end
end

function ns.GetActiveListingDungeon()
    if not C_LFGList or not C_LFGList.GetActiveEntryInfo then
        return nil
    end
    local entryInfo = C_LFGList.GetActiveEntryInfo()
    local activityID = GetActivityIDFromTable(entryInfo)
    return ns.GetDungeonFromActivityID(activityID), activityID
end

-- Mirrors Raider.IO: prefer the LFG activity you are viewing/hosting,
-- then the dungeon you are physically inside.
function ns.GetFocusedDungeon(activityID)
    local dungeon = ns.GetDungeonFromActivityID(activityID)
    if dungeon then
        return dungeon, "lfg"
    end

    dungeon = select(1, ns.GetActiveListingDungeon())
    if dungeon then
        return dungeon, "listing"
    end

    dungeon = ns.GetInstanceDungeon()
    if dungeon then
        return dungeon, "instance"
    end

    return nil, nil
end

function ns.GetUnitRole(unit, assignedRole)
    if assignedRole == "TANK" or assignedRole == "HEALER" or assignedRole == "DAMAGER" then
        return assignedRole
    end

    if unit and UnitExists(unit) then
        local groupRole = UnitGroupRolesAssigned(unit)
        if groupRole == "TANK" or groupRole == "HEALER" or groupRole == "DAMAGER" then
            return groupRole
        end

        if UnitIsUnit(unit, "player") then
            local specIndex
            if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
                specIndex = C_SpecializationInfo.GetSpecialization()
            elseif GetSpecialization then
                specIndex = GetSpecialization()
            end
            if specIndex then
                local role
                if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
                    role = select(5, C_SpecializationInfo.GetSpecializationInfo(specIndex))
                elseif GetSpecializationInfo then
                    role = select(5, GetSpecializationInfo(specIndex))
                end
                if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
                    return role
                end
            end
        end
    end

    return ns.ROLES.DAMAGER
end
