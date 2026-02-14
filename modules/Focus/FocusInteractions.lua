--[[
    Horizon Suite - Focus - Interactions
    Mouse scripts on pool entries (click, tooltip, scroll).
]]

local addon = _G.HorizonSuite

-- INTERACTIONS
-- ============================================================================

local pool = addon.pool

StaticPopupDialogs["HORIZONSUITE_ABANDON_QUEST"] = StaticPopupDialogs["HORIZONSUITE_ABANDON_QUEST"] or {
    text = "Abandon %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        local data = self.data
        if data and data.questID and C_QuestLog and C_QuestLog.AbandonQuest then
            if C_QuestLog.SetSelectedQuest then
                C_QuestLog.SetSelectedQuest(data.questID)
            end
            C_QuestLog.AbandonQuest()
            addon.ScheduleRefresh()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

for i = 1, addon.POOL_SIZE do
    local e = pool[i]
    e:EnableMouse(true)

    e:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            if self.entryKey then
                local achID = self.entryKey:match("^ach:(%d+)$")
                if achID and self.achievementID then
                    local requireCtrl = addon.GetDB("requireCtrlForQuestClicks", false)
                    if requireCtrl and not IsControlKeyDown() then return end
                    if addon.OpenAchievementToAchievement then
                        addon.OpenAchievementToAchievement(self.achievementID)
                    end
                    return
                end
                local endID = self.entryKey:match("^endeavor:(%d+)$")
                if endID and self.endeavorID then
                    local requireCtrl = addon.GetDB("requireCtrlForQuestClicks", false)
                    if requireCtrl and not IsControlKeyDown() then return end
                    if HousingFramesUtil and HousingFramesUtil.OpenFrameToTaskID then
                        pcall(HousingFramesUtil.OpenFrameToTaskID, self.endeavorID)
                    elseif ToggleHousingDashboard then
                        ToggleHousingDashboard()
                    elseif HousingFrame and HousingFrame.Show then
                        if HousingFrame:IsShown() then HousingFrame:Hide() else HousingFrame:Show() end
                    end
                    return
                end
                local decorID = self.entryKey:match("^decor:(%d+)$")
                if decorID and self.decorID then
                    local requireCtrl = addon.GetDB("requireCtrlForQuestClicks", false)
                    if requireCtrl and not IsControlKeyDown() then return end
                    if IsShiftKeyDown() then
                        local trackTypeDecor = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Decor) or 3
                        if ContentTrackingUtil and ContentTrackingUtil.OpenMapToTrackable then
                            pcall(ContentTrackingUtil.OpenMapToTrackable, trackTypeDecor, self.decorID)
                        end
                    elseif IsAltKeyDown() then
                        if HousingFramesUtil and HousingFramesUtil.PreviewHousingDecorID then
                            pcall(HousingFramesUtil.PreviewHousingDecorID, self.decorID)
                        elseif ToggleHousingDashboard then
                            ToggleHousingDashboard()
                        elseif HousingFrame and HousingFrame.Show then
                            if HousingFrame:IsShown() then HousingFrame:Hide() else HousingFrame:Show() end
                        end
                    else
                        if not HousingDashboardFrame and C_AddOns and C_AddOns.LoadAddOn then
                            pcall(C_AddOns.LoadAddOn, "Blizzard_HousingDashboard")
                        end
                        local entryType = (Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor) or 1
                        local ok, info = pcall(function()
                            if C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByRecordID then
                                return C_HousingCatalog.GetCatalogEntryInfoByRecordID(entryType, self.decorID, true)
                            end
                        end)
                        if ok and info and HousingDashboardFrame and HousingDashboardFrame.SetTab and HousingDashboardFrame.catalogTab then
                            ShowUIPanel(HousingDashboardFrame)
                            HousingDashboardFrame:SetTab(HousingDashboardFrame.catalogTab)
                            if C_Timer and C_Timer.After then
                                C_Timer.After(0.5, function()
                                    if HousingDashboardFrame and HousingDashboardFrame.CatalogContent and HousingDashboardFrame.CatalogContent.PreviewFrame then
                                        local pf = HousingDashboardFrame.CatalogContent.PreviewFrame
                                        if pf.PreviewCatalogEntryInfo then
                                            pcall(pf.PreviewCatalogEntryInfo, pf, info)
                                        end
                                        if pf.Show then pf:Show() end
                                    end
                                end)
                            end
                        elseif ToggleHousingDashboard then
                            ToggleHousingDashboard()
                        elseif HousingFrame and HousingFrame.Show then
                            if HousingFrame:IsShown() then HousingFrame:Hide() else HousingFrame:Show() end
                        end
                    end
                    return
                end
                local vignetteGUID = self.entryKey:match("^vignette:(.+)$")
                if vignetteGUID and C_SuperTrack and C_SuperTrack.SetSuperTrackedVignette then
                    C_SuperTrack.SetSuperTrackedVignette(vignetteGUID)
                end
                if WorldMapFrame and not WorldMapFrame:IsShown() and ToggleWorldMap then
                    ToggleWorldMap()
                end
                return
            end
            if not self.questID then return end

            local requireCtrl = addon.GetDB("requireCtrlForQuestClicks", false)
            local isWorldQuest = addon.IsQuestWorldQuest and addon.IsQuestWorldQuest(self.questID)

            -- Shift+Left: always open quest log & map (safe, read-only). For world quests, optionally add to watch list.
            if IsShiftKeyDown() then
                if isWorldQuest and C_QuestLog.AddWorldQuestWatch then
                    -- With safety enabled, adding to watch for world quests requires Ctrl+Shift+Left.
                    if not requireCtrl or IsControlKeyDown() then
                        C_QuestLog.AddWorldQuestWatch(self.questID)
                        addon.ScheduleRefresh()
                    end
                end
                if addon.OpenQuestDetails then
                    addon.OpenQuestDetails(self.questID)
                end
                return
            end

            -- Non-world quests that are not yet tracked: add to tracker (respect Ctrl safety if enabled).
            if not isWorldQuest and self.isTracked == false then
                if requireCtrl and not IsControlKeyDown() then
                    -- Safety: ignore plain Left-click when Ctrl is required.
                    return
                end
                if C_QuestLog.AddQuestWatch then
                    C_QuestLog.AddQuestWatch(self.questID)
                end
                addon.ScheduleRefresh()
                return
            end

            -- Left (no modifier): focus (set as super-tracked quest).
            if requireCtrl and not IsControlKeyDown() then
                -- Safety: ignore plain Left-click on quests when Ctrl is required.
                return
            end
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(self.questID)
            end
            if addon.FullLayout and not InCombatLockdown() then
                addon.FullLayout()
            end
        elseif button == "RightButton" then
            if self.entryKey then
                local achID = self.entryKey:match("^ach:(%d+)$")
                if achID and self.achievementID then
                    local requireCtrl = addon.GetDB("requireCtrlForQuestClicks", false)
                    if requireCtrl and not IsControlKeyDown() then return end
                    local trackType = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement) or 2
                    local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 0
                    if C_ContentTracking and C_ContentTracking.StopTracking then
                        C_ContentTracking.StopTracking(trackType, self.achievementID, stopType)
                    elseif RemoveTrackedAchievement then
                        RemoveTrackedAchievement(self.achievementID)
                    end
                    addon.ScheduleRefresh()
                    return
                end
                local endID = self.entryKey:match("^endeavor:(%d+)$")
                if endID and self.endeavorID then
                    local requireCtrl = addon.GetDB("requireCtrlForQuestClicks", false)
                    if requireCtrl and not IsControlKeyDown() then return end
                    if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RemoveTrackedInitiativeTask then
                        pcall(C_NeighborhoodInitiative.RemoveTrackedInitiativeTask, self.endeavorID)
                    elseif C_Endeavors and C_Endeavors.StopTracking then
                        pcall(C_Endeavors.StopTracking, self.endeavorID)
                    end
                    addon.ScheduleRefresh()
                    return
                end
                local decorID = self.entryKey:match("^decor:(%d+)$")
                if decorID and self.decorID then
                    local requireCtrl = addon.GetDB("requireCtrlForQuestClicks", false)
                    if requireCtrl and not IsControlKeyDown() then return end
                    local trackTypeDecor = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Decor) or 3
                    local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 0
                    if C_ContentTracking and C_ContentTracking.StopTracking then
                        pcall(C_ContentTracking.StopTracking, trackTypeDecor, self.decorID, stopType)
                    end
                    addon.ScheduleRefresh()
                    return
                end
                local vignetteGUID = self.entryKey:match("^vignette:(.+)$")
                if vignetteGUID and C_SuperTrack and C_SuperTrack.GetSuperTrackedVignette then
                    if C_SuperTrack.GetSuperTrackedVignette() == vignetteGUID then
                        C_SuperTrack.SetSuperTrackedVignette(nil)
                    end
                end
                return
            end
            if self.questID then
                -- Shift+Right: abandon quest with confirmation.
                if IsShiftKeyDown() then
                    local questName = C_QuestLog.GetTitleForQuestID(self.questID) or "this quest"
                    StaticPopup_Show("HORIZONSUITE_ABANDON_QUEST", questName, nil, { questID = self.questID })
                    return
                end

                local requireCtrl = addon.GetDB("requireCtrlForQuestClicks", false)
                if requireCtrl and not IsControlKeyDown() then
                    -- Safety: ignore plain Right-click on quests when Ctrl is required.
                    return
                end

                -- Right (no modifier): if this quest is focused, unfocus only; otherwise untrack.
                if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.SetSuperTrackedQuestID then
                    local focusedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
                    if focusedQuestID and focusedQuestID == self.questID then
                        C_SuperTrack.SetSuperTrackedQuestID(0)
                        if addon.FullLayout and not InCombatLockdown() then
                            addon.FullLayout()
                        end
                        return
                    end
                end

                if addon.IsQuestWorldQuest and addon.IsQuestWorldQuest(self.questID) and addon.RemoveWorldQuestWatch then
                    addon.RemoveWorldQuestWatch(self.questID)
                elseif C_QuestLog.RemoveQuestWatch then
                    C_QuestLog.RemoveQuestWatch(self.questID)
                end
                addon.ScheduleRefresh()
            end
        end
    end)

    e:SetScript("OnEnter", function(self)
        if not self.questID and not self.entryKey then return end
        local r, g, b = self.titleText:GetTextColor()
        self._savedColor = { r, g, b }
        self.titleText:SetTextColor(
            math.min(r * 1.25, 1),
            math.min(g * 1.25, 1),
            math.min(b * 1.25, 1), 1)
        if self.creatureID then
            local link = ("unit:Creature-0-0-0-0-%d-0000000000"):format(self.creatureID)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok, err = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            if not ok and addon.HSPrint then addon.HSPrint("Tooltip SetHyperlink (creature) failed: " .. tostring(err)) end
            local att = _G.AllTheThings
            if att and att.Modules and att.Modules.Tooltip then
                local attach = att.Modules.Tooltip.AttachTooltipSearchResults
                local searchFn = att.SearchForObject or att.SearchForField
                if attach and searchFn then
                    local ok, err = pcall(attach, GameTooltip, searchFn, "npcID", self.creatureID)
                    if not ok and addon.HSPrint then addon.HSPrint("ATT tooltip attach failed: " .. tostring(err)) end
                end
            end
            GameTooltip:Show()
        elseif self.endeavorID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetInitiativeTaskChatLink then
                local ok, link = pcall(C_NeighborhoodInitiative.GetInitiativeTaskChatLink, self.endeavorID)
                if ok and link and link ~= "" then
                    local setOk, setErr = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                    if not setOk and addon.HSPrint then addon.HSPrint("Tooltip SetHyperlink (endeavor) failed: " .. tostring(setErr)) end
                else
                    GameTooltip:SetText(self.titleText:GetText() or "")
                    GameTooltip:AddLine(("Endeavor #%d"):format(self.endeavorID), 0.7, 0.7, 0.7)
                end
            else
                GameTooltip:SetText(self.titleText:GetText() or "")
                GameTooltip:AddLine(("Endeavor #%d"):format(self.endeavorID), 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        elseif self.decorID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.titleText:GetText() or "")
            GameTooltip:AddLine(("Decor #%d"):format(self.decorID), 0.7, 0.7, 0.7)
            GameTooltip:Show()
        elseif self.achievementID and GetAchievementLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = GetAchievementLink(self.achievementID)
            if link then
                local ok, err = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                if not ok and addon.HSPrint then addon.HSPrint("Tooltip SetHyperlink (achievement) failed: " .. tostring(err)) end
            else
                GameTooltip:SetText(self.titleText:GetText() or "")
            end
            GameTooltip:Show()
        elseif self.questID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok, err = pcall(GameTooltip.SetHyperlink, GameTooltip, "quest:" .. self.questID)
            if not ok and addon.HSPrint then addon.HSPrint("Tooltip SetHyperlink (quest) failed: " .. tostring(err)) end
            addon.AddQuestRewardsToTooltip(GameTooltip, self.questID)
            GameTooltip:Show()
        elseif self.entryKey then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.titleText:GetText() or "")
            GameTooltip:Show()
        end
    end)

    e:SetScript("OnLeave", function(self)
        if self._savedColor then
            local sc = self._savedColor
            self.titleText:SetTextColor(sc[1], sc[2], sc[3], 1)
            self._savedColor = nil
        end
        if GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)

    e:EnableMouseWheel(true)
    e:SetScript("OnMouseWheel", function(_, delta) addon.HandleScroll(delta) end)
end
