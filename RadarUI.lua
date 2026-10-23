local _, addon = ...

-- ============================================================================
-- MountCollector — RadarUI.lua
-- Графический интерфейс аддона (тёмный плоский ElvUI / «Транспорт» стиль):
--   1. Базовые UI-примитивы (ApplyFlatBackdrop, CreateFlatButton, CopyLinkPopup)
--   2. Всплывающий радар-баннер при обнаружении рарника / босса с маунтом
--   3. Интерактивные иконки рарников на Карте Мира (WorldMapFrame)
--   4. Универсальный инспектор маунта (досье, чек-лист шагов, кнопки TomTom/Wowhead)
--   5. Главное двухколоночное окно /mc со встроенной вкладкой «Настройки»
--   6. Боковая док-колонка справа от стандартного окна «Транспорт» (MountJournal)
--   7. LibDataBroker-1.1 и иконка у миникарты (LibDBIcon-1.0)
-- ============================================================================

local L = addon.L
local LibStub = _G.LibStub
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local ui = {
    currentTab = "QUESTS",
    previousTab = "QUESTS",
    selectedMountID = nil,
    searchText = "",
    rowPool = {},
    stepRowPool = {},
    dockStepPool = {},
    mapPinPool = {},
    worldMapHooked = false,
    dockHiddenByUser = false,
}

-- ============================================================================
-- БАЗОВЫЕ ХЕЛПЕРЫ СТИЛЯ (ТЁМНЫЙ ПЛОСКИЙ ELVUI / COLLECTIONS JOURNAL ДИЗАЙН)
-- ============================================================================
local function ApplyFlatBackdrop(frame, bgR, bgG, bgB, bgA, brR, brG, brB, brA)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(bgR or 0.06, bgG or 0.06, bgB or 0.07, bgA or 0.96)
    frame:SetBackdropBorderColor(brR or 0.20, brG or 0.20, brB or 0.22, brA or 1.0)
end

local function CreateFlatButton(parent, width, height, text, isGoldAccent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    if isGoldAccent then
        ApplyFlatBackdrop(btn, 0.16, 0.13, 0.05, 0.96, 0.85, 0.68, 0.15, 1.0)
        btn.defaultBg = { 0.16, 0.13, 0.05, 0.96 }
        btn.defaultBorder = { 0.85, 0.68, 0.15, 1.0 }
    else
        ApplyFlatBackdrop(btn, 0.10, 0.10, 0.12, 0.96, 0.24, 0.24, 0.28, 1.0)
        btn.defaultBg = { 0.10, 0.10, 0.12, 0.96 }
        btn.defaultBorder = { 0.24, 0.24, 0.28, 1.0 }
    end

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.label:SetJustifyH("CENTER")
    btn.label:SetWordWrap(false)
    btn.label:SetText(text or "")
    if isGoldAccent then
        btn.label:SetTextColor(1.0, 0.85, 0.2, 1.0)
    else
        btn.label:SetTextColor(0.92, 0.92, 0.95, 1.0)
    end

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.18, 0.10, 0.98)
        self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
        self.label:SetTextColor(1.0, 0.90, 0.35, 1.0)
    end)
    btn:SetScript("OnLeave", function(self)
        if self.isActiveTab then
            self:SetBackdropColor(0.18, 0.15, 0.06, 0.98)
            self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
            self.label:SetTextColor(1.0, 0.86, 0.20, 1.0)
        else
            self:SetBackdropColor(unpack(self.defaultBg))
            self:SetBackdropBorderColor(unpack(self.defaultBorder))
            if isGoldAccent then
                self.label:SetTextColor(1.0, 0.85, 0.2, 1.0)
            else
                self.label:SetTextColor(0.92, 0.92, 0.95, 1.0)
            end
        end
    end)

    function btn:SetText(str)
        self.label:SetText(str or "")
    end

    function btn:SetActiveTab(active)
        self.isActiveTab = active
        if active then
            self:SetBackdropColor(0.18, 0.15, 0.06, 0.98)
            self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
            self.label:SetTextColor(1.0, 0.86, 0.20, 1.0)
        else
            self:SetBackdropColor(unpack(self.defaultBg))
            self:SetBackdropBorderColor(unpack(self.defaultBorder))
            self.label:SetTextColor(0.88, 0.88, 0.92, 1.0)
        end
    end

    return btn
end

addon.ApplyFlatBackdrop = ApplyFlatBackdrop
addon.CreateFlatButton = CreateFlatButton

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

-- Универсальная навигация для любого маунта (квестового или дропового)
function addon:NavigateMountTarget(mountID, forceFirstStep)
    if not mountID then return end
    local qStatus = self:GetMountQuestChainStatus(mountID)
    if qStatus then
        local stepIdx = forceFirstStep and 1 or qStatus.currentStepIndex or 1
        self:NavigateMountQuestStep(mountID, stepIdx, false)
        return
    end
    local info = self.DropInfoByMount and self.DropInfoByMount[mountID]
    local c = self:GetBestMountCoords(mountID)
    if c then
        self:SetMountWaypoint(mountID, c.m, c.x, c.y, c.n or (info and info.boss), false)
    else
        self:SetMountWaypoint(mountID, nil, nil, nil, info and info.boss, false)
    end
end

-- ============================================================================
-- 1. ВСПЛЫВАЮЩИЙ РАДАР-БАННЕР ПРИ ОБНАРУЖЕНИИ РАРНИКА / БОССА
-- ============================================================================
local alertFrame = CreateFrame("Button", "MountCollectorAlertFrame", UIParent, "BackdropTemplate")
alertFrame:SetSize(390, 72)
alertFrame:SetPoint("TOP", UIParent, "TOP", 0, -140)
alertFrame:SetFrameStrata("HIGH")
ApplyFlatBackdrop(alertFrame, 0.05, 0.05, 0.07, 0.96, 1.0, 0.82, 0.0, 1.0)
alertFrame:EnableMouse(true)
alertFrame:SetMovable(true)
alertFrame:RegisterForDrag("LeftButton")
alertFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
alertFrame:SetScript("OnDragStart", alertFrame.StartMoving)
alertFrame:SetScript("OnDragStop", alertFrame.StopMovingOrSizing)
alertFrame:Hide()

local alertIcon = alertFrame:CreateTexture(nil, "ARTWORK")
alertIcon:SetSize(50, 50)
alertIcon:SetPoint("LEFT", alertFrame, "LEFT", 10, 0)
alertIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local alertHeader = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
alertHeader:SetPoint("TOPLEFT", alertIcon, "TOPRIGHT", 10, -2)
alertHeader:SetPoint("RIGHT", alertFrame, "RIGHT", -24, 0)
alertHeader:SetJustifyH("LEFT")

local alertMountName = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
alertMountName:SetPoint("TOPLEFT", alertHeader, "BOTTOMLEFT", 0, -3)
alertMountName:SetPoint("RIGHT", alertFrame, "RIGHT", -10, 0)
alertMountName:SetJustifyH("LEFT")

local alertStats = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
alertStats:SetPoint("TOPLEFT", alertMountName, "BOTTOMLEFT", 0, -3)
alertStats:SetPoint("RIGHT", alertFrame, "RIGHT", -10, 0)
alertStats:SetJustifyH("LEFT")

local closeAlertBtn = CreateFlatButton(alertFrame, 20, 20, "X", false)
closeAlertBtn:SetPoint("TOPRIGHT", alertFrame, "TOPRIGHT", -4, -4)
closeAlertBtn:SetScript("OnClick", function() alertFrame:Hide() end)

alertFrame:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
        self:Hide()
    elseif self.currentMountID then
        addon:SetMountWaypoint(self.currentMountID, self.alertMapID, self.alertX, self.alertY, self.alertNpcName, false)
        addon:OpenMountInJournal(self.currentMountID)
    end
end)

function addon:TriggerRareMountAlert(mountID, npcID, npcName, forceShow, mapID, liveX, liveY)
    if not forceShow and (not self.db or not self.db.settings.alertRares) then return end
    local key = tostring(npcID or 0) .. ":" .. tostring(mountID or 0)
    local now = GetTime()
    if not forceShow and self.RecentAlertLock[key] and (now - self.RecentAlertLock[key]) < 120 then
        return
    end
    self.RecentAlertLock[key] = now

    local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    if not name or (isCollected and not forceShow) then return end

    local attempts, _, dropInfo = self:GetMountAttempts(mountID)
    local globalPct = self:GetGlobalRarity(mountID)
    local pctText = self:FormatRarityTier(globalPct)
    local chanceStr = (dropInfo and dropInfo.chance) and string.format("1/%d | ", dropInfo.chance) or ""

    alertFrame.currentMountID = mountID
    alertFrame.alertMapID = mapID
    alertFrame.alertX = liveX
    alertFrame.alertY = liveY
    alertFrame.alertNpcName = npcName

    alertIcon:SetTexture(icon or "Interface\\ICONS\\Ability_Mount_SpectralTiger")
    alertHeader:SetText(string.format(L.ALERT_HEADER_NEARBY, npcName or "Rare NPC"))
    alertMountName:SetText(string.format(L.ALERT_NOT_COLLECTED, name))
    alertStats:SetText(string.format(L.ALERT_STATS_LINE, attempts, chanceStr, pctText))

    alertFrame:Show()
    if self.db and self.db.settings.alertSound and PlaySound then
        PlaySound(8959, "Master")
    end

    if self.db and self.db.settings.autoWaypoint then
        self:SetMountWaypoint(mountID, mapID, liveX, liveY, npcName, false)
    end

    if self.alertHideTimer then
        self.alertHideTimer:Cancel()
    end
    self.alertHideTimer = C_Timer.NewTimer(15, function()
        if alertFrame:IsShown() then
            alertFrame:Hide()
        end
    end)
end

-- ============================================================================
-- 2. ИКОНКИ РАРНИКОВ И БОССОВ НА КАРТЕ МИРА (WORLD MAP PINS)
-- ============================================================================
local function GetOrCreateMapPin(parent, index)
    if ui.mapPinPool[index] then
        ui.mapPinPool[index]:SetParent(parent)
        return ui.mapPinPool[index]
    end

    local pin = CreateFrame("Button", nil, parent, "BackdropTemplate")
    pin:SetSize(24, 24)
    pin:SetFrameStrata("HIGH")
    pin:SetFrameLevel(2500)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ApplyFlatBackdrop(pin, 0.05, 0.05, 0.08, 0.95, 1.0, 0.78, 0.0, 1.0)

    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 2, -2)
    pin.icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -2, 2)
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    pin:SetScript("OnEnter", function(self)
        if not self.mountID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local mName, _, mIcon = C_MountJournal.GetMountInfoByID(self.mountID)
        local iconTag = mIcon and string.format("|T%s:18:18:0:0|t ", mIcon) or ""
        local npcLine = self.npcName and ("|cffffd100" .. self.npcName .. "|r — ") or ""
        GameTooltip:SetText(npcLine .. iconTag .. (mName or "Mount"), 1, 1, 1)
        addon:AppendMountCollectorLines(GameTooltip, self.mountID, true, false)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.MAP_PIN_HINT)
        GameTooltip:Show()
    end)

    pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    pin:SetScript("OnClick", function(self, button)
        if not self.mountID then return end
        if button == "RightButton" then
            addon:OpenMountInJournal(self.mountID)
        else
            addon:SetMountWaypoint(self.mountID, self.mapID, self.coordX, self.coordY, self.npcName, false)
        end
    end)

    ui.mapPinPool[index] = pin
    return pin
end

function addon:RefreshWorldMapPins()
    for _, pin in ipairs(ui.mapPinPool) do
        pin:Hide()
    end

    if not self.db or not self.db.settings or not self.db.settings.showWorldMapPins then return end
    if not _G.WorldMapFrame or not WorldMapFrame:IsShown() then return end

    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end

    local canvas = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
    if not canvas then return end

    local list = self.MountsByMap[mapID]
    if not list or #list == 0 then return end

    local cw = canvas:GetWidth()
    local ch = canvas:GetHeight()
    if not cw or not ch or cw <= 0 or ch <= 0 then return end

    local pinIdx = 0
    for _, mountID in ipairs(list) do
        local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if name and not isCollected then
            local info = self.DropInfoByMount[mountID]
            local locked = self:IsMountRareLockedToday(mountID)
            if info and info.coords then
                for _, c in ipairs(info.coords) do
                    if c.m == mapID and c.x and c.x > 0 and c.y and c.y > 0 then
                        pinIdx = pinIdx + 1
                        local pin = GetOrCreateMapPin(canvas, pinIdx)
                        pin.mountID = mountID
                        pin.mapID = mapID
                        pin.coordX = c.x
                        pin.coordY = c.y
                        pin.npcName = (c.n and c.n ~= "") and c.n or info.boss or name
                        pin.icon:SetTexture(icon or "Interface\\ICONS\\Ability_Mount_SpectralTiger")

                        if locked then
                            pin.icon:SetDesaturated(true)
                            pin:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
                            pin:SetAlpha(0.6)
                        else
                            pin.icon:SetDesaturated(false)
                            pin:SetBackdropBorderColor(1.0, 0.78, 0.0, 1.0)
                            pin:SetAlpha(1.0)
                        end

                        local px = (c.x / 100.0) * cw
                        local py = -(c.y / 100.0) * ch
                        pin:ClearAllPoints()
                        pin:SetPoint("CENTER", canvas, "TOPLEFT", px, py)
                        pin:Show()
                    end
                end
            end
        end
    end
end

function addon:InitWorldMapPins()
    if ui.worldMapHooked or not _G.WorldMapFrame then return end
    ui.worldMapHooked = true

    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
        addon:RefreshWorldMapPins()
    end)
    WorldMapFrame:HookScript("OnShow", function()
        addon:RefreshWorldMapPins()
    end)
    if WorldMapFrame.ScrollContainer then
        WorldMapFrame.ScrollContainer:HookScript("OnSizeChanged", function()
            addon:RefreshWorldMapPins()
        end)
    end
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

    card.statusFS = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.statusFS:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
    card.statusFS:SetJustifyH("LEFT")
    card.statusFS:SetWordWrap(false)

    card.coordsFS = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.coordsFS:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -8)
    card.coordsFS:SetJustifyH("RIGHT")
    card.coordsFS:SetWordWrap(false)

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
    if panel.btnNavNow then
        panel.btnNavNow:SetText(L.QUEST_NAV_BTN)
    end
    if panel.btnNavStart then
        panel.btnNavStart:SetText(L.QUEST_START_BTN)
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
        return
    end

    local name, spellID, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    if not name then return end

    local _, description, sourceText = C_MountJournal.GetMountInfoExtraByID(mountID)
    local realm, _, estOwners, seenCount, globalPct = addon:GetServerRarityInfo(mountID)
    local pctText, tierText = addon:FormatRarityTier(globalPct)
    local attempts, byChar, dropInfo = addon:GetMountAttempts(mountID)
    local qStatus = addon:GetMountQuestChainStatus(mountID)
    local bestCoord = addon:GetBestMountCoords(mountID)

    panel.iconFrame:Show()
    panel.iconTex:SetTexture(icon or "Interface\\ICONS\\Ability_Mount_SpectralTiger")

    local colTag = isCollected and L.TAG_COLLECTED or L.TAG_NOT_COLLECTED
    panel.nameFS:SetText(string.format("|cffffffff%s|r  %s", name, colTag))

    local metaLines = {}
    if qStatus then
        local curZone = (qStatus.currentStep and qStatus.currentStep.zone) or ""
        table.insert(metaLines, string.format(L.META_CHAIN_TYPE_ZONE, qStatus.category, curZone ~= "" and curZone or "—"))
        table.insert(metaLines, string.format(L.META_CHAIN_PROGRESS, qStatus.completedSteps, qStatus.totalSteps))
    else
        local bossStr = (dropInfo and dropInfo.boss) or (bestCoord and bestCoord.n) or "—"
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

    -- Заполняем карточки шагов (Сделано / Надо сделать)
    local stepsToRender = {}
    if qStatus and qStatus.steps then
        for _, st in ipairs(qStatus.steps) do
            local badge = L.QUEST_STEP_LOCKED
            local bg = { 0.07, 0.08, 0.10, 0.90 }
            local br = { 0.20, 0.22, 0.26, 0.90 }
            if st.isDone then
                badge = L.QUEST_STEP_DONE
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

            local coordText = (st.x and st.y) and string.format("|cff00ccff%s [%.1f, %.1f]|r", st.zone or "", st.x, st.y) or (st.zone or "")
            table.insert(stepsToRender, {
                mountID = mountID,
                stepIndex = st.index,
                doneQuest = st.doneQuest,
                badge = badge,
                coords = coordText,
                title = st.title,
                npc = st.npc ~= "" and (L.STEP_NPC_PREFIX .. st.npc .. "|r") or "",
                desc = st.desc or "",
                bg = bg,
                br = br,
            })
        end
    else
        -- Для обычных дроповых / прочих маунтов формируем понятный чек-лист добычи
        local lockedToday = addon:IsMountRareLockedToday(mountID)
        local badge1 = isCollected and L.QUEST_STEP_DONE or (lockedToday and L.TAG_LOCKED_TODAY or L.QUEST_STEP_ACTIVE)
        local coordText = ""
        if bestCoord and bestCoord.x and bestCoord.y then
            local zName = (bestCoord.m and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(bestCoord.m)) and C_Map.GetMapInfo(bestCoord.m).name or ""
            coordText = string.format("|cff00ccff%s [%.1f, %.1f]|r", zName, bestCoord.x, bestCoord.y)
        end
        local cleanSource = (sourceText and sourceText ~= "") and sourceText:gsub("|n", "\n") or (description or "")
        table.insert(stepsToRender, {
            mountID = mountID,
            stepIndex = nil,
            badge = badge1,
            coords = coordText,
            title = (dropInfo and dropInfo.boss) and (L.STEP_DROP_TITLE_PREFIX .. dropInfo.boss) or name,
            npc = (bestCoord and bestCoord.n and bestCoord.n ~= "") and (L.STEP_TARGET_PREFIX .. bestCoord.n .. "|r") or "",
            desc = cleanSource,
            bg = isCollected and { 0.06, 0.12, 0.08, 0.92 } or { 0.12, 0.11, 0.06, 0.94 },
            br = isCollected and { 0.18, 0.58, 0.30, 0.95 } or { 0.85, 0.68, 0.15, 1.0 },
        })
    end

    local yOffset = 0
    for idx, item in ipairs(stepsToRender) do
        local card = GetOrCreateChecklistCard(pool, panel.scrollContent, idx, cardWidth)
        card.mountID = item.mountID
        card.stepIndex = item.stepIndex
        card.doneQuest = item.doneQuest
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
    nameFS:SetPoint("LEFT", iconFrame, "RIGHT", 10, 0)
    nameFS:SetPoint("RIGHT", headerBox, "RIGHT", -10, 0)
    nameFS:SetJustifyH("LEFT")
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

    -- Заголовок секции чек-листа
    local secLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    secLabel:SetPoint("TOPLEFT", headerBox, "BOTTOMLEFT", 2, -8)
    secLabel:SetTextColor(1.0, 0.82, 0.0, 1.0)
    secLabel:SetText(L.SECTION_CHECKLIST)
    panel.secLabel = secLabel

    -- Скролл со списком шагов (Сделано / Надо сделать)
    local scrollFrame = CreateFrame("ScrollFrame", scrollName, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", headerBox, "BOTTOMLEFT", 0, -26)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 68)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(cardWidth, 1)
    scrollFrame:SetScrollChild(scrollContent)
    panel.scrollContent = scrollContent

    -- Нижняя панель кнопок действий (2x2)
    local btnBar = CreateFrame("Frame", nil, panel)
    btnBar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    btnBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    btnBar:SetHeight(54)

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
            if mID and addon.MountQuestsByMountID[mID] then
                addon:OpenMountQuestChain(mID)
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
-- ============================================================================
local radarFrame = CreateFrame("Frame", "MountCollectorRadarFrame", UIParent, "BackdropTemplate")
radarFrame:SetSize(840, 540)
radarFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
radarFrame:SetFrameStrata("DIALOG")
ApplyFlatBackdrop(radarFrame, 0.05, 0.05, 0.06, 0.96, 0.18, 0.18, 0.20, 1.0)
radarFrame:EnableMouse(true)
radarFrame:SetMovable(true)
radarFrame:RegisterForDrag("LeftButton")
radarFrame:SetScript("OnDragStart", radarFrame.StartMoving)
radarFrame:SetScript("OnDragStop", radarFrame.StopMovingOrSizing)
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
local totalBox = CreateFrame("Frame", nil, radarFrame, "BackdropTemplate")
totalBox:SetSize(150, 24)
totalBox:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 12, -36)
ApplyFlatBackdrop(totalBox, 0.03, 0.03, 0.04, 0.95, 0.18, 0.18, 0.20, 1.0)

local totalFS = totalBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
totalFS:SetPoint("CENTER", totalBox, "CENTER", 0, 0)
totalFS:SetTextColor(1.0, 0.82, 0.0, 1.0)

local tabQuestsBtn = CreateFlatButton(radarFrame, 155, 24, "", false)
tabQuestsBtn:SetPoint("LEFT", totalBox, "RIGHT", 8, 0)

local tabZoneBtn = CreateFlatButton(radarFrame, 145, 24, "", false)
tabZoneBtn:SetPoint("LEFT", tabQuestsBtn, "RIGHT", 6, 0)

local tabAllBtn = CreateFlatButton(radarFrame, 155, 24, "", false)
tabAllBtn:SetPoint("LEFT", tabZoneBtn, "RIGHT", 6, 0)

local btnPinZone = CreateFlatButton(radarFrame, 125, 24, "", false)
btnPinZone:SetPoint("LEFT", tabAllBtn, "RIGHT", 6, 0)
btnPinZone:SetScript("OnClick", function()
    local zoneMounts, mapID = addon:GetZoneUncollectedMounts()
    for _, m in ipairs(zoneMounts) do
        if not m.locked then
            addon:SetMountWaypoint(m.mountID, mapID, nil, nil, m.boss, true)
        end
    end
    if zoneMounts[1] then
        addon:SetMountWaypoint(zoneMounts[1].mountID, mapID, nil, nil, zoneMounts[1].boss, false)
    end
end)

local btnSettings = CreateFlatButton(radarFrame, 88, 24, "", false)
btnSettings:SetPoint("TOPRIGHT", radarFrame, "TOPRIGHT", -12, -36)
btnSettings:SetScript("OnClick", function()
    if ui.currentTab == "SETTINGS" then
        ui.currentTab = ui.previousTab or "QUESTS"
    else
        ui.previousTab = ui.currentTab
        ui.currentTab = "SETTINGS"
    end
    addon:RefreshRadarUI()
end)

-- ВСТРОЕННАЯ ПАНЕЛЬ НАСТРОЕК ВНУТРИ ГЛАВНОГО ОКНА /mc (БЕЗ ОТДЕЛЬНОГО ПОПАПА)
local settingsPanel = CreateFrame("Frame", nil, radarFrame, "BackdropTemplate")
settingsPanel:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 12, -66)
settingsPanel:SetPoint("BOTTOMRIGHT", radarFrame, "BOTTOMRIGHT", -12, 12)
ApplyFlatBackdrop(settingsPanel, 0.04, 0.04, 0.05, 0.94, 0.18, 0.18, 0.20, 1.0)
settingsPanel:Hide()
ui.settingsPanel = settingsPanel
addon.radarSettingsPanel = settingsPanel

-- ЛЕВАЯ КОЛОНКА (Поиск + Список маунтов, как в «Транспорт»)
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

local listScroll = CreateFrame("ScrollFrame", "MountCollectorListScroll", leftCol, "UIPanelScrollFrameTemplate")
listScroll:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 6, -36)
listScroll:SetPoint("BOTTOMRIGHT", leftCol, "BOTTOMRIGHT", -26, 6)

local listContent = CreateFrame("Frame", nil, listScroll)
listContent:SetSize(276, 1)
listScroll:SetScrollChild(listContent)

-- ПРАВАЯ КОЛОНКА (Досье выбранного маунта + Чек-лист шагов + Кнопки навигации)
local rightInspector = CreateMountInspectorWidget(radarFrame, "MountCollectorStepScroll", 464, false)
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

function addon:OpenMountQuestChain(mountID)
    if not mountID then return end
    ui.currentTab = "QUESTS"
    ui.selectedMountID = mountID
    radarFrame:Show()
    self:RefreshRadarUI()
    self:NavigateMountQuestStep(mountID, nil, false)
end

function addon:RefreshRadarUI()
    radarTitle:SetText(L.RADAR_WINDOW_TITLE)
    tabQuestsBtn:SetText(L.TAB_QUEST_CHAINS)
    tabZoneBtn:SetText(L.TAB_CURRENT_ZONE)
    tabAllBtn:SetText(L.TAB_ALL_ATTEMPTS)
    btnPinZone:SetText(L.BTN_PIN_ALL_ZONE)
    btnSettings:SetText(L.BTN_SETTINGS)
    searchPlaceholder:SetText(L.SEARCH_PLACEHOLDER)

    if ui.journalDockToggleBtn then
        ui.journalDockToggleBtn:SetText(L.DOCK_TOGGLE_BTN)
    end
    if ui.journalDockTitle then
        ui.journalDockTitle:SetText(L.DOCK_WINDOW_TITLE)
    end

    tabQuestsBtn:SetActiveTab(ui.currentTab == "QUESTS")
    tabZoneBtn:SetActiveTab(ui.currentTab == "ZONE")
    tabAllBtn:SetActiveTab(ui.currentTab == "ALL")
    btnSettings:SetActiveTab(ui.currentTab == "SETTINGS")

    if ui.currentTab == "ZONE" then
        btnPinZone:Show()
    else
        btnPinZone:Hide()
    end

    if not radarFrame:IsShown() then return end

    if ui.currentTab == "SETTINGS" then
        totalFS:SetText(string.format(L.TOTAL_LABEL, ui.lastListCount or #(self.MountQuestsDB or {})))
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

    if ui.currentTab == "QUESTS" then
        local _, playerClass = UnitClass("player")
        if type(self.MountQuestsDB) == "table" then
            for _, qChain in ipairs(self.MountQuestsDB) do
                local mID = qChain.resolvedMountID or (qChain.spellID and self.MountBySpell[qChain.spellID]) or qChain.mountID
                local st = mID and self:GetMountQuestChainStatus(mID)
                if st then
                    st.isPlayerClass = (st.classRestriction and st.classRestriction == playerClass) and true or false
                    if ui.searchText == "" or string.find(string.lower(st.name), ui.searchText, 1, true) or string.find(string.lower(st.category), ui.searchText, 1, true) then
                        local badge
                        if st.isCollected then
                            badge = L.TAG_COLLECTED
                        elseif st.hasStarted or st.completedSteps > 0 then
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
            return (a.completedSteps or 0) > (b.completedSteps or 0)
        end)
    elseif ui.currentTab == "ZONE" then
        local zoneMounts = self:GetZoneUncollectedMounts()
        for _, m in ipairs(zoneMounts) do
            if ui.searchText == "" or string.find(string.lower(m.name), ui.searchText, 1, true) then
                local chPart = (m.chance and m.chance > 0) and string.format(" • 1/%d", m.chance) or ""
                table.insert(listEntries, {
                    mountID = m.mountID,
                    name = m.name,
                    icon = m.icon,
                    isCollected = false,
                    subLine = string.format(L.ROW_ATTEMPTS_FMT, m.attempts or 0) .. "|cff888888" .. chPart .. "|r",
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

    ui.lastListCount = #listEntries
    totalFS:SetText(string.format(L.TOTAL_LABEL, #listEntries))

    local foundSelected = false
    for _, item in ipairs(listEntries) do
        if item.mountID == ui.selectedMountID then
            foundSelected = true
            break
        end
    end
    if not foundSelected then
        ui.selectedMountID = listEntries[1] and listEntries[1].mountID or nil
    end

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
    PopulateMountInspectorPanel(rightInspector, ui.selectedMountID, ui.stepRowPool, 464)
end

function addon:ToggleRadarWindow()
    if radarFrame:IsShown() then
        radarFrame:Hide()
    else
        if ui.currentTab == "SETTINGS" then
            ui.currentTab = ui.previousTab or "QUESTS"
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

tabQuestsBtn:SetScript("OnClick", function()
    ui.currentTab = "QUESTS"
    addon:RefreshRadarUI()
end)

tabZoneBtn:SetScript("OnClick", function()
    ui.currentTab = "ZONE"
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

-- ============================================================================
-- 6. LIBDATABROKER-1.1 + ИКОНКА НА МИНИ-КАРТЕ (LIBDBICON-1.0)
-- ============================================================================
function addon:UpdateLDBText()
    if not self.ldbObj then return end
    local zoneMounts = self:GetZoneUncollectedMounts()
    if #zoneMounts > 0 then
        self.ldbObj.text = string.format(L.LDB_TEXT_ZONE, #zoneMounts)
    else
        self.ldbObj.text = L.LDB_TEXT_CLEAN
    end
end

function addon:InitLDB()
    if not LDB or self.ldbObj then return end

    self.ldbObj = LDB:NewDataObject("MountCollector", {
        type = "data source",
        text = "MountCollector",
        icon = "Interface\\ICONS\\Ability_Mount_SpectralTiger",
        OnClick = function(_, button)
            if button == "RightButton" then
                if ToggleCollectionsJournal then
                    ToggleCollectionsJournal(1)
                end
            elseif button == "MiddleButton" then
                if addon.ToggleConfigFrame then
                    addon:ToggleConfigFrame()
                end
            else
                addon:ToggleRadarWindow()
            end
        end,
        OnTooltipShow = function(tooltip)
            if not tooltip then return end
            tooltip:AddLine(L.LDB_TT_TITLE)
            tooltip:AddLine(L.LDB_TT_HINT)
            tooltip:AddLine(" ")

            local zoneMounts, mapID = addon:GetZoneUncollectedMounts()
            local mapName = (mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)) and C_Map.GetMapInfo(mapID).name or GetRealZoneText() or "Zone"
            tooltip:AddLine(string.format(L.LDB_TT_ZONE_HEADER, mapName))

            if #zoneMounts == 0 then
                tooltip:AddLine(L.LDB_TT_ZONE_EMPTY)
            else
                for i = 1, math.min(12, #zoneMounts) do
                    local m = zoneMounts[i]
                    local pctText = addon:FormatRarityTier(m.globalRarity)
                    local lockStr = m.locked and L.TAG_LOCKED_SHORT or ""
                    local iconTag = m.icon and string.format("|T%s:14:14:0:0|t ", m.icon) or ""
                    local chancePart = (m.chance and m.chance > 0) and string.format("1/%d | ", m.chance) or ""
                    tooltip:AddDoubleLine(
                        string.format("  %s|cffa335ee%s|r%s", iconTag, m.name, lockStr),
                        string.format(L.LDB_TT_ROW_RIGHT, m.attempts or 0, chancePart, pctText)
                    )
                end
            end
        end,
    })

    if LDBIcon and self.db and self.db.minimap then
        LDBIcon:Register("MountCollector", self.ldbObj, self.db.minimap)
    end
end

SLASH_MOUNTCOLLECTOR1 = "/mc"
SLASH_MOUNTCOLLECTOR2 = "/mountcollector"
SlashCmdList["MOUNTCOLLECTOR"] = function(msg)
    local cmd = strtrim(string.lower(msg or ""))
    if cmd == "config" or cmd == "settings" or cmd == "opt" or cmd == "options" then
        if addon.ToggleConfigFrame then
            addon:ToggleConfigFrame()
        end
    else
        addon:ToggleRadarWindow()
    end
end
