--[[
    Horizon Suite - Focus - Mythic+ Block
    Timer, completion %, affixes when in M+ dungeon.
]]

local addon = _G.HorizonSuite

-- ============================================================================
-- MYTHIC+ BANNER (ALWAYS-VISIBLE ABOVE / BELOW LIST)
-- ============================================================================

local mplusBlock = CreateFrame("Frame", nil, addon.HS)
mplusBlock:SetSize(addon.GetPanelWidth() - addon.PADDING * 2, 40)
mplusBlock:Hide()

-- Soft glassy background.
local mplusBg = mplusBlock:CreateTexture(nil, "BACKGROUND")
mplusBg:SetAllPoints()
mplusBg:SetColorTexture(0.02, 0.02, 0.05, 0.75)

-- Left accent bar using Dungeon color.
local accent = mplusBlock:CreateTexture(nil, "BORDER")
accent:SetWidth(3)
accent:SetPoint("TOPLEFT", mplusBlock, "TOPLEFT", 0, 0)
accent:SetPoint("BOTTOMLEFT", mplusBlock, "BOTTOMLEFT", 0, 0)
local dungeonColor = (addon.QUEST_COLORS and addon.QUEST_COLORS.DUNGEON) or { 0.6, 0.4, 1.0 }
accent:SetColorTexture(dungeonColor[1], dungeonColor[2], dungeonColor[3], 0.9)

local contentOffsetX = 6

local mplusTimerText = mplusBlock:CreateFontString(nil, "OVERLAY")
mplusTimerText:SetFontObject(addon.TitleFont)
mplusTimerText:SetTextColor(0.95, 0.95, 0.98, 1)
mplusTimerText:SetPoint("TOPLEFT", mplusBlock, "TOPLEFT", contentOffsetX, -1)

local mplusPctText = mplusBlock:CreateFontString(nil, "OVERLAY")
mplusPctText:SetFontObject(addon.ObjFont)
mplusPctText:SetTextColor(0.6, 0.85, 1, 1)
mplusPctText:SetPoint("TOPRIGHT", mplusBlock, "TOPRIGHT", -contentOffsetX, -2)
mplusPctText:SetJustifyH("RIGHT")

local mplusAffixesText = mplusBlock:CreateFontString(nil, "OVERLAY")
mplusAffixesText:SetFontObject(addon.SectionFont)
mplusAffixesText:SetTextColor(0.75, 0.78, 0.9, 1)
mplusAffixesText:SetPoint("TOPLEFT", mplusTimerText, "BOTTOMLEFT", 0, -3)
mplusAffixesText:SetPoint("TOPRIGHT", mplusBlock, "TOPRIGHT", -contentOffsetX, -6)
mplusAffixesText:SetWordWrap(true)
mplusAffixesText:SetJustifyH("LEFT")

addon.mplusBlock       = mplusBlock
addon.mplusTimerText   = mplusTimerText
addon.mplusPctText     = mplusPctText
addon.mplusAffixesText = mplusAffixesText

local function PositionMplusBlock(pos)
    mplusBlock:SetWidth(addon.GetPanelWidth() - addon.PADDING * 2)
    mplusAffixesText:SetWidth(addon.GetPanelWidth() - addon.PADDING * 2 - contentOffsetX * 2)
    mplusBlock:ClearAllPoints()
    if pos == "bottom" then
        -- Sit just above the panel's bottom padding.
        mplusBlock:SetPoint("BOTTOMLEFT", addon.HS, "BOTTOMLEFT", addon.PADDING, addon.PADDING)
        mplusBlock:SetPoint("BOTTOMRIGHT", addon.HS, "BOTTOMRIGHT", -addon.PADDING, addon.PADDING)
    else
        -- Sit directly under the header / divider area.
        local topOffset = addon.GetContentTop()
        mplusBlock:SetPoint("TOPLEFT", addon.HS, "TOPLEFT", addon.PADDING, topOffset)
        mplusBlock:SetPoint("TOPRIGHT", addon.HS, "TOPRIGHT", -addon.PADDING, topOffset)
    end
end

local function UpdateMplusBlock()
    local pos = addon.GetDB("mplusBlockPosition", "top") or "top"

    -- Debug preview: always show the banner with example data when enabled via /horizon mplusdebug.
    if addon.mplusDebugPreview then
        PositionMplusBlock(pos)

        local timerStr  = "Keystone +15"
        local pctStr    = "67%"
        local affixStr  = "Fortified  Bursting  Sanguine"

        mplusTimerText:SetText(timerStr)
        mplusPctText:SetText(pctStr)
        mplusAffixesText:SetText(affixStr)
        mplusBlock:Show()
        return
    end

    if not addon.GetDB("showMythicPlusBlock", false) or not addon.IsInMythicDungeon() then
        mplusBlock:Hide()
        return
    end

    PositionMplusBlock(pos)
    local timerStr, pctStr, affixStr = "", "", ""
    if C_Scenario and C_Scenario.GetScenarioInfo then
        local ok, info = pcall(C_Scenario.GetScenarioInfo)
        if not ok and addon.HSPrint then addon.HSPrint("C_Scenario.GetScenarioInfo failed") end
        if ok and info and info.name then
            if info.currentStage and info.numStages and info.numStages > 0 then
                pctStr = string.format("%d/%d", info.currentStage or 0, info.numStages or 0)
            end
        end
    end
    if C_Scenario and C_Scenario.GetScenarioStepInfo then
        local ok, stepInfo = pcall(function()
            return C_Scenario.GetScenarioStepInfo()
        end)
        if not ok and addon.HSPrint then addon.HSPrint("C_Scenario.GetScenarioStepInfo failed") end
        if ok and stepInfo then
            local progress = (type(stepInfo) == "table" and stepInfo.progress) or (type(stepInfo) == "number" and stepInfo)
            if progress then pctStr = tostring(progress) .. "%" end
        end
    end
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneLevel then
        local ok, level = pcall(C_ChallengeMode.GetActiveKeystoneLevel)
        if not ok and addon.HSPrint then addon.HSPrint("C_ChallengeMode.GetActiveKeystoneLevel failed") end
        if ok and level and level > 0 then
            timerStr = "Keystone +" .. tostring(level)
        end
    end
    if C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
        local ok, affixes = pcall(C_MythicPlus.GetCurrentAffixes)
        if not ok and addon.HSPrint then addon.HSPrint("C_MythicPlus.GetCurrentAffixes failed") end
        if ok and affixes and #affixes > 0 then
            local names = {}
            for _, a in ipairs(affixes) do
                if a and a.name then names[#names + 1] = a.name end
            end
            affixStr = table.concat(names, "  ")
        end
    end
    if timerStr == "" and C_Scenario and C_Scenario.GetScenarioInfo then
        timerStr = "M+"
    end
    mplusTimerText:SetText(timerStr ~= "" and timerStr or "Mythic+")
    mplusPctText:SetText(pctStr ~= "" and pctStr or "—")
    mplusAffixesText:SetText(affixStr ~= "" and affixStr or "—")
    mplusBlock:Show()
end

addon.UpdateMplusBlock = UpdateMplusBlock
