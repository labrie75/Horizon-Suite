--[[
    Horizon Suite - Focus - Utilities
    Shared helpers for design tokens, borders, text, logging, and quest/map helpers.
]]

local addon = _G.HorizonSuite
if not addon then
    addon = {}
    _G.HorizonSuite = addon
end

-- ============================================================================
-- DESIGN TOKENS
-- ============================================================================

addon.Design = addon.Design or {}
local Design = addon.Design

Design.BORDER_COLOR   = Design.BORDER_COLOR   or { 0.35, 0.38, 0.45, 0.45 }
Design.BACKDROP_COLOR = Design.BACKDROP_COLOR or { 0.08, 0.08, 0.12, 0.90 }
Design.SHADOW_COLOR   = Design.SHADOW_COLOR   or { 0, 0, 0 }
Design.QUEST_ITEM_BG     = Design.QUEST_ITEM_BG     or { 0.12, 0.12, 0.15, 0.9 }
Design.QUEST_ITEM_BORDER = Design.QUEST_ITEM_BORDER or { 0.30, 0.32, 0.38, 0.6 }

-- ============================================================================
-- QUEST ITEM BUTTON STYLING
-- ============================================================================

--- Apply unified slot-style visuals to a quest item button (per-entry or floating).
--- Adds dark backdrop, thin border; caller should add hover alpha in OnEnter/OnLeave.
--- @param btn Frame Button frame (SecureActionButtonTemplate) to style.
function addon.StyleQuestItemButton(btn)
    if not btn then return end
    local bg = Design.QUEST_ITEM_BG
    local bgTex = btn:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
    addon.CreateBorder(btn, Design.QUEST_ITEM_BORDER, 1)
end

-- ============================================================================
-- BORDERS & TEXT
-- ============================================================================

--- Create a simple 1px border around a frame.
-- @param frame Frame to receive border textures.
-- @param color Optional {r,g,b,a}; falls back to Design.BORDER_COLOR.
-- @param thickness Optional border thickness in pixels (default 1).
function addon.CreateBorder(frame, color, thickness)
    if not frame then return nil end
    local c = color or Design.BORDER_COLOR
    local t = thickness or 1

    local top = frame:CreateTexture(nil, "BORDER")
    top:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    top:SetHeight(t)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    bottom:SetHeight(t)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    left:SetWidth(t)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    right:SetWidth(t)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    return top, bottom, left, right
end

--- Safe helper for setting text color from a {r,g,b[,a]} table.
function addon.SetTextColor(fontString, color)
    if not fontString or not color then return end
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

--- Apply text case from DB option. Returns text in upper, lower, or proper (title) case based on dbKey.
-- @param text string or nil
-- @param dbKey string DB key (e.g. "headerTextCase"); values "upper", "lower", or "proper"
-- @param default string optional default when key is not set (e.g. "upper" for header, "proper" for title)
-- @return string
function addon.ApplyTextCase(text, dbKey, default)
    if text == nil or type(text) ~= "string" then return text end
    local v = addon.GetDB(dbKey, default or "proper")
    if v == "upper" then return text:upper() end
    if v == "lower" then return text:lower() end
    if v == "proper" or v == "default" then
        -- Title case: first letter of each word upper, rest lower.
        return text:gsub("(%a)([%w]*)", function(a, rest) return a:upper() .. rest:lower() end)
    end
    return text
end

--- Create a text + shadow pair using the addon font objects and shadow offsets.
-- Returns text, shadow.
function addon.CreateShadowedText(parent, fontObject, layer, shadowLayer)
    if not parent then return nil end
    local textLayer   = layer or "OVERLAY"
    local shadowLayer = shadowLayer or "BORDER"

    local text = parent:CreateFontString(nil, textLayer)
    if fontObject then
        text:SetFontObject(fontObject)
    end

    local shadow = parent:CreateFontString(nil, shadowLayer)
    if fontObject then
        shadow:SetFontObject(fontObject)
    end
    local ox = addon.SHADOW_OX or 2
    local oy = addon.SHADOW_OY or -2
    local a  = addon.SHADOW_A or 0.8
    shadow:SetTextColor(0, 0, 0, a)
    shadow:SetPoint("CENTER", text, "CENTER", ox, oy)

    return text, shadow
end

-- ============================================================================
-- LOGGING
-- ============================================================================

addon.PRINT_PREFIX = "|cFF00CCFFHorizon Suite - Focus:|r "

--- Standardized print helper with colored Horizon Suite prefix.
function addon.HSPrint(msg)
    local prefix = addon.PRINT_PREFIX
    if msg == nil then
        print(prefix)
    else
        print(prefix .. tostring(msg))
    end
end

-- ============================================================================
-- OPTION HELPERS
-- ============================================================================

--- Normalize legacy "bar" to "bar-left". Returns valid highlight style for layout/options.
function addon.NormalizeHighlightStyle(style)
    if style == "bar" then return "bar-left" end
    return style
end

-- ============================================================================
-- QUEST / MAP HELPERS
-- ============================================================================

--- Parse a Task POI table into a simple set of quest IDs.
-- Handles both array-style lists and keyed tables used by various C_TaskQuest APIs.
-- @param taskPOIs Table returned from C_TaskQuest.* APIs (may be nil).
-- @param outSet   Table used as a set; ids will be added as keys with value true.
-- @return number  Count of IDs added.
function addon.ParseTaskPOIs(taskPOIs, outSet)
    if not taskPOIs or not outSet then return 0 end
    local count = 0

    if #taskPOIs > 0 then
        for _, poi in ipairs(taskPOIs) do
            local id = (type(poi) == "table" and (poi.questID or poi.questId)) or (type(poi) == "number" and poi)
            if id and not outSet[id] then
                outSet[id] = true
                count = count + 1
            end
        end
    end

    for k, v in pairs(taskPOIs) do
        if type(k) == "number" and k > 0 then
            if not outSet[k] then
                outSet[k] = true
                count = count + 1
            end
        elseif type(v) == "table" then
            local id = v.questID or v.questId
            if id and not outSet[id] then
                outSet[id] = true
                count = count + 1
            end
        end
    end

    return count
end

-- Resolve C_TaskQuest world-quest-list API once at load time.
-- Newer builds expose GetQuestsForPlayerByMapID; older builds have GetQuestsOnMap.
addon.GetTaskQuestsForMap = C_TaskQuest and (C_TaskQuest.GetQuestsForPlayerByMapID or C_TaskQuest.GetQuestsOnMap) or nil

--- Open the quest details view for a quest ID, mirroring Blizzard's behavior.
-- Used by click handlers so the logic lives in one place.
function addon.OpenQuestDetails(questID)
    if not questID or not C_QuestLog then return end

    if QuestMapFrame_OpenToQuestDetails then
        QuestMapFrame_OpenToQuestDetails(questID)
        return
    end

    if C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(questID)
    end

    if OpenQuestLog then
        OpenQuestLog()
        return
    end

    -- Fallback: select quest and toggle world map if available.
    if not WorldMapFrame or not WorldMapFrame.IsShown then
        return
    end
    if not WorldMapFrame:IsShown() and ToggleWorldMap then
        ToggleWorldMap()
    end
end

