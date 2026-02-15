--[[
    Horizon Suite - Presence - Event Dispatch
    Zone changes, level up, boss emotes, achievements, quest events.
]]

local addon = _G.HorizonSuite
if not addon or not addon.Presence then return end

-- ============================================================================
-- FORMATTING & MARKUP
-- ============================================================================

local function StripPresenceMarkup(s)
    if not s or s == "" then return s or "" end
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return strtrim(s)
end

-- ============================================================================
-- QUEST TEXT DETECTION (used by PresenceErrors and here)
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

addon.Presence.IsQuestText = IsQuestText

-- ============================================================================
-- EVENT FRAME
-- ============================================================================

local eventFrame = CreateFrame("Frame")
local eventsRegistered = false

local PRESENCE_EVENTS = {
    "ADDON_LOADED",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_LEVEL_UP",
    "RAID_BOSS_EMOTE",
    "ACHIEVEMENT_EARNED",
    "QUEST_ACCEPTED",
    "QUEST_TURNED_IN",
    "QUEST_WATCH_UPDATE",
    "QUEST_LOG_UPDATE",
    "UI_INFO_MESSAGE",
}

local function OnAddonLoaded(addonName)
    if addonName == "Blizzard_WorldQuestComplete" and addon.Presence.KillWorldQuestBanner then
        -- Defer so the addon has time to create WorldQuestCompleteBannerFrame
        C_Timer.After(0, function()
            addon.Presence.KillWorldQuestBanner()
        end)
        C_Timer.After(0.5, function()
            addon.Presence.KillWorldQuestBanner()
            eventFrame:UnregisterEvent("ADDON_LOADED")
        end)
    end
end

local function OnPlayerLevelUp(_, level)
    addon.Presence.QueueOrPlay("LEVEL_UP", "LEVEL UP", "You have reached level " .. (level or "??"))
end

local function OnRaidBossEmote(_, msg, unitName)
    local bossName = unitName or "Boss"
    local formatted = msg or ""
    formatted = formatted:gsub("|T.-|t", "")
    formatted = formatted:gsub("|c%x%x%x%x%x%x%x%x", "")
    formatted = formatted:gsub("|r", "")
    formatted = formatted:gsub("%%s", bossName)
    formatted = strtrim(formatted)
    addon.Presence.QueueOrPlay("BOSS_EMOTE", bossName, formatted)
end

local function OnAchievementEarned(_, achID)
    local _, name = GetAchievementInfo(achID)
    addon.Presence.QueueOrPlay("ACHIEVEMENT", "ACHIEVEMENT EARNED", StripPresenceMarkup(name or ""))
end

local function OnQuestAccepted(_, questID)
    local opts = (questID and { questID = questID }) or {}
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local questName = StripPresenceMarkup(C_QuestLog.GetTitleForQuestID(questID) or "New Quest")
        if addon.IsQuestWorldQuest and addon.IsQuestWorldQuest(questID) then
            addon.Presence.QueueOrPlay("WORLD_QUEST_ACCEPT", "WORLD QUEST ACCEPTED", questName, opts)
        else
            addon.Presence.QueueOrPlay("QUEST_ACCEPT", "QUEST ACCEPTED", questName, opts)
        end
    else
        addon.Presence.QueueOrPlay("QUEST_ACCEPT", "QUEST ACCEPTED", "New Quest", opts)
    end
end

local function OnQuestTurnedIn(_, questID)
    local opts = (questID and { questID = questID }) or {}
    local questName = "Objective"
    if C_QuestLog then
        if C_QuestLog.GetTitleForQuestID then
            questName = StripPresenceMarkup(C_QuestLog.GetTitleForQuestID(questID) or questName)
        end
        -- Use addon.IsQuestWorldQuest (QuestUtils + C_QuestLog) so world quests are detected even at turn-in when quest may be removed from log
        if addon.IsQuestWorldQuest and addon.IsQuestWorldQuest(questID) then
            addon.Presence.QueueOrPlay("WORLD_QUEST", "WORLD QUEST", questName, opts)
            return
        end
    end
    addon.Presence.QueueOrPlay("QUEST_COMPLETE", "QUEST COMPLETE", questName, opts)
end

local lastQuestUpdateQuestID, lastQuestUpdateTime = nil, 0
local lastUIInfoMsg, lastUIInfoTime = nil, 0
local QUEST_UPDATE_THROTTLE = 1.5  -- seconds between toasts per quest
local questLogUpdateTimer = nil

local function TryShowQuestUpdate(questID)
    if not questID or questID <= 0 then return end
    if C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then return end
    local now = GetTime()
    if lastQuestUpdateQuestID == questID and (now - lastQuestUpdateTime) < QUEST_UPDATE_THROTTLE then return end
    lastQuestUpdateQuestID, lastQuestUpdateTime = questID, now

    local msg = nil
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local objectives = C_QuestLog.GetQuestObjectives(questID) or {}
        for i = 1, #objectives do
            local o = objectives[i]
            if o and o.text and o.text ~= "" and not o.finished then
                msg = o.text
                break
            end
        end
        if not msg and #objectives > 0 then
            local o = objectives[1]
            if o and o.text and o.text ~= "" then msg = o.text end
        end
    end
    if not msg or msg == "" then msg = "Objective updated" end

    addon.Presence.QueueOrPlay("QUEST_UPDATE", "QUEST UPDATE", StripPresenceMarkup(msg), { questID = questID })
end

local function OnQuestWatchUpdate(_, questID)
    TryShowQuestUpdate(questID)
end

-- QUEST_WATCH_UPDATE does not fire for world/task quests; QUEST_LOG_UPDATE does. Debounce and use super-tracked.
local function OnQuestLogUpdate()
    if questLogUpdateTimer then return end  -- already pending
    questLogUpdateTimer = C_Timer.After(0.2, function()
        questLogUpdateTimer = nil
        local questID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) and C_SuperTrack.GetSuperTrackedQuestID() or nil
        if not questID or questID <= 0 then return end
        if not (addon.IsQuestWorldQuest and addon.IsQuestWorldQuest(questID)) then return end  -- only for world quests (fallback)
        TryShowQuestUpdate(questID)
    end)
end

local function OnUIInfoMessage(_, msgType, msg)
    if IsQuestText(msg) and not (msg and (msg:find("Quest Accepted") or msg:find("Accepted"))) then
        local questID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) and C_SuperTrack.GetSuperTrackedQuestID() or nil
        if questID and questID <= 0 then questID = nil end
        -- Route through TryShowQuestUpdate when questID available: uses same per-quest throttle as QUEST_WATCH_UPDATE to prevent double toasts
        if questID then
            TryShowQuestUpdate(questID)
        else
            local now = GetTime()
            if lastUIInfoMsg == msg and (now - lastUIInfoTime) < QUEST_UPDATE_THROTTLE then return end
            lastUIInfoMsg, lastUIInfoTime = msg, now
            addon.Presence.QueueOrPlay("QUEST_UPDATE", "QUEST UPDATE", StripPresenceMarkup(msg or ""), {})
        end
    end
end

local function OnZoneChangedNewArea()
    local zone = GetZoneText() or "Unknown Zone"
    local sub  = GetSubZoneText() or ""
    local wait = addon.Presence.DISCOVERY_WAIT or 0.15
    C_Timer.After(wait, function()
        if not addon:IsModuleEnabled("presence") then return end
        local active = addon.Presence.active and addon.Presence.active()
        local activeTitle = addon.Presence.activeTitle and addon.Presence.activeTitle()
        local phase = addon.Presence.animPhase and addon.Presence.animPhase()
        if active and activeTitle == zone and (phase == "hold" or phase == "entrance") then
            addon.Presence.SoftUpdateSubtitle(sub)
            if addon.Presence.pendingDiscovery then
                addon.Presence.ShowDiscoveryLine()
                addon.Presence.pendingDiscovery = nil
            end
        else
            addon.Presence.QueueOrPlay("ZONE_CHANGE", StripPresenceMarkup(zone), StripPresenceMarkup(sub))
        end
    end)
end

local function OnZoneChanged()
    local sub = GetSubZoneText()
    if sub and sub ~= "" then
        local zone = GetZoneText() or ""
        local wait = addon.Presence.DISCOVERY_WAIT or 0.15
        C_Timer.After(wait, function()
            if not addon:IsModuleEnabled("presence") then return end
            local active = addon.Presence.active and addon.Presence.active()
            local activeTitle = addon.Presence.activeTitle and addon.Presence.activeTitle()
            local phase = addon.Presence.animPhase and addon.Presence.animPhase()
            if active and activeTitle == zone and (phase == "hold" or phase == "entrance") then
                addon.Presence.SoftUpdateSubtitle(sub)
                if addon.Presence.pendingDiscovery then
                    addon.Presence.ShowDiscoveryLine()
                    addon.Presence.pendingDiscovery = nil
                end
            else
                addon.Presence.QueueOrPlay("SUBZONE_CHANGE", StripPresenceMarkup(zone), StripPresenceMarkup(sub))
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
    QUEST_WATCH_UPDATE       = function(_, questID) OnQuestWatchUpdate(_, questID) end,
    QUEST_LOG_UPDATE         = function() OnQuestLogUpdate() end,
    UI_INFO_MESSAGE          = function(_, msgType, msg) OnUIInfoMessage(_, msgType, msg) end,
    ZONE_CHANGED_NEW_AREA    = function() OnZoneChangedNewArea() end,
    ZONE_CHANGED             = function() OnZoneChanged() end,
    ZONE_CHANGED_INDOORS     = function() OnZoneChanged() end,
}

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if not addon:IsModuleEnabled("presence") then return end
    local fn = eventHandlers[event]
    if fn then fn(event, ...) end
end)

function addon.Presence.EnableEvents()
    if eventsRegistered then return end
    for _, evt in ipairs(PRESENCE_EVENTS) do
        eventFrame:RegisterEvent(evt)
    end
    eventsRegistered = true
end

function addon.Presence.DisableEvents()
    if not eventsRegistered then return end
    for _, evt in ipairs(PRESENCE_EVENTS) do
        eventFrame:UnregisterEvent(evt)
    end
    eventsRegistered = false
end

addon.Presence.eventFrame = eventFrame
