--[[
    Horizon Suite - Vista - Error Frame & Alert Interception
    UIErrorsFrame hook for "Discovered" and quest text. AlertFrame muting.
]]

local addon = _G.HorizonSuite
if not addon or not addon.Vista then return end

-- ============================================================================
-- UIERRORSFRAME HOOK
-- ============================================================================

local uiErrorsHooked = false
local originalAddMessage = nil

local function OnUIErrorsAddMessage(self, msg)
    if msg and msg:find("Discovered") then
        addon.Vista.SetPendingDiscovery()
        local phase = addon.Vista.animPhase and addon.Vista.animPhase()
        if addon:IsModuleEnabled("vista") and phase and (phase == "entrance" or phase == "hold" or phase == "crossfade") then
            addon.Vista.ShowDiscoveryLine()
            addon.Vista.pendingDiscovery = nil
        end
        if self.Clear then self:Clear() end
        return
    end
    if addon.Vista.IsQuestText and addon.Vista.IsQuestText(msg) then
        if self.Clear then self:Clear() end
    end
end

local function HookUIErrorsFrame()
    if uiErrorsHooked or not UIErrorsFrame then return end
    if hooksecurefunc then
        hooksecurefunc(UIErrorsFrame, "AddMessage", function(self, msg)
            if not addon:IsModuleEnabled("vista") then return end
            OnUIErrorsAddMessage(self, msg)
        end)
        uiErrorsHooked = true
    end
end

local function UnhookUIErrorsFrame()
    -- hooksecurefunc cannot be undone; we simply stop acting in the callback when Vista is disabled
    -- The callback will remain but will no-op when addon:IsModuleEnabled("vista") is false
    uiErrorsHooked = false
end

-- ============================================================================
-- ALERT FRAME MUTING
-- ============================================================================

local alertsMuted = false
local alertEventsUnregistered = {}

local function MuteAlerts()
    if alertsMuted then return end
    pcall(function()
        if AlertFrame and AlertFrame.UnregisterEvent then
            AlertFrame:UnregisterEvent("ACHIEVEMENT_EARNED")
            alertEventsUnregistered["ACHIEVEMENT_EARNED"] = true
            AlertFrame:UnregisterEvent("QUEST_TURNED_IN")
            alertEventsUnregistered["QUEST_TURNED_IN"] = true
        end
    end)
    alertsMuted = true
end

local function RestoreAlerts()
    if not alertsMuted then return end
    pcall(function()
        if AlertFrame and AlertFrame.RegisterEvent then
            if alertEventsUnregistered["ACHIEVEMENT_EARNED"] then
                AlertFrame:RegisterEvent("ACHIEVEMENT_EARNED")
                alertEventsUnregistered["ACHIEVEMENT_EARNED"] = nil
            end
            if alertEventsUnregistered["QUEST_TURNED_IN"] then
                AlertFrame:RegisterEvent("QUEST_TURNED_IN")
                alertEventsUnregistered["QUEST_TURNED_IN"] = nil
            end
        end
    end)
    alertsMuted = false
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

addon.Vista.HookUIErrorsFrame = HookUIErrorsFrame
addon.Vista.UnhookUIErrorsFrame = UnhookUIErrorsFrame
addon.Vista.MuteAlerts = MuteAlerts
addon.Vista.RestoreAlerts = RestoreAlerts
