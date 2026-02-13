--[[
    Horizon Suite - Vista Module
    Cinematic zone text and notifications. Zone/subzone changes, discoveries,
    level up, boss emotes, achievements, quest accept/complete/update, world quests.
]]

local addon = _G.HorizonSuite
if not addon or not addon.RegisterModule then return end

addon:RegisterModule("vista", {
    title       = "Vista",
    description = "Cinematic zone text and notifications (zone changes, level up, boss emotes, achievements, quest updates).",
    order       = 20,

    OnInit = function()
        if addon.Vista and addon.Vista.Init then
            addon.Vista.Init()
        end
    end,

    OnEnable = function()
        if addon.Vista then
            if addon.Vista.EnableEvents then addon.Vista.EnableEvents() end
            if addon.Vista.SuppressBlizzard then addon.Vista.SuppressBlizzard() end
            if addon.Vista.MuteAlerts then addon.Vista.MuteAlerts() end
            if addon.Vista.HookUIErrorsFrame then addon.Vista.HookUIErrorsFrame() end
        end
    end,

    OnDisable = function()
        if addon.Vista then
            if addon.Vista.DisableEvents then addon.Vista.DisableEvents() end
            if addon.Vista.RestoreBlizzard then addon.Vista.RestoreBlizzard() end
            if addon.Vista.RestoreAlerts then addon.Vista.RestoreAlerts() end
            if addon.Vista.HideAndClear then addon.Vista.HideAndClear() end
        end
    end,
})
