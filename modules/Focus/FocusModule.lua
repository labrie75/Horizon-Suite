--[[
    Horizon Suite - Focus Module
    Registers the Focus (objective tracker) module with the core.
    OnInit/OnEnable/OnDisable route initialization and teardown.
]]

local addon = _G.HorizonSuite
if not addon or not addon.RegisterModule then return end

-- ============================================================================
-- FOCUS MODULE DEFINITION
-- ============================================================================

local function HookWorldMapOnHide()
    if WorldMapFrame and not WorldMapFrame._HSOnHideHooked then
        WorldMapFrame._HSOnHideHooked = true
        WorldMapFrame:HookScript("OnHide", function()
            if not addon.GetCurrentWorldQuestWatchSet then return end
            local currentSet = addon.GetCurrentWorldQuestWatchSet()
            local lastSet = addon.lastWorldQuestWatchSet
            if lastSet and next(lastSet) then
                if not addon.recentlyUntrackedWorldQuests then addon.recentlyUntrackedWorldQuests = {} end
                for questID, _ in pairs(lastSet) do
                    if not currentSet[questID] then
                        addon.recentlyUntrackedWorldQuests[questID] = true
                    end
                end
            end
            addon.lastWorldQuestWatchSet = currentSet
            if addon.ScheduleRefresh then addon.ScheduleRefresh() end
        end)
    end
end

local function HookWorldMapOnShow()
    if WorldMapFrame and not WorldMapFrame._HSOnShowHooked then
        WorldMapFrame._HSOnShowHooked = true
        WorldMapFrame:HookScript("OnShow", function()
            C_Timer.After(0.5, function()
                if not addon.enabled or not WorldMapFrame then return end
                if addon.ScheduleRefresh then addon.ScheduleRefresh() end
            end)
        end)
    end
end

local function StartScenarioTimerHeartbeat()
    if addon._scenarioTimerHeartbeat then return end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1)
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -1000, -1000)
    f:Show()
    f._elapsed = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        if not addon.enabled or addon.collapsed then return end
        if addon.ShouldHideInCombat and addon.ShouldHideInCombat() then return end
        if not addon.GetDB("showScenarioEvents", true) then return end
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed < 5 then return end
        self._elapsed = 0
        if addon.IsScenarioActive and addon.IsScenarioActive() then
            if addon.ScheduleRefresh then addon.ScheduleRefresh() end
        end
    end)
    addon._scenarioTimerHeartbeat = f
end

local function tryHookWorldMap()
    HookWorldMapOnHide()
    HookWorldMapOnShow()
end

-- Expose for FocusEvents when Blizzard_WorldMap loads after us
addon.FocusModuleHooks = addon.FocusModuleHooks or {}
addon.FocusModuleHooks.WorldMap = tryHookWorldMap

addon:RegisterModule("focus", {
    title       = "Focus",
    description = "Objective tracker for quests, world quests, rares, achievements, and scenarios.",
    order       = 10,

    OnInit = function()
        -- One-time setup when module is first initialized.
        -- Pools, fonts, and config are created by other files at load.
    end,

    OnEnable = function()
        addon.enabled = true
        addon.RestoreSavedPosition()
        addon.ApplyTypography()
        addon.ApplyDimensions()
        if addon.ApplyBackdropOpacity then addon.ApplyBackdropOpacity() end
        if addon.ApplyBorderVisibility then addon.ApplyBorderVisibility() end
        if HorizonDB and HorizonDB.collapsed then
            addon.collapsed = true
            addon.chevron:SetText("+")
            addon.scrollFrame:Hide()
            addon.targetHeight  = addon.GetCollapsedHeight()
            addon.currentHeight = addon.GetCollapsedHeight()
        end
        StartScenarioTimerHeartbeat()
        C_Timer.After(0.5, tryHookWorldMap)
        for attempt = 1, 5 do
            C_Timer.After(1 + attempt, tryHookWorldMap)
        end
        C_Timer.After(1, tryHookWorldMap)
        if addon.TrySuppressTracker then addon.TrySuppressTracker() end
        if addon.ScheduleRefresh then addon.ScheduleRefresh() end
    end,

    OnDisable = function()
        addon.enabled = false
        if addon.RestoreTracker then addon.RestoreTracker() end
        addon.HS:Hide()
        if addon.pool then
            for i = 1, addon.POOL_SIZE do
                if addon.ClearEntry then addon.ClearEntry(addon.pool[i]) end
            end
        end
        if addon.activeMap then wipe(addon.activeMap) end
        if addon.HideAllSectionHeaders then addon.HideAllSectionHeaders() end
        addon.sectionIdx = 0
        if addon.UpdateFloatingQuestItem then addon.UpdateFloatingQuestItem(nil) end
        if addon.UpdateMplusBlock then addon.UpdateMplusBlock() end
    end,
})
