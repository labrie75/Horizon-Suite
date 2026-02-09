--[[
    Horizon Suite - Focus - World Quest Tracking
    Quests on map (GetNearbyQuestIDs), world/calling watch list, merge into tracker.
    Uses same approach as WorldQuestTracker: query GetQuestsForPlayerByMapID for all known WQ zones, then filter to current zone.
]]

local addon = _G.ModernQuestTracker

-- Zone map IDs that can have world quests (TWW + Dragonflight + other WQ zones; same concept as WorldQuestTracker.mapTables / WorldQuestZones).
-- Querying these when cache is empty lets the client return zone data. Add zones as needed (UiMapID from C_Map.GetBestMapForUnit("player")).
local ZONE_MAP_IDS_WITH_WQS = {
    [2214] = true, [2215] = true, [2213] = true, [2216] = true, [2248] = true, [2255] = true, [2256] = true, [2346] = true, [2371] = true, -- TWW
    [2024] = true, [2025] = true, [2023] = true, [2022] = true, [2151] = true, [2133] = true, [2200] = true, -- Dragonflight
    [4922] = true, -- Twilight Highlands (Eastern Kingdoms)
}

-- ============================================================================
-- WORLD QUEST AND QUESTS-ON-MAP LOGIC
-- ============================================================================

local function GetNearbyQuestIDs()
    local nearbySet = {}
    local taskQuestOnlySet = {}
    if not C_Map or not C_Map.GetBestMapForUnit or not C_QuestLog.GetQuestsOnMap then return nearbySet, taskQuestOnlySet end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nearbySet, taskQuestOnlySet end

    local mapIDsToCheck = { mapID }
    local seen = { [mapID] = true }
    if C_Map.GetMapParentInfo then
        local current = mapID
        for _ = 1, 20 do
            local parentInfo = C_Map.GetMapParentInfo(current)
            if not parentInfo or not parentInfo.parentMapID or parentInfo.parentMapID == 0 then break end
            current = parentInfo.parentMapID
            if not seen[current] then
                seen[current] = true
                mapIDsToCheck[#mapIDsToCheck + 1] = current
            end
        end
    end
    local numMapsAfterParentWalk = #mapIDsToCheck
    if C_Map.GetMapChildrenInfo then
        local children = C_Map.GetMapChildrenInfo(mapID, nil, true)
        if children then
            for _, child in ipairs(children) do
                local childID = child and child.mapID
                if childID and not seen[childID] then
                    seen[childID] = true
                    mapIDsToCheck[#mapIDsToCheck + 1] = childID
                end
            end
        end
        for i = 2, numMapsAfterParentWalk do
            local parentMapID = mapIDsToCheck[i]
            local parentChildren = C_Map.GetMapChildrenInfo(parentMapID, nil, true)
            if parentChildren then
                for _, child in ipairs(parentChildren) do
                    local childID = child and child.mapID
                    if childID and not seen[childID] then
                        seen[childID] = true
                        mapIDsToCheck[#mapIDsToCheck + 1] = childID
                    end
                end
            end
        end
    end

    for _, checkMapID in ipairs(mapIDsToCheck) do
        local onMap = C_QuestLog.GetQuestsOnMap(checkMapID)
        if onMap then
            for _, info in ipairs(onMap) do
                if info.questID then
                    nearbySet[info.questID] = true
                end
            end
        end
        if C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
            local taskPOIs = C_TaskQuest.GetQuestsForPlayerByMapID(checkMapID, checkMapID) or C_TaskQuest.GetQuestsForPlayerByMapID(checkMapID)
            if taskPOIs then
                for _, poi in ipairs(taskPOIs) do
                    local id = poi.questID or poi.questId
                    if id then
                        nearbySet[id] = true
                        taskQuestOnlySet[id] = true
                    end
                end
            end
        end
    end

    -- Fallback when cache is empty: query known WQ zones (or at least player's zone). When cache is primed by OnMapChanged, rely on it.
    local cacheHasZone = addon.zoneTaskQuestCache and addon.zoneTaskQuestCache[mapID] and next(addon.zoneTaskQuestCache[mapID])
    if not cacheHasZone and C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
        for zoneMapID, _ in pairs(ZONE_MAP_IDS_WITH_WQS) do
            local taskPOIs = C_TaskQuest.GetQuestsForPlayerByMapID(zoneMapID, zoneMapID) or C_TaskQuest.GetQuestsForPlayerByMapID(zoneMapID)
            if taskPOIs then
                local isPlayerZone = (zoneMapID == mapID)
                for _, poi in ipairs(taskPOIs) do
                    local id = poi.questID or poi.questId
                    if id then
                        local poiMapID = poi.mapID or poi.mapId or zoneMapID
                        if isPlayerZone or poiMapID == mapID then
                            nearbySet[id] = true
                            taskQuestOnlySet[id] = true
                        end
                    end
                end
            end
        end
    end

    -- Use cached zone WQ IDs when the world map was opened for this zone (fallback).
    if addon.zoneTaskQuestCache and addon.zoneTaskQuestCache[mapID] then
        for id, _ in pairs(addon.zoneTaskQuestCache[mapID]) do
            if id then
                nearbySet[id] = true
                taskQuestOnlySet[id] = true
            end
        end
    end
    return nearbySet, taskQuestOnlySet
end

-- World quest watch set for map-close diff.
local function GetCurrentWorldQuestWatchSet()
    local set = {}
    if C_QuestLog.GetNumWorldQuestWatches and C_QuestLog.GetQuestIDForWorldQuestWatchIndex then
        for i = 1, C_QuestLog.GetNumWorldQuestWatches() do
            local questID = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
            if questID then set[questID] = true end
        end
    end
    return set
end

-- Returns watch-list WQs plus in-zone active world quests/callings so they appear in the objective list.
-- taskQuestOnlySet: quest IDs from C_TaskQuest.GetQuestsForPlayerByMapID (map icons not yet in log); show these even when IsWorldQuest/IsActive are false.
local function GetWorldAndCallingQuestIDsToShow(nearbySet, taskQuestOnlySet)
    local out = {}
    local seen = {}
    if C_QuestLog.GetNumWorldQuestWatches and C_QuestLog.GetQuestIDForWorldQuestWatchIndex then
        addon.lastWorldQuestWatchSet = addon.lastWorldQuestWatchSet or {}
        wipe(addon.lastWorldQuestWatchSet)
        local numWorldWatches = C_QuestLog.GetNumWorldQuestWatches()
        for i = 1, numWorldWatches do
            local questID = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
            if questID and not seen[questID] then
                seen[questID] = true
                addon.lastWorldQuestWatchSet[questID] = true
                out[#out + 1] = { questID = questID, isTracked = true }
            end
        end
    end
    if nearbySet and C_QuestLog.IsWorldQuest then
        local recentlyUntracked = addon.recentlyUntrackedWorldQuests
        for questID, _ in pairs(nearbySet) do
            if not seen[questID] and (not recentlyUntracked or not recentlyUntracked[questID]) then
                local isWorld = C_QuestLog.IsWorldQuest(questID)
                local isCalling = C_QuestLog.IsQuestCalling and C_QuestLog.IsQuestCalling(questID)
                local isActiveTask = C_TaskQuest and C_TaskQuest.IsActive and C_TaskQuest.IsActive(questID)
                local fromTaskQuestMap = taskQuestOnlySet and taskQuestOnlySet[questID]
                if isWorld or isCalling or isActiveTask or fromTaskQuestMap then
                    seen[questID] = true
                    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
                        C_TaskQuest.RequestPreloadRewardData(questID)
                    end
                    local forceCategory = (fromTaskQuestMap and not isWorld and not isCalling) and "WORLD" or nil
                    out[#out + 1] = { questID = questID, isTracked = false, forceCategory = forceCategory }
                end
            end
        end
    end
    return out
end

local function RemoveWorldQuestWatch(questID)
    if not questID then return end
    if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) and C_QuestLog.RemoveWorldQuestWatch then
        C_QuestLog.RemoveWorldQuestWatch(questID)
    end
end

addon.zoneTaskQuestCache = addon.zoneTaskQuestCache or {}
addon.GetNearbyQuestIDs = GetNearbyQuestIDs
addon.GetWorldAndCallingQuestIDsToShow = GetWorldAndCallingQuestIDsToShow
addon.GetCurrentWorldQuestWatchSet = GetCurrentWorldQuestWatchSet
addon.RemoveWorldQuestWatch = RemoveWorldQuestWatch
