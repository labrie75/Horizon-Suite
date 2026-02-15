--[[
    Horizon Suite - Presence - Event Dispatch
    Zone changes, level up, boss emotes, achievements, quest events.
]]

local addon = _G.HorizonSuite
if not addon or not addon.Presence then return end

-- Temporary diagnostics for world quest live-update debugging. Set to true to log to chat.
local PRESENCE_DEBUG_WQ = false
local function DbgWQ(...)
    if not PRESENCE_DEBUG_WQ or not addon.HSPrint then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    addon.HSPrint("[Presence WQ] " .. table.concat(parts, " "))
end

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
    "PLAYER_ENTERING_WORLD",
    "SCENARIO_UPDATE",
    "SCENARIO_CRITERIA_UPDATE",
    "SCENARIO_COMPLETED",
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
local lastQuestObjectivesCache = {}  -- questID -> serialized objectives; only show toast when this changes
local QUEST_LOG_RETRY_DELAY = 0.2
local QUEST_LOG_MAX_RETRIES = 3

-- Scenario start: track transition !IsScenarioActive -> IsScenarioActive; suppress on reload.
local wasInScenario = false
local scenarioCheckPending = false
local SCENARIO_DEBOUNCE = 0.4

-- Resolve which world quest to show an objective update for.
-- Order: super-tracked > ReadTrackedQuests (only nearby). No quest-log fallback (no proximity data).
local function GetWorldQuestIDForObjectiveUpdate()
    -- 1. Super-tracked world quest (user focused in tracker)
    local super = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) and C_SuperTrack.GetSuperTrackedQuestID() or 0
    if super and super > 0 and addon.IsQuestWorldQuest and addon.IsQuestWorldQuest(super) then
        if not (C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(super)) then
            DbgWQ("GetWorldQuestID: super-tracked", super)
            return super
        end
    end
    -- 2. ReadTrackedQuests: only nearby/in-area quests (avoids distant WQ toasts after completing one)
    if addon.ReadTrackedQuests then
        local candidates = {}
        for _, q in ipairs(addon.ReadTrackedQuests()) do
            if q.questID and (q.category == "WORLD" or q.category == "CALLING") and not q.isComplete and q.isNearby then
                candidates[#candidates + 1] = q.questID
            end
        end
        DbgWQ("GetWorldQuestID: ReadTrackedQuests nearby WQ/CALLING incomplete count=", #candidates)
        if #candidates > 0 then return candidates[1] end
    else
        DbgWQ("GetWorldQuestID: ReadTrackedQuests nil")
    end
    DbgWQ("GetWorldQuestID: no candidate")
    return nil
end

-- Returns exit reason: "shown", "no_quest", "complete", "throttled", "unchanged"
local function TryShowQuestUpdate(questID)
    if not questID or questID <= 0 then
        DbgWQ("TryShowQuestUpdate: no_quest")
        return "no_quest"
    end
    if C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then
        DbgWQ("TryShowQuestUpdate: complete questID=", questID)
        lastQuestObjectivesCache[questID] = nil
        return "complete"
    end
    local now = GetTime()
    if lastQuestUpdateQuestID == questID and (now - lastQuestUpdateTime) < QUEST_UPDATE_THROTTLE then
        DbgWQ("TryShowQuestUpdate: throttled questID=", questID)
        return "throttled"
    end

    -- Build serialized objective state; only show if it actually changed (avoids periodic QUEST_LOG_UPDATE spam)
    local objectives = (C_QuestLog and C_QuestLog.GetQuestObjectives) and (C_QuestLog.GetQuestObjectives(questID) or {}) or {}
    local parts = {}
    for i = 1, #objectives do
        local o = objectives[i]
        parts[i] = (o and o.text or "") .. "|" .. (o and o.finished and "1" or "0")
    end
    local objKey = table.concat(parts, ";")
    if lastQuestObjectivesCache[questID] == objKey then
        DbgWQ("TryShowQuestUpdate: unchanged questID=", questID)
        return "unchanged"
    end
    lastQuestObjectivesCache[questID] = objKey
    lastQuestUpdateQuestID, lastQuestUpdateTime = questID, now

    local msg = nil
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
    if not msg or msg == "" then msg = "Objective updated" end

    addon.Presence.QueueOrPlay("QUEST_UPDATE", "QUEST UPDATE", StripPresenceMarkup(msg), { questID = questID })
    DbgWQ("TryShowQuestUpdate: shown questID=", questID)
    return "shown"
end

local function OnQuestWatchUpdate(_, questID)
    TryShowQuestUpdate(questID)
end

-- QUEST_WATCH_UPDATE does not fire for world/task quests; QUEST_LOG_UPDATE does.
-- Retry quest-ID resolution a few times (timing: map/quest APIs can lag).
local function OnQuestLogUpdate()
    if addon.Presence._suppressQuestUpdateOnReload then return end  -- suppress on reload
    if questLogUpdateTimer then return end  -- already pending
    DbgWQ("QUEST_LOG_UPDATE fired, starting retry chain")
    local retryCount = 0
    local function attempt()
        retryCount = retryCount + 1
        local questID = GetWorldQuestIDForObjectiveUpdate()
        DbgWQ("OnQuestLogUpdate attempt", retryCount, "questID=", tostring(questID))
        if questID and questID > 0 then
            questLogUpdateTimer = nil
            local reason = TryShowQuestUpdate(questID)
            DbgWQ("OnQuestLogUpdate: TryShowQuestUpdate questID=", questID, "reason=", reason)
            return
        end
        if retryCount < QUEST_LOG_MAX_RETRIES then
            questLogUpdateTimer = C_Timer.After(QUEST_LOG_RETRY_DELAY, attempt)
        else
            questLogUpdateTimer = nil
            DbgWQ("OnQuestLogUpdate: exhausted retries")
        end
    end
    questLogUpdateTimer = C_Timer.After(QUEST_LOG_RETRY_DELAY, attempt)
end

local function OnUIInfoMessage(_, msgType, msg)
    if IsQuestText(msg) and not (msg and (msg:find("Quest Accepted") or msg:find("Accepted"))) then
        local questID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) and C_SuperTrack.GetSuperTrackedQuestID() or nil
        if questID and questID <= 0 then questID = nil end
        if not questID then questID = GetWorldQuestIDForObjectiveUpdate() end
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

local function TryShowScenarioStart()
    if scenarioCheckPending then return end
    if not addon.IsScenarioActive or not addon.IsScenarioActive() then return end
    if wasInScenario then return end
    if addon.GetDB and not addon.GetDB("showScenarioEvents", true) then return end
    if not addon.GetScenarioDisplayInfo then return end

    scenarioCheckPending = true
    C_Timer.After(SCENARIO_DEBOUNCE, function()
        scenarioCheckPending = false
        if not addon:IsModuleEnabled("presence") then return end
        if not addon.IsScenarioActive or not addon.IsScenarioActive() then return end
        if wasInScenario then return end
        if addon.GetDB and not addon.GetDB("showScenarioEvents", true) then return end

        local title, subtitle, category = addon.GetScenarioDisplayInfo()
        if not title or title == "" then return end

        wasInScenario = true
        addon.Presence.QueueOrPlay("SCENARIO_START", StripPresenceMarkup(title), StripPresenceMarkup(subtitle or ""), { category = category })
    end)
end

local function OnPlayerEnteringWorld()
    -- On reload while in scenario: suppress "start" toast by initializing wasInScenario
    if not addon.Presence._scenarioInitDone then
        addon.Presence._scenarioInitDone = true
        wasInScenario = addon.IsScenarioActive and addon.IsScenarioActive()
    end
end

local function OnScenarioUpdate()
    TryShowScenarioStart()
end

local function OnScenarioCriteriaUpdate()
    TryShowScenarioStart()
end

local function OnScenarioCompleted()
    wasInScenario = false
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
    PLAYER_ENTERING_WORLD   = function() OnPlayerEnteringWorld() end,
    SCENARIO_UPDATE          = function() OnScenarioUpdate() end,
    SCENARIO_CRITERIA_UPDATE = function() OnScenarioCriteriaUpdate() end,
    SCENARIO_COMPLETED       = function() OnScenarioCompleted() end,
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
    -- Suppress QUEST_UPDATE toasts for 2s after enable (covers /reload; QUEST_LOG_UPDATE can fire before PLAYER_ENTERING_WORLD)
    addon.Presence._suppressQuestUpdateOnReload = true
    C_Timer.After(2, function()
        addon.Presence._suppressQuestUpdateOnReload = nil
    end)
end

function addon.Presence.DisableEvents()
    if not eventsRegistered then return end
    for _, evt in ipairs(PRESENCE_EVENTS) do
        eventFrame:UnregisterEvent(evt)
    end
    eventsRegistered = false
end

addon.Presence.eventFrame = eventFrame
