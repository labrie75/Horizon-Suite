--[[
    Horizon Suite - Vista - Slash Commands
    /horizon vista [zone|discover|level|boss|ach|quest|wq|accept|update|all]
]]

local addon = _G.HorizonSuite
if not addon or not addon.Vista then return end

local HSPrint = addon.HSPrint or function(msg)
    print("|cFF00CCFFHorizon Suite:|r " .. tostring(msg or ""))
end

local function HandleVistaSlash(msg)
    local cmd = strtrim(msg or ""):lower()

    if InCombatLockdown() then
        print("|cFFFF0000Horizon Suite - Vista:|r Cannot run tests during combat.")
        return true
    end

    if cmd == "level" then
        addon.Vista.QueueOrPlay("LEVEL_UP", "LEVEL UP", "You have reached level 80")
    elseif cmd == "boss" then
        addon.Vista.QueueOrPlay("BOSS_EMOTE", "Ragnaros", "BY FIRE BE PURGED!")
    elseif cmd == "ach" then
        addon.Vista.QueueOrPlay("ACHIEVEMENT", "ACHIEVEMENT EARNED", "Exploring the Midnight Isles")
    elseif cmd == "quest" then
        addon.Vista.QueueOrPlay("QUEST_COMPLETE", "QUEST COMPLETE", "Objective Secured")
    elseif cmd == "wq" then
        addon.Vista.QueueOrPlay("WORLD_QUEST", "WORLD QUEST", "Azerite Mining")
    elseif cmd == "accept" then
        addon.Vista.QueueOrPlay("QUEST_ACCEPT", "QUEST ACCEPTED", "The Fate of the Horde")
    elseif cmd == "update" then
        addon.Vista.QueueOrPlay("QUEST_UPDATE", "QUEST UPDATE", "Boar Pelts: 7/10")
    elseif cmd == "zone" then
        addon.Vista.QueueOrPlay("ZONE_CHANGE", GetZoneText() or "Unknown Zone", GetSubZoneText() or "")
    elseif cmd == "discover" then
        addon.Vista.SetPendingDiscovery()
        addon.Vista.QueueOrPlay("ZONE_CHANGE", "The Waking Shores", "Obsidian Citadel")
    elseif cmd == "all" then
        HSPrint("Vista: Playing demo reel (10 notifications)...")
        local demos = {
            { "SUBZONE_CHANGE", "The Seat of Aspects",  ""                          },
            { "QUEST_ACCEPT",   "QUEST ACCEPTED",       "The Fate of the Horde"     },
            { "QUEST_UPDATE",   "QUEST UPDATE",         "Dragon Glyphs: 3/5"        },
            { "ZONE_CHANGE",    "Valdrakken",           "Thaldraszus"               },
            { "ZONE_CHANGE",    "The Waking Shores",    "Obsidian Citadel",  true  },
            { "QUEST_COMPLETE", "QUEST COMPLETE",       "Aiding the Accord"         },
            { "WORLD_QUEST",    "WORLD QUEST",          "Azerite Mining"            },
            { "ACHIEVEMENT",    "ACHIEVEMENT EARNED",   "Exploring Khaz Algar"     },
            { "BOSS_EMOTE",     "Ragnaros",             "BY FIRE BE PURGED!"       },
            { "LEVEL_UP",       "LEVEL UP",             "You have reached level 80" },
        }
        for i, d in ipairs(demos) do
            C_Timer.After((i - 1) * 3, function()
                if d[4] then addon.Vista.SetPendingDiscovery() end
                addon.Vista.QueueOrPlay(d[1], d[2], d[3])
            end)
        end
    elseif cmd == "" or cmd == "help" then
        print("|cFF00CCFFHorizon Suite - Vista Test Commands:|r")
        print("  /horizon vista         - Show help + test current zone")
        print("  /horizon vista zone     - Test Zone Change")
        print("  /horizon vista discover - Test Zone Discovery")
        print("  /horizon vista level    - Test Level Up")
        print("  /horizon vista boss     - Test Boss Emote")
        print("  /horizon vista ach      - Test Achievement")
        print("  /horizon vista accept   - Test Quest Accepted")
        print("  /horizon vista quest    - Test Quest Complete")
        print("  /horizon vista wq       - Test World Quest")
        print("  /horizon vista update   - Test Quest Update")
        print("  /horizon vista all      - Demo reel (all types)")
        addon.Vista.QueueOrPlay("ZONE_CHANGE", GetZoneText() or "Unknown Zone", GetSubZoneText() or "")
    else
        return false
    end

    return true
end

-- Wrap the existing /horizon handler to add vista subcommands
local oldHandler = SlashCmdList["MODERNQUESTTRACKER"]
SlashCmdList["MODERNQUESTTRACKER"] = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "vista" or cmd:match("^vista ") then
        local sub = cmd == "vista" and "" or strtrim(cmd:sub(7))
        if HandleVistaSlash(sub) then return end
    end
    if oldHandler then oldHandler(msg) end
end

addon.Vista.HandleVistaSlash = HandleVistaSlash
