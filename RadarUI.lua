local _, addon = ...

-- ============================================================================
-- MountCollector — RadarUI.lua
-- Главный графический интерфейс аддона (тёмный плоский ElvUI / «Транспорт» стиль):
--   1. Всплывающие диалоги (ShowCopyLinkPopup, ShowMountDebugWindow, ShowSetAttemptsPopup)
--   2. Универсальный инспектор маунта с динамической высотой заголовков и карточек
--      (CreateMountInspectorWidget, PopulateMountInspectorPanel)
--   3. Главное двухколоночное окно /mc с адаптивной панелью вкладок (LayoutTopTabBar):
--      [В текущей зоне] -> [Ворлдбоссы] -> [Данж-лут] -> [Цепочки и Квесты] -> [Все траи] -> [Настройки]
--   4. Боковая док-колонка справа от стандартного окна «Транспорт» (MountJournal)
-- ============================================================================

local L = addon.L
local ui = addon.UIState
local ApplyFlatBackdrop = addon.ApplyFlatBackdrop
local CreateFlatButton = addon.CreateFlatButton

function addon:OpenMountInJournal(mountID)
    if not mountID then return end
    if not C_AddOns.IsAddOnLoaded("Blizzard_Collections") then
        UIParentLoadAddOn("Blizzard_Collections")
    end
    if ToggleCollectionsJournal then
        if not CollectionsJournal or not CollectionsJournal:IsShown() then
            ToggleCollectionsJournal(1)
        elseif CollectionsJournal_SetTab then
            CollectionsJournal_SetTab(CollectionsJournal, 1)
        end
    end
    if MountJournal and MountJournal_SelectByMountID then
        MountJournal_SelectByMountID(mountID)
    end
end

-- Всплывающее окошко для мгновенного копирования ссылки на Wowhead (Ctrl+C)
function addon:ShowCopyLinkPopup(url, subtitle)
    if not ui.copyPopup then
        local p = CreateFrame("Frame", "MountCollectorCopyPopup", UIParent, "BackdropTemplate")
        p:SetSize(440, 88)
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        ApplyFlatBackdrop(p, 0.05, 0.05, 0.06, 0.98, 1.0, 0.82, 0.0, 1.0)
        p:EnableMouse(true)

        p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -12)
        p.title:SetPoint("RIGHT", p, "RIGHT", -36, 0)
        p.title:SetJustifyH("LEFT")
        p.title:SetTextColor(1.0, 0.82, 0.0, 1.0)

        local closeBtn = CreateFlatButton(p, 22, 22, "X", false)
        closeBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -6, -6)
        closeBtn:SetScript("OnClick", function() p:Hide() end)

        local ebFrame = CreateFrame("Frame", nil, p, "BackdropTemplate")
        ebFrame:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -38)
        ebFrame:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -14, 14)
        ApplyFlatBackdrop(ebFrame, 0.02, 0.02, 0.03, 1.0, 0.30, 0.30, 0.35, 1.0)

        local eb = CreateFrame("EditBox", nil, ebFrame)
        eb:SetPoint("TOPLEFT", ebFrame, "TOPLEFT", 8, -4)
        eb:SetPoint("BOTTOMRIGHT", ebFrame, "BOTTOMRIGHT", -8, 4)
        eb:SetFontObject("ChatFontNormal")
        eb:SetAutoFocus(true)
        eb:SetScript("OnEscapePressed", function() p:Hide() end)
        eb:SetScript("OnEnterPressed", function() p:Hide() end)
        p.editBox = eb

        ui.copyPopup = p
    end

    local p = ui.copyPopup
    p.title:SetText(subtitle and (L.WOWHEAD_POPUP_TITLE .. " |cffffffff" .. subtitle .. "|r") or L.WOWHEAD_POPUP_TITLE)
    p:Show()
    p.editBox:SetText(url or "")
    p.editBox:SetFocus()
    p.editBox:HighlightText()
end

    -- 1b. Окно Lua-дебаггера квестовых цепочек и условий (MountCollectorDebugFrame)
function addon:ShowMountDebugWindow(mountID)
    local targetMountID = mountID
        or (MountJournal and MountJournal:IsShown() and MountJournal.selectedMountID)
        or ui.selectedMountID
        or 861

    if not ui.debugFrame then
        local f = CreateFrame("Frame", "MountCollectorDebugFrame", UIParent, "BackdropTemplate")
        f:SetSize(660, 480)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        ApplyFlatBackdrop(f, 0.04, 0.04, 0.05, 0.98, 1.0, 0.82, 0.0, 1.0)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local top = CreateFrame("Frame", nil, f, "BackdropTemplate")
        top:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        top:SetHeight(28)
        ApplyFlatBackdrop(top, 0.08, 0.08, 0.10, 0.98, 0.22, 0.22, 0.25, 1.0)

        f.title = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("LEFT", top, "LEFT", 12, 0)
        f.title:SetTextColor(1.0, 0.82, 0.0, 1.0)
        f.title:SetText(L.DEBUG_WINDOW_TITLE)

        local closeBtn = CreateFlatButton(top, 22, 22, "X", false)
        closeBtn:SetPoint("RIGHT", top, "RIGHT", -4, 0)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        local bodyBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
        bodyBg:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -36)
        bodyBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 44)
        ApplyFlatBackdrop(bodyBg, 0.02, 0.02, 0.03, 0.98, 0.22, 0.22, 0.26, 1.0)

        local sf = CreateFrame("ScrollFrame", "MountCollectorDebugScroll", bodyBg, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", bodyBg, "TOPLEFT", 8, -8)
        sf:SetPoint("BOTTOMRIGHT", bodyBg, "BOTTOMRIGHT", -28, 8)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetWidth(590)
        eb:SetFontObject("ChatFontNormal")
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        sf:SetScrollChild(eb)
        f.editBox = eb

        local btnRefresh = CreateFlatButton(f, 200, 26, L.DEBUG_REFRESH_BTN, false)
        btnRefresh:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
        btnRefresh:SetScript("OnClick", function()
            if f.currentMountID then
                local report = addon:BuildMountDebugReport(f.currentMountID)
                f.editBox:SetText(report)
            end
        end)
        f.btnRefresh = btnRefresh

        local btnCopy = CreateFlatButton(f, 240, 26, L.DEBUG_COPY_BTN, true)
        btnCopy:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
        btnCopy:SetScript("OnClick", function()
            f.editBox:SetFocus()
            f.editBox:HighlightText()
        end)
        f.btnCopy = btnCopy

        ui.debugFrame = f
    end

    local f = ui.debugFrame
    f.currentMountID = targetMountID
    f.title:SetText(L.DEBUG_WINDOW_TITLE)
    f.btnRefresh:SetText(L.DEBUG_REFRESH_BTN)
    f.btnCopy:SetText(L.DEBUG_COPY_BTN)
    f.editBox:SetText(self:BuildMountDebugReport(targetMountID))
    f:Show()
end

-- Окно ручной настройки / корректировки счётчика траев (для Всадника без головы и исторических боссов)
function addon:ShowSetAttemptsPopup(mountID)
    local targetMountID = mountID or ui.selectedMountID or (MountJournal and MountJournal.selectedMountID)
    if not targetMountID then return end

    if not ui.setAttemptsFrame then
        local f = CreateFrame("Frame", "MountCollectorSetAttemptsFrame", UIParent, "BackdropTemplate")
        f:SetSize(460, 210)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        ApplyFlatBackdrop(f, 0.05, 0.05, 0.06, 0.98, 1.0, 0.82, 0.0, 1.0)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local top = CreateFrame("Frame", nil, f, "BackdropTemplate")
        top:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        top:SetHeight(26)
        ApplyFlatBackdrop(top, 0.09, 0.09, 0.10, 0.98, 0.22, 0.22, 0.25, 1.0)

        local title = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", top, "LEFT", 10, 0)
        f.title = title

        local btnClose = CreateFlatButton(top, 20, 20, "X", false)
        btnClose:SetPoint("RIGHT", top, "RIGHT", -4, 0)
        btnClose:SetScript("OnClick", function() f:Hide() end)

        local mountLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        mountLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -36)
        mountLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -36)
        mountLabel:SetJustifyH("LEFT")
        f.mountLabel = mountLabel

        local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", mountLabel, "BOTTOMLEFT", 0, -6)
        desc:SetPoint("RIGHT", f, "RIGHT", -14, 0)
        desc:SetJustifyH("LEFT")
        desc:SetTextColor(0.82, 0.82, 0.85, 1.0)
        f.desc = desc

        local boxFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
        boxFrame:SetSize(130, 28)
        boxFrame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 44)
        ApplyFlatBackdrop(boxFrame, 0.02, 0.02, 0.03, 1.0, 0.85, 0.68, 0.15, 1.0)

        local eb = CreateFrame("EditBox", nil, boxFrame)
        eb:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 8, -2)
        eb:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -8, 2)
        eb:SetFontObject("GameFontHighlightLarge")
        eb:SetJustifyH("CENTER")
        eb:SetAutoFocus(false)
        eb:SetNumeric(true)
        eb:SetMaxLetters(6)
        f.editBox = eb

        local function AdjustVal(delta)
            local cur = tonumber(eb:GetText()) or 0
            eb:SetText(tostring(math.max(0, cur + delta)))
        end

        local btnMinus1 = CreateFlatButton(f, 44, 28, "-1", false)
        btnMinus1:SetPoint("LEFT", boxFrame, "RIGHT", 6, 0)
        btnMinus1:SetScript("OnClick", function() AdjustVal(-1) end)

        local btnPlus1 = CreateFlatButton(f, 44, 28, "+1", false)
        btnPlus1:SetPoint("LEFT", btnMinus1, "RIGHT", 5, 0)
        btnPlus1:SetScript("OnClick", function() AdjustVal(1) end)

        local btnPlus10 = CreateFlatButton(f, 52, 28, "+10", false)
        btnPlus10:SetPoint("LEFT", btnPlus1, "RIGHT", 5, 0)
        btnPlus10:SetScript("OnClick", function() AdjustVal(10) end)

        local btnPlus50 = CreateFlatButton(f, 52, 28, "+50", false)
        btnPlus50:SetPoint("LEFT", btnPlus10, "RIGHT", 5, 0)
        btnPlus50:SetScript("OnClick", function() AdjustVal(50) end)

        local btnSave = CreateFlatButton(f, 210, 26, L.SET_ATTEMPTS_SAVE, true)
        btnSave:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 10)
        btnSave:SetScript("OnClick", function()
            if f.currentMountID then
                local val = tonumber(eb:GetText()) or 0
                addon:SetManualMountAttempts(f.currentMountID, val, false)
            end
            f:Hide()
        end)
        f.btnSave = btnSave

        local btnReset = CreateFlatButton(f, 210, 26, L.SET_ATTEMPTS_RESET, false)
        btnReset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)
        btnReset:SetScript("OnClick", function()
            if f.currentMountID then
                addon:SetManualMountAttempts(f.currentMountID, 0, true)
            end
            f:Hide()
        end)
        f.btnReset = btnReset

        eb:SetScript("OnEnterPressed", function()
            btnSave:Click()
        end)
        eb:SetScript("OnEscapePressed", function()
            f:Hide()
        end)

        ui.setAttemptsFrame = f
    end

    local f = ui.setAttemptsFrame
    f.currentMountID = targetMountID
    local name, _, icon = C_MountJournal.GetMountInfoByID(targetMountID)
    local curAttempts = self:GetMountAttempts(targetMountID)
    local iconTag = icon and string.format("|T%s:20:20:0:0|t ", icon) or ""

    f.title:SetText(L.SET_ATTEMPTS_TITLE)
    f.mountLabel:SetText(iconTag .. "|cffa335ee" .. (name or "Mount") .. "|r")
    f.desc:SetText(L.SET_ATTEMPTS_DESC)
    f.btnSave:SetText(L.SET_ATTEMPTS_SAVE)
    f.btnReset:SetText(L.SET_ATTEMPTS_RESET)
    f.editBox:SetText(tostring(curAttempts or 0))
    f:Show()
    f.editBox:SetFocus()
    f.editBox:HighlightText()
end


-- ============================================================================
-- 3. РЕНДЕР ПРАВОЙ КОЛОНКИ (ДОСЬЕ + ЧЕК-ЛИСТ ШАГОВ + КНОПКИ НАВИГАЦИИ)
-- Используется как в окне /mc, так и в боковой док-колонке окна «Транспорт»!
-- ============================================================================
local function GetOrCreateChecklistCard(pool, parent, index, cardWidth)
    if pool[index] then
        pool[index]:SetWidth(cardWidth)
        return pool[index]
    end

    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetWidth(cardWidth)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ApplyFlatBackdrop(card, 0.08, 0.08, 0.10, 0.94, 0.22, 0.22, 0.26, 1.0)

    card.coordsFS = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.coordsFS:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -8)
    card.coordsFS:SetJustifyH("RIGHT")
    card.coordsFS:SetWordWrap(false)

    card.statusFS = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.statusFS:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
    card.statusFS:SetPoint("RIGHT", card.coordsFS, "LEFT", -8, 0)
    card.statusFS:SetJustifyH("LEFT")
    card.statusFS:SetWordWrap(false)

    card.titleFS = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.titleFS:SetPoint("TOPLEFT", card.statusFS, "BOTTOMLEFT", 0, -5)
    card.titleFS:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    card.titleFS:SetJustifyH("LEFT")
    card.titleFS:SetWordWrap(true)

    card.npcFS = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.npcFS:SetPoint("TOPLEFT", card.titleFS, "BOTTOMLEFT", 0, -4)
    card.npcFS:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    card.npcFS:SetJustifyH("LEFT")
    card.npcFS:SetWordWrap(false)

    card.descFS = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.descFS:SetPoint("TOPLEFT", card.npcFS, "BOTTOMLEFT", 0, -5)
    card.descFS:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    card.descFS:SetJustifyH("LEFT")
    card.descFS:SetJustifyV("TOP")
    card.descFS:SetWordWrap(true)
    if card.descFS.SetSpacing then
        card.descFS:SetSpacing(3)
    end

    card:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.rawTitle or "Step", 1, 0.82, 0)
        if self.rawDesc and self.rawDesc ~= "" then
            GameTooltip:AddLine(self.rawDesc, 1, 1, 1, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.QUEST_STEP_CLICK_HINT)
        GameTooltip:Show()
    end)

    card:SetScript("OnLeave", function(self)
        if self.defaultBorder then
            self:SetBackdropBorderColor(unpack(self.defaultBorder))
        end
        GameTooltip:Hide()
    end)

    card:SetScript("OnClick", function(self, button)
        if not self.mountID then return end
        if button == "RightButton" then
            local url = addon:GetMountWowheadURL(self.mountID, self.doneQuest)
            addon:ShowCopyLinkPopup(url, self.rawTitle)
        elseif self.stepIndex then
            addon:NavigateMountQuestStep(self.mountID, self.stepIndex, false)
        elseif self.customMapID and self.customX and self.customY then
            addon:SetMountWaypoint(self.mountID, self.customMapID, self.customX, self.customY, self.customNpc, false)
        else
            addon:NavigateMountTarget(self.mountID, false)
        end
    end)

    pool[index] = card
    return card
end

local function PopulateMountInspectorPanel(panel, mountID, pool, cardWidth)
    for _, c in ipairs(pool) do
        c:Hide()
    end

    if panel.secLabel then
        panel.secLabel:SetText(L.SECTION_CHECKLIST)
    end
    if panel.btnDebug then
        panel.btnDebug:SetText(L.QUEST_DEBUG_BTN)
        if panel.btnDebug.AutoSizeWidth then
            panel.btnDebug:AutoSizeWidth(92, 175, 16)
        end
    end
    if panel.btnSetAttempts then
        panel.btnSetAttempts:SetText(L.BTN_SET_ATTEMPTS)
        if panel.btnSetAttempts.AutoSizeWidth then
            panel.btnSetAttempts:AutoSizeWidth(86, 155, 16)
        end
    end
    if panel.btnNavNow then
        panel.btnNavNow:SetText(L.QUEST_NAV_BTN)
    end
    if panel.btnWowhead then
        panel.btnWowhead:SetText(L.QUEST_WOWHEAD_BTN)
    end
    if panel.btnFourth then
        panel.btnFourth:SetText(panel.isDockedInJournal and L.QUEST_OPEN_MC_BTN or L.QUEST_JOURNAL_BTN)
    end

    if not mountID then
        panel.iconFrame:Hide()
        panel.nameFS:SetText("")
        panel.metaFS:SetText("")
        panel.scrollContent:SetHeight(1)
        if panel.btnNavStart then
            panel.btnNavStart:SetText(L.QUEST_START_BTN)
        end
        return
    end

    local name, spellID, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    if not name then return end

    local _, description, sourceText = C_MountJournal.GetMountInfoExtraByID(mountID)
    local realm, _, estOwners, seenCount, globalPct = addon:GetServerRarityInfo(mountID)
    local pctText, tierText = addon:FormatRarityTier(globalPct)
    local attempts, byChar, dropInfo = addon:GetMountAttempts(mountID)
    local qStatus = addon:GetMountQuestChainStatus(mountID)
    local dStatus = (not qStatus) and addon:GetDungeonMountStatus(mountID) or nil
    local bestCoord = addon:GetBestMountCoords(mountID)

    if panel.btnSetAttempts then
        if qStatus then
            panel.btnSetAttempts:Hide()
            if panel.secLabel and panel.btnDebug then
                panel.secLabel:ClearAllPoints()
                panel.secLabel:SetPoint("TOPLEFT", panel.headerBox, "BOTTOMLEFT", 2, -8)
                panel.secLabel:SetPoint("RIGHT", panel.btnDebug, "LEFT", -6, 0)
            end
        else
            panel.btnSetAttempts:Show()
            if panel.secLabel then
                panel.secLabel:ClearAllPoints()
                panel.secLabel:SetPoint("TOPLEFT", panel.headerBox, "BOTTOMLEFT", 2, -8)
                panel.secLabel:SetPoint("RIGHT", panel.btnSetAttempts, "LEFT", -6, 0)
            end
        end
    end

    local fullW = cardWidth + 16
    local halfW = math.floor(fullW / 2) - 3

    if isCollected then
        if panel.btnNavNow then panel.btnNavNow:Hide() end
        if panel.btnNavStart then panel.btnNavStart:Hide() end
        if panel.btnBar then panel.btnBar:SetHeight(24) end
        if panel.scrollFrame then
            panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 38)
        end
    elseif dStatus and dStatus.sourceKind ~= "WORLD_BOSS" and not (dStatus.entry and dStatus.entry.isWorldBoss) then
        -- Для боссов подземелий и рейдов скрываем «Отметить все спавны» и растягиваем «Отметить вход в данж» на всю ширину
        if panel.btnNavNow then
            panel.btnNavNow:SetWidth(fullW)
            panel.btnNavNow:SetText(L.DUNGEON_ENTRANCE_BTN)
            panel.btnNavNow:Show()
        end
        if panel.btnNavStart then
            panel.btnNavStart:Hide()
        end
        if panel.btnBar then panel.btnBar:SetHeight(54) end
        if panel.scrollFrame then
            panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 68)
        end
    elseif dStatus and (dStatus.sourceKind == "WORLD_BOSS" or (dStatus.entry and dStatus.entry.isWorldBoss)) and dStatus.spellID ~= 448941 then
        -- Для ворлдбоссов с фиксированной точкой спавна
        if panel.btnNavNow then
            panel.btnNavNow:SetWidth(fullW)
            panel.btnNavNow:SetText(L.WORLDBOSS_SPAWN_BTN or L.QUEST_NAV_BTN)
            panel.btnNavNow:Show()
        end
        if panel.btnNavStart then
            panel.btnNavStart:Hide()
        end
        if panel.btnBar then panel.btnBar:SetHeight(54) end
        if panel.scrollFrame then
            panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 68)
        end
    else
        if panel.btnNavNow then
            panel.btnNavNow:SetWidth(halfW)
            panel.btnNavNow:SetText((dStatus and dStatus.sourceKind == "WORLD_BOSS") and (L.WORLDBOSS_SPAWN_BTN or L.QUEST_NAV_BTN) or L.QUEST_NAV_BTN)
            panel.btnNavNow:Show()
        end
        if panel.btnNavStart then
            panel.btnNavStart:SetWidth(halfW)
            panel.btnNavStart:SetText(qStatus and L.QUEST_START_BTN or L.RARE_PIN_ALL_BTN)
            panel.btnNavStart:Show()
        end
        if panel.btnBar then panel.btnBar:SetHeight(54) end
        if panel.scrollFrame then
            panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 68)
        end
    end

    panel.iconFrame:Show()
    panel.iconTex:SetTexture(icon or "Interface\\ICONS\\Ability_Mount_SpectralTiger")

    local colTag = isCollected and L.TAG_COLLECTED or L.TAG_NOT_COLLECTED
    panel.nameFS:SetText(string.format("|cffffffff%s|r  %s", name, colTag))

    local metaLines = {}
    if qStatus then
        local curZone = (qStatus.currentStep and qStatus.currentStep.zone) or ""
        table.insert(metaLines, string.format(L.META_CHAIN_TYPE_ZONE, qStatus.category, curZone ~= "" and curZone or "—"))
        table.insert(metaLines, string.format(L.META_CHAIN_PROGRESS, qStatus.completedSteps, qStatus.totalSteps))
    elseif dStatus then
        if dStatus.eventTitle then
            table.insert(metaLines, string.format(L.REQUIRES_EVENT_FMT, dStatus.eventTitle))
        end
        table.insert(metaLines, string.format(L.DUNGEON_META_LINE1_FMT, dStatus.instanceTitle, dStatus.bossTitle))
        table.insert(metaLines, string.format(L.DUNGEON_META_LINE2_FMT, dStatus.difficultyTitle, dStatus.lockoutTitle, dStatus.minLevel))
        local chStr = string.format(L.MD_CHANCE_PART, dStatus.chance)
        table.insert(metaLines, string.format(L.META_DROP_ATTEMPTS, attempts, chStr))
    else
        local bestCoordName = bestCoord and ((bestCoord.npcID and addon.KnownNpcNames and addon.KnownNpcNames[bestCoord.npcID]) or (bestCoord.n and bestCoord.n ~= "" and bestCoord.n)) or nil
        local bossStr = bestCoordName or (dropInfo and dropInfo.boss) or "—"
        local zoneStr = "—"
        if bestCoord and bestCoord.m and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(bestCoord.m) then
            zoneStr = string.format("%s [%.1f, %.1f]", C_Map.GetMapInfo(bestCoord.m).name or "", bestCoord.x or 0, bestCoord.y or 0)
        end
        table.insert(metaLines, string.format(L.META_DROP_SOURCE_ZONE, bossStr, zoneStr))
        if attempts > 0 or (dropInfo and dropInfo.chance) then
            local chStr = (dropInfo and dropInfo.chance) and string.format(L.MD_CHANCE_PART, dropInfo.chance) or ""
            table.insert(metaLines, string.format(L.META_DROP_ATTEMPTS, attempts, chStr))
        end
    end

    if globalPct then
        local srvPart = estOwners and string.format(L.MD_SERVER_PART, realm, estOwners) or ""
        table.insert(metaLines, string.format("%s %s (%s)%s", L.MD_RARITY_LABEL, pctText, tierText, srvPart))
    end

    panel.metaFS:SetText(table.concat(metaLines, "\n"))
    if panel.headerBox then
        local nameH = math.ceil(panel.nameFS:GetStringHeight() or 20)
        local topBlockH = math.max(44, nameH + 4)
        panel.metaFS:ClearAllPoints()
        panel.metaFS:SetPoint("TOPLEFT", panel.headerBox, "TOPLEFT", 10, -(10 + topBlockH + 8))
        panel.metaFS:SetPoint("RIGHT", panel.headerBox, "RIGHT", -10, 0)
        local metaH = math.ceil(panel.metaFS:GetStringHeight() or 40)
        panel.headerBox:SetHeight(math.max(98, 10 + topBlockH + 8 + metaH + 12))
    end

    -- Заполняем карточки шагов (Сделано / Надо сделать)
    local stepsToRender = {}
    if qStatus and qStatus.steps then
        for _, st in ipairs(qStatus.steps) do
            local badge = L.QUEST_STEP_LOCKED
            local bg = { 0.07, 0.08, 0.10, 0.90 }
            local br = { 0.20, 0.22, 0.26, 0.90 }
            if st.isDone then
                badge = st.isDoneAccountOnly and L.QUEST_STEP_DONE_ACCT or L.QUEST_STEP_DONE
                bg = { 0.06, 0.12, 0.08, 0.92 }
                br = { 0.18, 0.58, 0.30, 0.95 }
            elseif st.isCurrent then
                badge = L.QUEST_STEP_ACTIVE
                if st.inLog then
                    badge = badge .. L.QUEST_STEP_IN_LOG
                elseif st.totalSubCount > 1 and st.doneSubCount > 0 then
                    badge = badge .. string.format(L.QUEST_STEP_SUBPROGRESS, st.doneSubCount, st.totalSubCount)
                end
                bg = { 0.14, 0.12, 0.05, 0.96 }
                br = { 1.0, 0.82, 0.0, 1.0 }
            end

            local zRaw = st.zone or ""
            local coordText = zRaw
            if st.x and st.y and not string.find(zRaw, "[", 1, true) then
                coordText = string.format("|cff00ccff%s [%.1f, %.1f]|r", zRaw, st.x, st.y)
            elseif zRaw ~= "" then
                coordText = "|cff00ccff" .. zRaw .. "|r"
            end

            local fullDesc = st.desc or ""
            if st.luaStepDetail and st.luaStepDetail ~= "" then
                fullDesc = fullDesc .. "\n" .. st.luaStepDetail
            end

            table.insert(stepsToRender, {
                mountID = mountID,
                stepIndex = st.index,
                doneQuest = st.doneQuest,
                badge = badge,
                coords = coordText,
                title = st.title,
                npc = st.npc ~= "" and (L.STEP_NPC_PREFIX .. st.npc .. "|r") or "",
                desc = fullDesc,
                bg = bg,
                br = br,
            })
        end
    elseif dStatus then
        -- 1. Карточка: Как получить, шанс выпадения, КД и событие
        local badge1
        if isCollected then
            badge1 = L.QUEST_STEP_DONE
        elseif dStatus.eventTitle then
            badge1 = string.format(L.REQUIRES_EVENT_FMT, dStatus.eventTitle)
        elseif dStatus.isLockedOnCurrentChar then
            badge1 = L.ALT_STATUS_LOCKED .. "  |cffaaaaaa(" .. dStatus.lockoutTitle .. ")|r"
        else
            badge1 = L.QUEST_STEP_ACTIVE .. "  |cff00ff96(" .. dStatus.lockoutTitle .. ")|r"
        end

        local coordText = "|cff00ccff" .. (dStatus.zoneTitle or "") .. "|r"
        if dStatus.mapID and dStatus.x and dStatus.y then
            coordText = string.format("|cff00ccff%s [%.1f, %.1f]|r", dStatus.zoneTitle or "", dStatus.x, dStatus.y)
        end

        local descLines = {}
        if dStatus.eventTitle then
            table.insert(descLines, string.format(L.REQUIRES_EVENT_FMT, dStatus.eventTitle))
        end
        if dStatus.howToGet and dStatus.howToGet ~= "" then
            table.insert(descLines, dStatus.howToGet)
        end
        if attempts > 0 and dStatus.chance and dStatus.chance > 1 then
            local luck = (1.0 - ((1.0 - (1.0 / dStatus.chance)) ^ attempts)) * 100.0
            table.insert(descLines, string.format(L.TT_ACCOUNT_ATTEMPTS .. " |cffffd100%d|r" .. L.TT_LUCK_INLINE, attempts, luck))
        end
        table.insert(descLines, L.QUEST_STEP_CLICK_HINT)

        table.insert(stepsToRender, {
            mountID = mountID,
            stepIndex = nil,
            customMapID = dStatus.mapID,
            customX = dStatus.x,
            customY = dStatus.y,
            customNpc = dStatus.instanceTitle .. " — " .. dStatus.bossTitle,
            badge = badge1,
            coords = coordText,
            title = string.format("%s — %s (%s)", dStatus.instanceTitle, dStatus.bossTitle, dStatus.difficultyTitle),
            npc = string.format(L.DUNGEON_CHANCE_LOCKOUT_LINE_FMT, dStatus.chance, dStatus.chancePct, dStatus.lockoutTitle),
            desc = table.concat(descLines, "\n"),
            bg = isCollected and { 0.06, 0.12, 0.08, 0.92 } or (dStatus.eventTitle and { 0.15, 0.10, 0.04, 0.96 } or { 0.12, 0.11, 0.06, 0.94 }),
            br = isCollected and { 0.18, 0.58, 0.30, 0.95 } or (dStatus.eventTitle and { 1.0, 0.55, 0.0, 1.0 } or { 0.85, 0.68, 0.15, 1.0 }),
        })

        -- 2. Карточка: Твинки аккаунта (с фильтром по уровню minLevel+ и проверкой КД)
        local altLines = {
            string.format(L.DUNGEON_ALTS_DESC_FMT, dStatus.minLevel, dStatus.minLevel),
        }
        if #dStatus.eligibleChars > 0 then
            for _, ch in ipairs(dStatus.eligibleChars) do
                local stTag = ch.isLocked and L.ALT_STATUS_LOCKED or L.ALT_STATUS_READY
                local charTries = (byChar and byChar[ch.charKey]) or 0
                local triesPart = (charTries > 0) and string.format("  |cffaaaaaa(%s)|r", string.format(L.ROW_ATTEMPTS_FMT, charTries)) or ""
                table.insert(altLines, string.format("• %s — %s%s", ch.coloredName, stTag, triesPart))
            end
        end
        if #dStatus.underleveledChars > 0 then
            local lowNames = {}
            for _, ch in ipairs(dStatus.underleveledChars) do
                table.insert(lowNames, ch.coloredName)
            end
            table.insert(altLines, string.format(L.ALT_UNDERLEVEL_HEADER_FMT, dStatus.minLevel, table.concat(lowNames, ", ")))
        end

        local allLocked = (dStatus.totalEligible > 0 and dStatus.readyCount == 0)
        table.insert(stepsToRender, {
            mountID = mountID,
            stepIndex = nil,
            customMapID = dStatus.mapID,
            customX = dStatus.x,
            customY = dStatus.y,
            customNpc = dStatus.instanceTitle,
            badge = allLocked and L.DUNGEON_ALTS_CARD_BADGE_ALL_LOCKED or L.DUNGEON_ALTS_CARD_BADGE_READY,
            coords = string.format("|cffffd100%d+ lvl|r", dStatus.minLevel),
            title = string.format(L.DUNGEON_ALTS_TITLE_FMT, dStatus.minLevel, dStatus.instanceTitle, dStatus.readyCount, dStatus.totalEligible),
            npc = "",
            desc = table.concat(altLines, "\n"),
            bg = allLocked and { 0.10, 0.06, 0.06, 0.92 } or { 0.07, 0.10, 0.12, 0.95 },
            br = allLocked and { 0.65, 0.25, 0.25, 0.90 } or { 0.25, 0.70, 0.95, 0.95 },
        })
    else
        -- 1. Основная карточка источника дропа / торговца / достижения
        local lockedToday = addon:IsMountRareLockedToday(mountID)
        local badge1 = isCollected and L.QUEST_STEP_DONE or (lockedToday and L.TAG_LOCKED_TODAY or L.QUEST_STEP_ACTIVE)
        local coordText = ""
        if bestCoord and bestCoord.x and bestCoord.y then
            local zName = (bestCoord.m and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(bestCoord.m)) and C_Map.GetMapInfo(bestCoord.m).name or ""
            coordText = string.format("|cff00ccff%s [%.1f, %.1f]|r", zName, bestCoord.x, bestCoord.y)
        end
        local cleanSource = (sourceText and sourceText ~= "") and sourceText:gsub("|n", "\n") or (description or "")
        local bestTargetName = bestCoord and ((bestCoord.npcID and addon.KnownNpcNames and addon.KnownNpcNames[bestCoord.npcID]) or (bestCoord.n and bestCoord.n ~= "" and bestCoord.n)) or nil
        local card1Boss = bestTargetName or (dropInfo and dropInfo.boss)
        table.insert(stepsToRender, {
            mountID = mountID,
            stepIndex = nil,
            badge = badge1,
            coords = coordText,
            title = card1Boss and (L.STEP_DROP_TITLE_PREFIX .. card1Boss) or name,
            npc = bestTargetName and (L.STEP_TARGET_PREFIX .. bestTargetName .. "|r") or "",
            desc = cleanSource,
            bg = isCollected and { 0.06, 0.12, 0.08, 0.92 } or { 0.12, 0.11, 0.06, 0.94 },
            br = isCollected and { 0.18, 0.58, 0.30, 0.95 } or { 0.85, 0.68, 0.15, 1.0 },
        })

        -- 2. Карточка особых условий получения и Lua-статуса (приманки, ковенант, КД рарника, траи)
        local specCond = addon:GetMountSpecialConditions(mountID)
        if specCond and specCond.lines and #specCond.lines > 0 then
            table.insert(stepsToRender, {
                mountID = mountID,
                stepIndex = nil,
                badge = specCond.lockedToday and L.TAG_LOCKED_TODAY or L.QUEST_STEP_ACTIVE,
                coords = "|cffffd100Lua API|r",
                title = L.STEP_SPECIAL_COND_TITLE,
                npc = "",
                desc = table.concat(specCond.lines, "\n"),
                bg = { 0.09, 0.09, 0.13, 0.95 },
                br = { 0.35, 0.65, 0.95, 0.95 },
            })
        end

        -- 3. Отдельные кликабельные карточки только для НЕ убитых сегодня точек спавна рарника / босса
        if dropInfo and dropInfo.coords and #dropInfo.coords > 0 then
            local uniqueSpawns = {}
            for _, c in ipairs(dropInfo.coords) do
                if c.m and c.x and c.x > 0 and c.y and c.y > 0 then
                    local isDup = false
                    for _, u in ipairs(uniqueSpawns) do
                        if u.m == c.m and math.abs(u.x - c.x) < 0.8 and math.abs(u.y - c.y) < 0.8 then
                            if not u.npcID and c.npcID then u.npcID = c.npcID end
                            if (not u.n or u.n == "") and c.n and c.n ~= "" then u.n = c.n end
                            isDup = true
                            break
                        end
                    end
                    if not isDup then
                        table.insert(uniqueSpawns, { m = c.m, x = c.x, y = c.y, n = c.n, npcID = c.npcID })
                    end
                end
            end

            local availSpawns = {}
            for _, c in ipairs(uniqueSpawns) do
                local spLocked = (c.npcID and addon:IsNpcLockedToday(c.npcID)) or lockedToday
                if not spLocked then
                    table.insert(availSpawns, c)
                end
            end

            table.sort(availSpawns, function(a, b)
                return (a.x or 0) < (b.x or 0)
            end)

            for spIdx, c in ipairs(availSpawns) do
                if spIdx <= 30 then
                    local zName = (C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(c.m)) and C_Map.GetMapInfo(c.m).name or ("Map #" .. tostring(c.m))
                    local knownNpc = (c.npcID and addon.KnownNpcNames and addon.KnownNpcNames[c.npcID]) or nil
                    local targetNpc = knownNpc or ((c.n and c.n ~= "") and c.n) or (dropInfo.boss or name)
                    table.insert(stepsToRender, {
                        mountID = mountID,
                        stepIndex = nil,
                        customMapID = c.m,
                        customX = c.x,
                        customY = c.y,
                        customNpc = targetNpc,
                        badge = L.RARE_SPAWN_AVAIL_BADGE,
                        coords = string.format("|cff00ccff%s [%.1f, %.1f]|r", zName, c.x, c.y),
                        title = string.format(L.STEP_SPAWN_POINT_FMT, spIdx, targetNpc),
                        npc = "",
                        desc = L.QUEST_STEP_CLICK_HINT,
                        bg = { 0.07, 0.10, 0.08, 0.94 },
                        br = { 0.22, 0.65, 0.38, 0.95 },
                    })
                end
            end
        end
    end

    local yOffset = 0
    for idx, item in ipairs(stepsToRender) do
        local card = GetOrCreateChecklistCard(pool, panel.scrollContent, idx, cardWidth)
        card.mountID = item.mountID
        card.stepIndex = item.stepIndex
        card.doneQuest = item.doneQuest
        card.customMapID = item.customMapID
        card.customX = item.customX
        card.customY = item.customY
        card.customNpc = item.customNpc
        card.rawTitle = item.title
        card.rawDesc = item.desc
        card.defaultBorder = item.br

        card:SetBackdropColor(unpack(item.bg))
        card:SetBackdropBorderColor(unpack(item.br))

        card.statusFS:SetText(item.badge)
        card.coordsFS:SetText(item.coords)
        card.titleFS:SetText("|cffffffff" .. (item.title or "") .. "|r")
        card.npcFS:SetText(item.npc or "")
        card.descFS:SetText("|cffcccccc" .. (item.desc or "") .. "|r")

        local titleH = math.max(14, card.titleFS:GetStringHeight() or 14)
        local npcH = (item.npc and item.npc ~= "") and math.max(12, card.npcFS:GetStringHeight() or 12) or 0
        local descH = math.max(16, card.descFS:GetStringHeight() or 16)
        local cardH = 26 + titleH + (npcH > 0 and (npcH + 4) or 0) + descH + 16

        card:SetHeight(cardH)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", panel.scrollContent, "TOPLEFT", 0, -yOffset)
        card:Show()

        yOffset = yOffset + cardH + 6
    end

    panel.scrollContent:SetHeight(math.max(1, yOffset))
end

local function CreateMountInspectorWidget(parent, scrollName, cardWidth, isDockedInJournal)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel.isDockedInJournal = isDockedInJournal
    ApplyFlatBackdrop(panel, 0.04, 0.04, 0.05, 0.94, 0.18, 0.18, 0.20, 1.0)

    -- Верхняя шапка выбранного маунта (точь-в-точь как в «Транспорт»)
    local headerBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    headerBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    headerBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    headerBox:SetHeight(114)
    ApplyFlatBackdrop(headerBox, 0.07, 0.07, 0.08, 0.96, 0.22, 0.22, 0.25, 1.0)
    panel.headerBox = headerBox

    local iconFrame = CreateFrame("Frame", nil, headerBox, "BackdropTemplate")
    iconFrame:SetSize(44, 44)
    iconFrame:SetPoint("TOPLEFT", headerBox, "TOPLEFT", 10, -10)
    ApplyFlatBackdrop(iconFrame, 0.0, 0.0, 0.0, 1.0, 0.85, 0.68, 0.15, 1.0)
    panel.iconFrame = iconFrame

    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    panel.iconTex = iconTex

    local nameFS = headerBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameFS:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 10, -2)
    nameFS:SetPoint("RIGHT", headerBox, "RIGHT", -10, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetJustifyV("TOP")
    nameFS:SetWordWrap(true)
    panel.nameFS = nameFS

    local metaFS = headerBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    metaFS:SetPoint("TOPLEFT", iconFrame, "BOTTOMLEFT", 0, -8)
    metaFS:SetPoint("RIGHT", headerBox, "RIGHT", -10, 0)
    metaFS:SetJustifyH("LEFT")
    metaFS:SetJustifyV("TOP")
    if metaFS.SetSpacing then
        metaFS:SetSpacing(4)
    end
    panel.metaFS = metaFS

    -- Кнопка Lua-дебаггера цепочки и условий справа над чек-листом
    local btnDebug = CreateFlatButton(panel, 134, 20, L.QUEST_DEBUG_BTN, false)
    btnDebug:SetPoint("TOPRIGHT", headerBox, "BOTTOMRIGHT", 0, -4)
    btnDebug:SetScript("OnClick", function()
        local mID = isDockedInJournal and (MountJournal and MountJournal.selectedMountID) or ui.selectedMountID
        addon:ShowMountDebugWindow(mID)
    end)
    panel.btnDebug = btnDebug

    -- Кнопка ручной настройки траев (для Всадника без головы и исторических боссов)
    local btnSetAttempts = CreateFlatButton(panel, 102, 20, L.BTN_SET_ATTEMPTS, true)
    btnSetAttempts:SetPoint("RIGHT", btnDebug, "LEFT", -5, 0)
    btnSetAttempts:SetScript("OnClick", function()
        local mID = isDockedInJournal and (MountJournal and MountJournal.selectedMountID) or ui.selectedMountID
        addon:ShowSetAttemptsPopup(mID)
    end)
    panel.btnSetAttempts = btnSetAttempts

    -- Заголовок секции чек-листа
    local secLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    secLabel:SetPoint("TOPLEFT", headerBox, "BOTTOMLEFT", 2, -8)
    secLabel:SetPoint("RIGHT", btnSetAttempts, "LEFT", -6, 0)
    secLabel:SetJustifyH("LEFT")
    secLabel:SetWordWrap(false)
    secLabel:SetTextColor(1.0, 0.82, 0.0, 1.0)
    secLabel:SetText(L.SECTION_CHECKLIST)
    panel.secLabel = secLabel

    -- Скролл со списком шагов (Сделано / Надо сделать)
    local scrollFrame = CreateFrame("ScrollFrame", scrollName, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", headerBox, "BOTTOMLEFT", 0, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 68)
    panel.scrollFrame = scrollFrame

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(cardWidth, 1)
    scrollFrame:SetScrollChild(scrollContent)
    panel.scrollContent = scrollContent

    -- Нижняя панель кнопок действий (2x2)
    local btnBar = CreateFrame("Frame", nil, panel)
    btnBar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    btnBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    btnBar:SetHeight(54)
    panel.btnBar = btnBar

    local halfW = math.floor((cardWidth + 16) / 2) - 3

    local btnNavNow = CreateFlatButton(btnBar, halfW, 24, L.QUEST_NAV_BTN, true)
    btnNavNow:SetPoint("TOPLEFT", btnBar, "TOPLEFT", 0, 0)
    btnNavNow:SetScript("OnClick", function()
        local mID = isDockedInJournal and (MountJournal and MountJournal.selectedMountID) or ui.selectedMountID
        if mID then
            addon:NavigateMountTarget(mID, false)
        end
    end)
    panel.btnNavNow = btnNavNow

    local btnNavStart = CreateFlatButton(btnBar, halfW, 24, L.QUEST_START_BTN, false)
    btnNavStart:SetPoint("TOPRIGHT", btnBar, "TOPRIGHT", 0, 0)
    btnNavStart:SetScript("OnClick", function()
        local mID = isDockedInJournal and (MountJournal and MountJournal.selectedMountID) or ui.selectedMountID
        if mID then
            addon:NavigateMountTarget(mID, true)
        end
    end)
    panel.btnNavStart = btnNavStart

    local btnWowhead = CreateFlatButton(btnBar, halfW, 24, L.QUEST_WOWHEAD_BTN, false)
    btnWowhead:SetPoint("BOTTOMLEFT", btnBar, "BOTTOMLEFT", 0, 0)
    btnWowhead:SetScript("OnClick", function()
        local mID = isDockedInJournal and (MountJournal and MountJournal.selectedMountID) or ui.selectedMountID
        if mID then
            local name = C_MountJournal.GetMountInfoByID(mID)
            local url = addon:GetMountWowheadURL(mID)
            addon:ShowCopyLinkPopup(url, name)
        end
    end)
    panel.btnWowhead = btnWowhead

    local btnFourth = CreateFlatButton(btnBar, halfW, 24, isDockedInJournal and L.QUEST_OPEN_MC_BTN or L.QUEST_JOURNAL_BTN, false)
    btnFourth:SetPoint("BOTTOMRIGHT", btnBar, "BOTTOMRIGHT", 0, 0)
    btnFourth:SetScript("OnClick", function()
        if isDockedInJournal then
            local mID = MountJournal and MountJournal.selectedMountID
            if mID then
                addon:InspectMountInCollector(mID)
            else
                addon:ToggleRadarWindow()
            end
        else
            if ui.selectedMountID then
                addon:OpenMountInJournal(ui.selectedMountID)
            end
        end
    end)
    panel.btnFourth = btnFourth

    return panel
end

-- ============================================================================
-- 4. ГЛАВНОЕ ДВУХКОЛОНОЧНОЕ ОКНО /mc (В СТИЛЕ «ТРАНСПОРТ» ELVUI)
-- Адаптивная мультиязычная вёрстка: кнопки вкладок сами считают ширину по тексту,
-- а окно автоматически масштабируется, если разрешение экрана меньше базового!
-- ============================================================================
local radarFrame = CreateFrame("Frame", "MountCollectorRadarFrame", UIParent, "BackdropTemplate")
radarFrame:SetSize(880, 550)
radarFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
radarFrame:SetFrameStrata("DIALOG")
ApplyFlatBackdrop(radarFrame, 0.05, 0.05, 0.06, 0.96, 0.18, 0.18, 0.20, 1.0)
radarFrame:EnableMouse(true)
radarFrame:SetMovable(true)
radarFrame:RegisterForDrag("LeftButton")
radarFrame:SetScript("OnDragStart", radarFrame.StartMoving)
radarFrame:SetScript("OnDragStop", radarFrame.StopMovingOrSizing)
radarFrame:SetScript("OnShow", function(self)
    local uiW = UIParent and UIParent:GetWidth() or 1920
    local uiH = UIParent and UIParent:GetHeight() or 1080
    local scaleW = (uiW > 0 and uiW < 920) and ((uiW - 24) / 880) or 1.0
    local scaleH = (uiH > 0 and uiH < 600) and ((uiH - 36) / 550) or 1.0
    local targetScale = math.max(0.72, math.min(1.0, scaleW, scaleH))
    self:SetScale(targetScale)
end)
radarFrame:Hide()
ui.radarFrame = radarFrame

-- Верхняя полоса заголовка (как в «Транспорт»)
local topBar = CreateFrame("Frame", nil, radarFrame, "BackdropTemplate")
topBar:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 1, -1)
topBar:SetPoint("TOPRIGHT", radarFrame, "TOPRIGHT", -1, -1)
topBar:SetHeight(28)
ApplyFlatBackdrop(topBar, 0.08, 0.08, 0.09, 0.98, 0.18, 0.18, 0.20, 1.0)

local radarTitle = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
radarTitle:SetPoint("CENTER", topBar, "CENTER", 0, 0)
radarTitle:SetTextColor(1.0, 0.82, 0.0, 1.0)

local radarClose = CreateFlatButton(topBar, 22, 22, "X", false)
radarClose:SetPoint("RIGHT", topBar, "RIGHT", -4, 0)
radarClose:SetScript("OnClick", function() radarFrame:Hide() end)

-- Панель вкладок и счётчика «Всего: X»
-- Порядок вкладок: 1. В текущей зоне -> 2. Ворлдбоссы -> 3. Данж-лут -> 4. Цепочки и Квесты -> 5. Все траи аккаунта | Настройки
local totalBox = CreateFrame("Frame", nil, radarFrame, "BackdropTemplate")
totalBox:SetSize(96, 24)
totalBox:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 12, -36)
ApplyFlatBackdrop(totalBox, 0.03, 0.03, 0.04, 0.95, 0.18, 0.18, 0.20, 1.0)

local totalFS = totalBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
totalFS:SetPoint("CENTER", totalBox, "CENTER", 0, 0)
totalFS:SetTextColor(1.0, 0.82, 0.0, 1.0)

local tabZoneBtn = CreateFlatButton(radarFrame, 120, 24, "", false)
tabZoneBtn:SetPoint("LEFT", totalBox, "RIGHT", 5, 0)

local tabWorldBossBtn = CreateFlatButton(radarFrame, 104, 24, "", false)
tabWorldBossBtn:SetPoint("LEFT", tabZoneBtn, "RIGHT", 5, 0)

local tabDungeonsBtn = CreateFlatButton(radarFrame, 102, 24, "", false)
tabDungeonsBtn:SetPoint("LEFT", tabWorldBossBtn, "RIGHT", 5, 0)

local tabQuestsBtn = CreateFlatButton(radarFrame, 130, 24, "", false)
tabQuestsBtn:SetPoint("LEFT", tabDungeonsBtn, "RIGHT", 5, 0)

local tabAllBtn = CreateFlatButton(radarFrame, 130, 24, "", false)
tabAllBtn:SetPoint("LEFT", tabQuestsBtn, "RIGHT", 5, 0)

local btnSettings = CreateFlatButton(radarFrame, 86, 24, "", false)
btnSettings:SetPoint("TOPRIGHT", radarFrame, "TOPRIGHT", -12, -36)
btnSettings:SetScript("OnClick", function()
    if ui.currentTab == "SETTINGS" then
        ui.currentTab = ui.previousTab or "ZONE"
    else
        ui.previousTab = ui.currentTab
        ui.currentTab = "SETTINGS"
    end
    addon:RefreshRadarUI()
end)

local topTabButtons = { tabZoneBtn, tabWorldBossBtn, tabDungeonsBtn, tabQuestsBtn, tabAllBtn }

-- Динамический расчёт ширины всех кнопок верхней панели для любого языка клиента (без наездов!)
local function LayoutTopTabBar()
    local totalTextW = math.ceil(totalFS:GetStringWidth() or 64)
    local totalBoxW = math.max(84, math.min(126, totalTextW + 18))
    totalBox:SetWidth(totalBoxW)

    local settingsW = btnSettings:AutoSizeWidth(78, 135, 16)
    local availForTabs = (radarFrame:GetWidth() or 880) - 24 - totalBoxW - settingsW - (#topTabButtons * 5) - 10

    local rawTabWidths = {}
    local sumRaw = 0
    for i, btn in ipairs(topTabButtons) do
        local w = math.ceil((btn.label and btn.label:GetStringWidth()) or 80) + 18
        w = math.max(82, w)
        rawTabWidths[i] = w
        sumRaw = sumRaw + w
    end

    local scale = (sumRaw > availForTabs and sumRaw > 0) and (availForTabs / sumRaw) or 1.0
    for i, btn in ipairs(topTabButtons) do
        btn:SetWidth(math.max(72, math.floor(rawTabWidths[i] * scale)))
    end
end

-- ВСТРОЕННАЯ ПАНЕЛЬ НАСТРОЕК ВНУТРИ ГЛАВНОГО ОКНА /mc (БЕЗ ОТДЕЛЬНОГО ПОПАПА)
local settingsPanel = CreateFrame("Frame", nil, radarFrame, "BackdropTemplate")
settingsPanel:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 12, -66)
settingsPanel:SetPoint("BOTTOMRIGHT", radarFrame, "BOTTOMRIGHT", -12, 12)
ApplyFlatBackdrop(settingsPanel, 0.04, 0.04, 0.05, 0.94, 0.18, 0.18, 0.20, 1.0)
settingsPanel:Hide()
ui.settingsPanel = settingsPanel
addon.radarSettingsPanel = settingsPanel

-- ЛЕВАЯ КОЛОНКА (Поиск + Кнопка «Отметить всех на карте» в текущей зоне + Список маунтов)
local leftCol = CreateFrame("Frame", nil, radarFrame, "BackdropTemplate")
leftCol:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 12, -66)
leftCol:SetPoint("BOTTOMLEFT", radarFrame, "BOTTOMLEFT", 12, 12)
leftCol:SetWidth(310)
ApplyFlatBackdrop(leftCol, 0.04, 0.04, 0.05, 0.94, 0.18, 0.18, 0.20, 1.0)

local searchBoxFrame = CreateFrame("Frame", nil, leftCol, "BackdropTemplate")
searchBoxFrame:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 6, -6)
searchBoxFrame:SetPoint("TOPRIGHT", leftCol, "TOPRIGHT", -6, -6)
searchBoxFrame:SetHeight(24)
ApplyFlatBackdrop(searchBoxFrame, 0.02, 0.02, 0.03, 0.98, 0.22, 0.22, 0.26, 1.0)

local searchBox = CreateFrame("EditBox", nil, searchBoxFrame)
searchBox:SetPoint("TOPLEFT", searchBoxFrame, "TOPLEFT", 8, -2)
searchBox:SetPoint("BOTTOMRIGHT", searchBoxFrame, "BOTTOMRIGHT", -24, 2)
searchBox:SetFontObject("ChatFontNormal")
searchBox:SetAutoFocus(false)

local searchPlaceholder = searchBoxFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
searchPlaceholder:SetPoint("LEFT", searchBoxFrame, "LEFT", 8, 0)
searchPlaceholder:SetText(L.SEARCH_PLACEHOLDER)

local clearSearchBtn = CreateFlatButton(searchBoxFrame, 18, 18, "x", false)
clearSearchBtn:SetPoint("RIGHT", searchBoxFrame, "RIGHT", -3, 0)
clearSearchBtn:Hide()
clearSearchBtn:SetScript("OnClick", function()
    searchBox:SetText("")
    searchBox:ClearFocus()
end)

searchBox:SetScript("OnTextChanged", function(self)
    local txt = self:GetText() or ""
    ui.searchText = strtrim(string.lower(txt))
    if txt ~= "" then
        searchPlaceholder:Hide()
        clearSearchBtn:Show()
    else
        searchPlaceholder:Show()
        clearSearchBtn:Hide()
    end
    addon:RefreshRadarUI()
end)
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

-- Кнопка «Отметить всех на карте» (расположена в левой колонке под поиском на вкладке «В текущей зоне», не открывает карту!)
local btnPinZone = CreateFlatButton(leftCol, 298, 22, "", true)
btnPinZone:SetPoint("TOPLEFT", searchBoxFrame, "BOTTOMLEFT", 0, -4)
btnPinZone:SetPoint("TOPRIGHT", searchBoxFrame, "BOTTOMRIGHT", 0, -4)
btnPinZone:SetScript("OnClick", function()
    local zoneMounts = addon:GetZoneUncollectedMounts()
    if zoneMounts and zoneMounts[1] then
        local targetID = ui.selectedMountID or zoneMounts[1].mountID
        addon:PinAllMountSpawns(targetID, false)
    end
end)

local listScroll = CreateFrame("ScrollFrame", "MountCollectorListScroll", leftCol, "UIPanelScrollFrameTemplate")
listScroll:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 6, -62)
listScroll:SetPoint("BOTTOMRIGHT", leftCol, "BOTTOMRIGHT", -26, 6)

local listContent = CreateFrame("Frame", nil, listScroll)
listContent:SetSize(276, 1)
listScroll:SetScrollChild(listContent)

-- ПРАВАЯ КОЛОНКА (Досье выбранного маунта + Чек-лист шагов + Кнопки навигации)
local rightInspector = CreateMountInspectorWidget(radarFrame, "MountCollectorStepScroll", 504, false)
rightInspector:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 8, 0)
rightInspector:SetPoint("BOTTOMRIGHT", radarFrame, "BOTTOMRIGHT", -12, 12)
ui.rightInspector = rightInspector

local function GetOrCreateMountListRow(index)
    if ui.rowPool[index] then return ui.rowPool[index] end

    local row = CreateFrame("Button", nil, listContent, "BackdropTemplate")
    row:SetSize(276, 46)
    row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -((index - 1) * 49))
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ApplyFlatBackdrop(row, 0.08, 0.08, 0.09, 0.92, 0.18, 0.18, 0.20, 1.0)

    local iconBox = CreateFrame("Frame", nil, row, "BackdropTemplate")
    iconBox:SetSize(38, 38)
    iconBox:SetPoint("LEFT", row, "LEFT", 4, 0)
    ApplyFlatBackdrop(iconBox, 0.0, 0.0, 0.0, 1.0, 0.25, 0.25, 0.28, 1.0)
    row.iconBox = iconBox

    row.icon = iconBox:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", iconBox, "TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", iconBox, "BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.title:SetPoint("TOPLEFT", iconBox, "TOPRIGHT", 8, -5)
    row.title:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.sub:SetPoint("BOTTOMLEFT", iconBox, "BOTTOMRIGHT", 8, 5)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
        if self.mountID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local name, _, icon = C_MountJournal.GetMountInfoByID(self.mountID)
            local iconTag = icon and string.format("|T%s:18:18:0:0|t ", icon) or ""
            GameTooltip:SetText(iconTag .. (name or "Mount"), 1, 1, 1)
            addon:AppendMountCollectorLines(GameTooltip, self.mountID, true, false)
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        if self.mountID == ui.selectedMountID then
            self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
        else
            self:SetBackdropBorderColor(0.18, 0.18, 0.20, 1.0)
        end
        GameTooltip:Hide()
    end)

    row:SetScript("OnClick", function(self, button)
        if not self.mountID then return end
        ui.selectedMountID = self.mountID
        if ui.pinnedInspectMountID and ui.pinnedInspectMountID ~= self.mountID then
            ui.pinnedInspectMountID = nil
        end
        addon:RefreshRadarUI()
        if button == "RightButton" then
            addon:NavigateMountTarget(self.mountID, false)
        elseif IsShiftKeyDown() then
            addon:OpenMountInJournal(self.mountID)
        end
    end)

    ui.rowPool[index] = row
    return row
end

function addon:InspectMountInCollector(mountID)
    if not mountID then return end
    ui.selectedMountID = mountID
    ui.pinnedInspectMountID = mountID
    local dStatus = self:GetDungeonMountStatus(mountID)
    if self:GetMountQuestChainStatus(mountID) then
        ui.currentTab = "QUESTS"
    elseif dStatus and dStatus.sourceKind == "WORLD_BOSS" then
        ui.currentTab = "WORLDBOSS"
    elseif dStatus then
        ui.currentTab = "DUNGEONS"
    elseif ui.currentTab == "SETTINGS" then
        ui.currentTab = "ZONE"
    end
    radarFrame:Show()
    self:RefreshRadarUI()
end

function addon:OpenMountQuestChain(mountID)
    if not mountID then return end
    self:InspectMountInCollector(mountID)
    if self:GetMountQuestChainStatus(mountID) then
        self:NavigateMountQuestStep(mountID, nil, false)
    else
        self:NavigateMountTarget(mountID, false)
    end
end

function addon:RefreshRadarUI()
    radarTitle:SetText(L.RADAR_WINDOW_TITLE)
    tabZoneBtn:SetText(L.TAB_CURRENT_ZONE)
    tabWorldBossBtn:SetText(L.TAB_WORLD_BOSSES or "Ворлдбоссы")
    tabDungeonsBtn:SetText(L.TAB_DUNGEON_LOOT)
    tabQuestsBtn:SetText(L.TAB_QUEST_CHAINS)
    tabAllBtn:SetText(L.TAB_ALL_ATTEMPTS)
    btnPinZone:SetText(L.BTN_PIN_ALL_ZONE)
    btnSettings:SetText(L.BTN_SETTINGS)
    searchPlaceholder:SetText(L.SEARCH_PLACEHOLDER)

    if ui.journalDockToggleBtn then
        ui.journalDockToggleBtn:SetText(L.DOCK_TOGGLE_BTN)
        if ui.journalDockToggleBtn.AutoSizeWidth then
            ui.journalDockToggleBtn:AutoSizeWidth(135, 220, 18)
        end
    end
    if ui.journalDockTitle then
        ui.journalDockTitle:SetText(L.DOCK_WINDOW_TITLE)
    end

    tabZoneBtn:SetActiveTab(ui.currentTab == "ZONE")
    tabWorldBossBtn:SetActiveTab(ui.currentTab == "WORLDBOSS")
    tabDungeonsBtn:SetActiveTab(ui.currentTab == "DUNGEONS")
    tabQuestsBtn:SetActiveTab(ui.currentTab == "QUESTS")
    tabAllBtn:SetActiveTab(ui.currentTab == "ALL")
    btnSettings:SetActiveTab(ui.currentTab == "SETTINGS")

    if ui.currentTab == "ZONE" then
        btnPinZone:Show()
        listScroll:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 6, -62)
    else
        btnPinZone:Hide()
        listScroll:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 6, -36)
    end

    if not radarFrame:IsShown() then
        LayoutTopTabBar()
        return
    end

    if ui.currentTab == "SETTINGS" then
        totalFS:SetText(string.format(L.TOTAL_LABEL, ui.lastListCount or #(self.MountQuestsDB or {})))
        LayoutTopTabBar()
        leftCol:Hide()
        rightInspector:Hide()
        settingsPanel:Show()
        if settingsPanel.controls and settingsPanel.controls.Refresh then
            settingsPanel.controls:Refresh()
        end
        return
    else
        settingsPanel:Hide()
        leftCol:Show()
        rightInspector:Show()
    end

    for _, row in ipairs(ui.rowPool) do
        row:Hide()
    end

    local listEntries = {}
    local currentPlayerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local currentParentMapID = nil
    if currentPlayerMapID and C_Map and C_Map.GetMapInfo then
        local mInfo = C_Map.GetMapInfo(currentPlayerMapID)
        currentParentMapID = mInfo and mInfo.parentMapID or nil
    end

    if ui.currentTab == "QUESTS" then
        local _, playerClass = UnitClass("player")
        if type(self.MountQuestsDB) == "table" then
            for dbIdx, qChain in ipairs(self.MountQuestsDB) do
                local mID = qChain.resolvedMountID or (qChain.spellID and self.MountBySpell[qChain.spellID]) or qChain.mountID
                local st = mID and self:GetMountQuestChainStatus(mID)
                local isOtherClass = (st and st.classRestriction and st.classRestriction ~= playerClass) and true or false
                if st and (not isOtherClass or ui.pinnedInspectMountID == mID) and (not st.isCollected or ui.pinnedInspectMountID == mID) then
                    st.isPlayerClass = (st.classRestriction and st.classRestriction == playerClass) and true or false
                    if ui.searchText == "" or string.find(string.lower(st.name), ui.searchText, 1, true) or string.find(string.lower(st.category), ui.searchText, 1, true) then
                        local badge
                        if st.isCollected then
                            badge = L.TAG_COLLECTED
                        elseif st.hasStarted then
                            badge = string.format(L.QUEST_CHAIN_STATUS_IN_PROGRESS, st.completedSteps, st.totalSteps)
                        else
                            badge = string.format(L.QUEST_CHAIN_STATUS_AVAILABLE, st.totalSteps)
                        end
                        table.insert(listEntries, {
                            mountID = st.mountID,
                            name = st.name,
                            icon = st.icon,
                            isCollected = st.isCollected,
                            isPlayerClass = st.isPlayerClass,
                            hasStarted = st.hasStarted,
                            completedSteps = st.completedSteps,
                            dbOrder = dbIdx,
                            subLine = string.format("%s |cff888888• %s|r", badge, st.category),
                        })
                    end
                end
            end
        end

        table.sort(listEntries, function(a, b)
            if a.isCollected ~= b.isCollected then
                return not a.isCollected
            end
            if a.isPlayerClass ~= b.isPlayerClass then
                return a.isPlayerClass
            end
            if a.hasStarted ~= b.hasStarted then
                return a.hasStarted
            end
            if (a.completedSteps or 0) ~= (b.completedSteps or 0) then
                return (a.completedSteps or 0) > (b.completedSteps or 0)
            end
            return (a.dbOrder or 0) < (b.dbOrder or 0)
        end)
    elseif ui.currentTab == "WORLDBOSS" or ui.currentTab == "DUNGEONS" then
        local wantWorldBoss = (ui.currentTab == "WORLDBOSS")
        if type(self.MountDungeonsDB) == "table" then
            for dbIdx, dEntry in ipairs(self.MountDungeonsDB) do
                local includeEntry = wantWorldBoss and (dEntry.sourceKind == "WORLD_BOSS" or dEntry.isWorldBoss == true) or (not wantWorldBoss and dEntry.sourceKind ~= "WORLD_BOSS")
                if includeEntry then
                    local mID = dEntry.resolvedMountID or (dEntry.spellID and self.MountBySpell[dEntry.spellID]) or dEntry.mountID
                    local st = mID and self:GetDungeonMountStatus(mID)
                    if st and (not st.isCollected or ui.pinnedInspectMountID == mID) then
                        local sTxt = ui.searchText or ""
                        local matchSearch = (sTxt == "")
                            or string.find(string.lower(st.name or ""), sTxt, 1, true)
                            or string.find(string.lower(st.instanceTitle or ""), sTxt, 1, true)
                            or string.find(string.lower(st.bossTitle or ""), sTxt, 1, true)
                            or string.find(string.lower(st.zoneTitle or ""), sTxt, 1, true)
                            or (st.eventTitle and string.find(string.lower(st.eventTitle), sTxt, 1, true))
                        if matchSearch then
                            local attempts = self:GetMountAttempts(mID)
                            local isInCurrentZone = (st.mapID and (st.mapID == currentPlayerMapID or st.mapID == currentParentMapID)) and true or false
                            local zoneBadge = (wantWorldBoss and isInCurrentZone) and ("|cff00ccff[" .. L.TAB_CURRENT_ZONE .. "]|r ") or ""
                            local subLine
                            if st.isCollected then
                                subLine = zoneBadge .. string.format("%s |cff888888• %s|r", L.TAG_COLLECTED, st.eventTitle or st.instanceTitle)
                            elseif st.eventTitle then
                                local altsPart = (st.totalEligible > 0) and string.format(L.ROW_ALTS_READY_FMT, st.readyCount, st.totalEligible) or ""
                                subLine = zoneBadge .. string.format(L.ROW_REQUIRES_EVENT_FMT, st.eventTitle) .. string.format(" |cff888888• 1/%d|r", st.chance) .. altsPart
                            elseif wantWorldBoss then
                                local altsPart = (st.totalEligible > 0) and string.format(L.ROW_ALTS_READY_FMT, st.readyCount, st.totalEligible) or ""
                                subLine = zoneBadge .. string.format(L.ROW_ATTEMPTS_FMT, attempts or 0) .. string.format(" |cff888888• 1/%d • %s|r", st.chance, st.bossTitle or st.zoneTitle) .. altsPart
                            else
                                local altsPart = (st.totalEligible > 0) and string.format(L.ROW_ALTS_READY_FMT, st.readyCount, st.totalEligible) or ""
                                subLine = string.format(L.ROW_ATTEMPTS_FMT, attempts or 0) .. string.format(" |cff888888• 1/%d • %s|r", st.chance, st.instanceTitle) .. altsPart
                            end
                            table.insert(listEntries, {
                                mountID = st.mountID,
                                name = st.name,
                                icon = st.icon,
                                attempts = attempts,
                                isCollected = st.isCollected,
                                isInCurrentZone = isInCurrentZone,
                                isLockedOnCurrentChar = st.isLockedOnCurrentChar and true or false,
                                dbOrder = dbIdx,
                                subLine = subLine,
                            })
                        end
                    end
                end
            end
        end

        table.sort(listEntries, function(a, b)
            if a.isCollected ~= b.isCollected then
                return not a.isCollected
            end
            if a.isInCurrentZone ~= b.isInCurrentZone then
                return a.isInCurrentZone
            end
            if a.isLockedOnCurrentChar ~= b.isLockedOnCurrentChar then
                return not a.isLockedOnCurrentChar
            end
            return (a.dbOrder or 0) < (b.dbOrder or 0)
        end)
    elseif ui.currentTab == "ZONE" then
        local zoneMounts = self:GetZoneUncollectedMounts()
        for _, m in ipairs(zoneMounts) do
            if ui.searchText == "" or string.find(string.lower(m.name), ui.searchText, 1, true) then
                local chPart = (m.chance and m.chance > 0) and string.format(" • 1/%d", m.chance) or ""
                local lockPart = ""
                if m.isWorldBoss then
                    local wbTag = " |cff00ccff[" .. (L.TAB_WORLD_BOSSES or "WB") .. "]|r"
                    local altsPart = (m.totalEligible and m.totalEligible > 0) and string.format(L.ROW_ALTS_READY_FMT, m.readyCount or 0, m.totalEligible) or ""
                    lockPart = wbTag .. (m.locked and L.TAG_LOCKED_SHORT or altsPart)
                elseif m.locked then
                    lockPart = L.TAG_LOCKED_SHORT
                elseif m.totalLockoutCount and m.totalLockoutCount > 1 then
                    lockPart = string.format(L.ROW_RARES_LOCKOUT_FMT, m.lockedCount or 0, m.totalLockoutCount)
                end
                table.insert(listEntries, {
                    mountID = m.mountID,
                    name = m.name,
                    icon = m.icon,
                    isCollected = false,
                    subLine = string.format(L.ROW_ATTEMPTS_FMT, m.attempts or 0) .. "|cff888888" .. chPart .. "|r" .. lockPart,
                })
            end
        end
    else
        for mountID, info in pairs(self.DropInfoByMount) do
            local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if name and not isCollected then
                local attempts = self:GetMountAttempts(mountID)
                if attempts > 0 and (ui.searchText == "" or string.find(string.lower(name), ui.searchText, 1, true)) then
                    local chPart = (info.chance and info.chance > 0) and string.format(" • 1/%d", info.chance) or ""
                    table.insert(listEntries, {
                        mountID = mountID,
                        name = name,
                        icon = icon,
                        attempts = attempts,
                        isCollected = false,
                        subLine = string.format(L.ROW_ATTEMPTS_FMT, attempts) .. "|cff888888" .. chPart .. "|r",
                    })
                end
            end
        end
        table.sort(listEntries, function(a, b)
            return (a.attempts or 0) > (b.attempts or 0)
        end)
    end

    local foundSelected = false
    for _, item in ipairs(listEntries) do
        if item.mountID == ui.selectedMountID then
            foundSelected = true
            break
        end
    end
    if not foundSelected and ui.selectedMountID and ui.selectedMountID == ui.pinnedInspectMountID then
        local pName, _, pIcon, _, _, _, _, _, _, _, pCollected = C_MountJournal.GetMountInfoByID(ui.selectedMountID)
        if pName then
            local pAttempts, _, pDrop = self:GetMountAttempts(ui.selectedMountID)
            local chPart = (pDrop and pDrop.chance and pDrop.chance > 0) and string.format(" • 1/%d", pDrop.chance) or ""
            table.insert(listEntries, 1, {
                mountID = ui.selectedMountID,
                name = pName,
                icon = pIcon,
                attempts = pAttempts,
                isCollected = pCollected,
                subLine = string.format(L.ROW_ATTEMPTS_FMT, pAttempts or 0) .. "|cff888888" .. chPart .. "|r",
            })
            foundSelected = true
        end
    end
    if not foundSelected then
        ui.selectedMountID = listEntries[1] and listEntries[1].mountID or nil
    end

    ui.lastListCount = #listEntries
    totalFS:SetText(string.format(L.TOTAL_LABEL, #listEntries))
    LayoutTopTabBar()

    for idx, entry in ipairs(listEntries) do
        local row = GetOrCreateMountListRow(idx)
        row.mountID = entry.mountID
        row.icon:SetTexture(entry.icon or "Interface\\ICONS\\Ability_Mount_SpectralTiger")

        if entry.isCollected then
            row.title:SetText("|cff00ff96" .. entry.name .. "|r")
        else
            row.title:SetText("|cffff6666" .. entry.name .. "|r")
        end
        row.sub:SetText(entry.subLine or "")

        if entry.mountID == ui.selectedMountID then
            row:SetBackdropColor(0.16, 0.14, 0.06, 0.96)
            row:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
        else
            row:SetBackdropColor(0.08, 0.08, 0.09, 0.92)
            row:SetBackdropBorderColor(0.18, 0.18, 0.20, 1.0)
        end
        row:Show()
    end

    listContent:SetHeight(math.max(1, #listEntries * 49))
    PopulateMountInspectorPanel(rightInspector, ui.selectedMountID, ui.stepRowPool, 504)
end

function addon:ToggleRadarWindow()
    if radarFrame:IsShown() then
        radarFrame:Hide()
    else
        if ui.currentTab == "SETTINGS" then
            ui.currentTab = ui.previousTab or "ZONE"
        end
        radarFrame:Show()
        self:RefreshRadarUI()
    end
end

function addon:ToggleConfigFrame()
    if radarFrame:IsShown() and ui.currentTab == "SETTINGS" then
        radarFrame:Hide()
    else
        if ui.currentTab ~= "SETTINGS" then
            ui.previousTab = ui.currentTab
        end
        ui.currentTab = "SETTINGS"
        radarFrame:Show()
        self:RefreshRadarUI()
    end
end

tabZoneBtn:SetScript("OnClick", function()
    ui.currentTab = "ZONE"
    addon:RefreshRadarUI()
end)

tabWorldBossBtn:SetScript("OnClick", function()
    ui.currentTab = "WORLDBOSS"
    addon:RefreshRadarUI()
end)

tabDungeonsBtn:SetScript("OnClick", function()
    ui.currentTab = "DUNGEONS"
    addon:RefreshRadarUI()
end)

tabQuestsBtn:SetScript("OnClick", function()
    ui.currentTab = "QUESTS"
    addon:RefreshRadarUI()
end)

tabAllBtn:SetScript("OnClick", function()
    ui.currentTab = "ALL"
    addon:RefreshRadarUI()
end)

-- ============================================================================
-- 5. БОКОВАЯ ДОК-КОЛОНКА СПРАВА ОТ ОКНА «ТРАНСПОРТ» (CollectionsJournal)
-- ============================================================================
function addon:InitMountJournalSideColumn()
    if ui.journalDockFrame or not _G.CollectionsJournal or not _G.MountJournal then return end

    local toggleBtn = CreateFlatButton(MountJournal, 150, 22, L.DOCK_TOGGLE_BTN, true)
    toggleBtn:SetPoint("TOPRIGHT", MountJournal, "TOPRIGHT", -36, -4)
    toggleBtn:SetFrameLevel((MountJournal:GetFrameLevel() or 10) + 10)
    ui.journalDockToggleBtn = toggleBtn

    local dock = CreateFrame("Frame", "MountCollectorJournalDock", MountJournal, "BackdropTemplate")
    dock:SetWidth(390)
    dock:SetPoint("TOPLEFT", CollectionsJournal, "TOPRIGHT", 3, 0)
    dock:SetPoint("BOTTOMLEFT", CollectionsJournal, "BOTTOMRIGHT", 3, 0)
    dock:SetFrameStrata("HIGH")
    ApplyFlatBackdrop(dock, 0.05, 0.05, 0.06, 0.96, 0.18, 0.18, 0.20, 1.0)
    ui.journalDockFrame = dock

    local dockTopBar = CreateFrame("Frame", nil, dock, "BackdropTemplate")
    dockTopBar:SetPoint("TOPLEFT", dock, "TOPLEFT", 1, -1)
    dockTopBar:SetPoint("TOPRIGHT", dock, "TOPRIGHT", -1, -1)
    dockTopBar:SetHeight(28)
    ApplyFlatBackdrop(dockTopBar, 0.08, 0.08, 0.09, 0.98, 0.18, 0.18, 0.20, 1.0)

    local dockTitle = dockTopBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dockTitle:SetPoint("CENTER", dockTopBar, "CENTER", 0, 0)
    dockTitle:SetTextColor(1.0, 0.82, 0.0, 1.0)
    dockTitle:SetText(L.DOCK_WINDOW_TITLE)
    ui.journalDockTitle = dockTitle

    local dockClose = CreateFlatButton(dockTopBar, 22, 22, "X", false)
    dockClose:SetPoint("RIGHT", dockTopBar, "RIGHT", -4, 0)
    dockClose:SetScript("OnClick", function()
        ui.dockHiddenByUser = true
        dock:Hide()
    end)

    local dockInspector = CreateMountInspectorWidget(dock, "MountCollectorDockStepScroll", 336, true)
    dockInspector:SetPoint("TOPLEFT", dock, "TOPLEFT", 8, -34)
    dockInspector:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", -8, 8)
    ui.dockInspector = dockInspector

    toggleBtn:SetScript("OnClick", function()
        if dock:IsShown() then
            ui.dockHiddenByUser = true
            dock:Hide()
        else
            ui.dockHiddenByUser = false
            dock:Show()
            addon:RefreshMountJournalSideColumn()
        end
    end)

    MountJournal:HookScript("OnShow", function()
        if not ui.dockHiddenByUser then
            dock:Show()
            addon:RefreshMountJournalSideColumn()
        end
    end)
end

function addon:RefreshMountJournalSideColumn()
    if not ui.journalDockFrame or not ui.journalDockFrame:IsShown() then return end
    if not _G.MountJournal or not MountJournal:IsShown() then return end
    local mountID = MountJournal.selectedMountID
    PopulateMountInspectorPanel(ui.dockInspector, mountID, ui.dockStepPool, 336)
end


SLASH_MOUNTCOLLECTOR1 = "/mc"
SLASH_MOUNTCOLLECTOR2 = "/mountcollector"
SlashCmdList["MOUNTCOLLECTOR"] = function(msg)
    local cmd = strtrim(string.lower(msg or ""))
    if cmd == "config" or cmd == "settings" or cmd == "opt" or cmd == "options" then
        if addon.ToggleConfigFrame then
            addon:ToggleConfigFrame()
        end
    elseif cmd == "check" or cmd == "validate" then
        if addon.ValidateModuleIntegrity then
            addon:ValidateModuleIntegrity(false)
        end
    elseif string.find(cmd, "^debug") or string.find(cmd, "^dbg") then
        local argID = tonumber(string.match(cmd, "(%d+)"))
        addon:ShowMountDebugWindow(argID)
    elseif string.find(cmd, "^set") then
        local count = tonumber(string.match(cmd, "(%d+)"))
        local mID = ui.selectedMountID or (MountJournal and MountJournal.selectedMountID)
        if mID and count then
            addon:SetManualMountAttempts(mID, count, false)
        else
            addon:ShowSetAttemptsPopup(mID)
        end
    else
        addon:ToggleRadarWindow()
    end
end
