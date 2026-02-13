--[[
    Horizon Suite - Vista - Event Dispatch
    Zone changes, level up, boss emotes, achievements, quest events.
]]

local addon = _G.HorizonSuite
if not addon or not addon.Vista then return end

-- ============================================================================
-- QUEST TEXT DETECTION (used by VistaErrors and here)
-- ============================================================================

local function IsQuestText(msg)
    if not msg then return false end
    return msg:find("%d+/%d+")
        or msg:find("%%")
        or msg:find("slain")
        or msg:find("destroyed")
        or msg:find("Quest Accepted")
        or msg:find("Complete")
end

addon.Vista.IsQuestText = IsQuestText

-- ============================================================================
-- EVENT FRAME
-- ============================================================================

local eventFrame = CreateFrame("Frame")
local eventsRegistered = false

local VISTA_EVENTS = {
    "ADDON_LOADED",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_LEVEL_UP",
    "RAID_BOSS_EMOTE",
    "ACHIEVEMENT_EARNED",
    "QUEST_ACCEPTED",
    "QUEST_TURNED_IN",
    "UI_INFO_MESSAGE",
}

local function OnAddonLoaded(addonName)
    if addonName == "Blizzard_WorldQuestComplete" and addon.Vista.KillWorldQuestBanner then
        addon.Vista.KillWorldQuestBanner()
        eventFrame:UnregisterEvent("ADDON_LOADED")
    end
end

local function OnPlayerLevelUp(_, level)
    addon.Vista.QueueOrPlay("LEVEL_UP", "LEVEL UP", "You have reached level " .. (level or "??"))
end

local function OnRaidBossEmote(_, msg, unitName)
    local bossName = unitName or "Boss"
    local formatted = msg or ""
    formatted = formatted:gsub("|T.-|t", "")
    formatted = formatted:gsub("|c%x%x%x%x%x%x%x%x", "")
    formatted = formatted:gsub("|r", "")
    formatted = formatted:gsub("%%s", bossName)
    formatted = strtrim(formatted)
    addon.Vista.QueueOrPlay("BOSS_EMOTE", bossName, formatted)
end

local function OnAchievementEarned(_, achID)
    local _, name = GetAchievementInfo(achID)
    addon.Vista.QueueOrPlay("ACHIEVEMENT", "ACHIEVEMENT EARNED", name or "")
end

local function OnQuestAccepted(_, questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local title = C_QuestLog.GetTitleForQuestID(questID) or "New Quest"
        addon.Vista.QueueOrPlay("QUEST_ACCEPT", "QUEST ACCEPTED", title)
    else
        addon.Vista.QueueOrPlay("QUEST_ACCEPT", "QUEST ACCEPTED", "New Quest")
    end
end

local function OnQuestTurnedIn(_, questID)
    local title = "Objective"
    if C_QuestLog then
        if C_QuestLog.GetTitleForQuestID then
            title = C_QuestLog.GetTitleForQuestID(questID) or title
        end
        if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
            addon.Vista.QueueOrPlay("WORLD_QUEST", "WORLD QUEST", title)
            return
        end
    end
    addon.Vista.QueueOrPlay("QUEST_COMPLETE", "QUEST COMPLETE", title)
end

local function OnUIInfoMessage(_, msgType, msg)
    if IsQuestText(msg) and not (msg and (msg:find("Quest Accepted") or msg:find("Accepted"))) then
        addon.Vista.QueueOrPlay("QUEST_UPDATE", "QUEST UPDATE", msg or "")
    end
end

local function OnZoneChangedNewArea()
    local zone = GetZoneText() or "Unknown Zone"
    local sub  = GetSubZoneText() or ""
    local wait = addon.Vista.DISCOVERY_WAIT or 0.15
    C_Timer.After(wait, function()
        if not addon:IsModuleEnabled("vista") then return end
        local active = addon.Vista.active and addon.Vista.active()
        local activeTitle = addon.Vista.activeTitle and addon.Vista.activeTitle()
        local phase = addon.Vista.animPhase and addon.Vista.animPhase()
        if active and activeTitle == zone and (phase == "hold" or phase == "entrance") then
            addon.Vista.SoftUpdateSubtitle(sub)
            if addon.Vista.pendingDiscovery then
                addon.Vista.ShowDiscoveryLine()
                addon.Vista.pendingDiscovery = nil
            end
        else
            addon.Vista.QueueOrPlay("ZONE_CHANGE", zone, sub)
        end
    end)
end

local function OnZoneChanged()
    local sub = GetSubZoneText()
    if sub and sub ~= "" then
        local zone = GetZoneText() or ""
        local wait = addon.Vista.DISCOVERY_WAIT or 0.15
        C_Timer.After(wait, function()
            if not addon:IsModuleEnabled("vista") then return end
            local active = addon.Vista.active and addon.Vista.active()
            local activeTitle = addon.Vista.activeTitle and addon.Vista.activeTitle()
            local phase = addon.Vista.animPhase and addon.Vista.animPhase()
            if active and activeTitle == zone and (phase == "hold" or phase == "entrance") then
                addon.Vista.SoftUpdateSubtitle(sub)
                if addon.Vista.pendingDiscovery then
                    addon.Vista.ShowDiscoveryLine()
                    addon.Vista.pendingDiscovery = nil
                end
            else
                addon.Vista.QueueOrPlay("SUBZONE_CHANGE", zone, sub)
            end
        end)
    end
end

local eventHandlers = {
    ADDON_LOADED             = function(_, addonName) OnAddonLoaded(addonName) end,
    PLAYER_LEVEL_UP          = function(_, level) OnPlayerLevelUp(_, level) end,
    RAID_BOSS_EMOTE          = function(_, msg, unitName) OnRaidBossEmote(_, msg, unitName) end,
    ACHIEVEMENT_EARNED       = function(_, achID) OnAchievementEarned(_, achID) end,
    QUEST_ACCEPTED           = function(_, questID) OnQuestAccepted(_, questID) end,
    QUEST_TURNED_IN          = function(_, questID) OnQuestTurnedIn(_, questID) end,
    UI_INFO_MESSAGE          = function(_, msgType, msg) OnUIInfoMessage(_, msgType, msg) end,
    ZONE_CHANGED_NEW_AREA    = function() OnZoneChangedNewArea() end,
    ZONE_CHANGED             = function() OnZoneChanged() end,
    ZONE_CHANGED_INDOORS     = function() OnZoneChanged() end,
}

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if not addon:IsModuleEnabled("vista") then return end
    local fn = eventHandlers[event]
    if fn then fn(event, ...) end
end)

function addon.Vista.EnableEvents()
    if eventsRegistered then return end
    for _, evt in ipairs(VISTA_EVENTS) do
        eventFrame:RegisterEvent(evt)
    end
    eventsRegistered = true
end

function addon.Vista.DisableEvents()
    if not eventsRegistered then return end
    for _, evt in ipairs(VISTA_EVENTS) do
        eventFrame:UnregisterEvent(evt)
    end
    eventsRegistered = false
end

addon.Vista.eventFrame = eventFrame
