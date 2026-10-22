local _, addon = ...

local L = addon.L
local LibStub = _G.LibStub
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

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

-- ============================================================================
-- 1. ВСПЛЫВАЮЩИЙ РАДАР-БАННЕР ПРИ ОБНАРУЖЕНИИ РАРНИКА / БОССА С НЕСОБРАННЫМ МАУНТОМ
-- ============================================================================
local alertFrame = CreateFrame("Button", "MountCollectorAlertFrame", UIParent, "BackdropTemplate")
alertFrame:SetSize(390, 72)
alertFrame:SetPoint("TOP", UIParent, "TOP", 0, -140)
alertFrame:SetFrameStrata("HIGH")
alertFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
alertFrame:SetBackdropColor(0.06, 0.07, 0.10, 0.95)
alertFrame:SetBackdropBorderColor(0.0, 0.8, 1.0, 0.95)
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

local closeAlertBtn = CreateFrame("Button", nil, alertFrame, "UIPanelCloseButton")
closeAlertBtn:SetSize(22, 22)
closeAlertBtn:SetPoint("TOPRIGHT", alertFrame, "TOPRIGHT", -2, -2)

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
-- 2. ИКОНКИ РАРНИКОВ И БОССОВ С МАУНТАМИ ПРЯМО НА КАРТЕ МИРА (WORLD MAP PINS)
-- ============================================================================
local mapPinPool = {}
local worldMapHooked = false

local function GetOrCreateMapPin(parent, index)
    if mapPinPool[index] then
        mapPinPool[index]:SetParent(parent)
        return mapPinPool[index]
    end

    local pin = CreateFrame("Button", nil, parent, "BackdropTemplate")
    pin:SetSize(24, 24)
    pin:SetFrameStrata("HIGH")
    pin:SetFrameLevel(2500)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1.5,
    })
    pin:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    pin:SetBackdropBorderColor(1.0, 0.75, 0.0, 1.0)

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

    mapPinPool[index] = pin
    return pin
end

function addon:RefreshWorldMapPins()
    for _, pin in ipairs(mapPinPool) do
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
    if worldMapHooked or not _G.WorldMapFrame then return end
    worldMapHooked = true

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
-- 3. ОКНО РАДАРА И ТРЕКЕРА ТРАЕВ (/mc или /mountcollector)
-- ============================================================================
local radarFrame = CreateFrame("Frame", "MountCollectorRadarFrame", UIParent, "BackdropTemplate")
radarFrame:SetSize(560, 420)
radarFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
radarFrame:SetFrameStrata("DIALOG")
radarFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
radarFrame:SetBackdropColor(0.05, 0.06, 0.09, 0.95)
radarFrame:SetBackdropBorderColor(0.2, 0.6, 0.9, 0.85)
radarFrame:EnableMouse(true)
radarFrame:SetMovable(true)
radarFrame:RegisterForDrag("LeftButton")
radarFrame:SetScript("OnDragStart", radarFrame.StartMoving)
radarFrame:SetScript("OnDragStop", radarFrame.StopMovingOrSizing)
radarFrame:Hide()

local radarTitle = radarFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
radarTitle:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 14, -12)

local radarClose = CreateFrame("Button", nil, radarFrame, "UIPanelCloseButton")
radarClose:SetPoint("TOPRIGHT", radarFrame, "TOPRIGHT", -4, -4)

local currentTab = "ZONE"

local tabZoneBtn = CreateFrame("Button", nil, radarFrame, "UIPanelButtonTemplate")
tabZoneBtn:SetSize(135, 24)
tabZoneBtn:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 14, -38)

local tabAllBtn = CreateFrame("Button", nil, radarFrame, "UIPanelButtonTemplate")
tabAllBtn:SetSize(145, 24)
tabAllBtn:SetPoint("LEFT", tabZoneBtn, "RIGHT", 6, 0)

local btnPinZone = CreateFrame("Button", nil, radarFrame, "UIPanelButtonTemplate")
btnPinZone:SetSize(145, 24)
btnPinZone:SetPoint("LEFT", tabAllBtn, "RIGHT", 6, 0)
btnPinZone:SetScript("OnClick", function()
    local zoneMounts, mapID = addon:GetZoneUncollectedMounts()
    local count = 0
    for _, m in ipairs(zoneMounts) do
        if not m.locked and addon:SetMountWaypoint(m.mountID, mapID, nil, nil, m.boss, true) then
            count = count + 1
        end
    end
    if count > 0 and zoneMounts[1] then
        addon:SetMountWaypoint(zoneMounts[1].mountID, mapID, nil, nil, zoneMounts[1].boss, false)
    end
end)

local btnSettings = CreateFrame("Button", nil, radarFrame, "UIPanelButtonTemplate")
btnSettings:SetSize(90, 24)
btnSettings:SetPoint("LEFT", btnPinZone, "RIGHT", 6, 0)
btnSettings:SetScript("OnClick", function()
    if addon.ToggleConfigFrame then
        addon:ToggleConfigFrame()
    end
end)

local subHeader = radarFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subHeader:SetPoint("TOPLEFT", tabZoneBtn, "BOTTOMLEFT", 2, -8)
subHeader:SetPoint("RIGHT", radarFrame, "RIGHT", -14, 0)
subHeader:SetJustifyH("LEFT")

local scrollFrame = CreateFrame("ScrollFrame", "MountCollectorRadarScroll", radarFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 14, -86)
scrollFrame:SetPoint("BOTTOMRIGHT", radarFrame, "BOTTOMRIGHT", -32, 14)

local contentFrame = CreateFrame("Frame", nil, scrollFrame)
contentFrame:SetSize(500, 1)
scrollFrame:SetScrollChild(contentFrame)

local rowPool = {}

local function GetOrCreateRow(index)
    if rowPool[index] then return rowPool[index] end
    local row = CreateFrame("Button", nil, contentFrame, "BackdropTemplate")
    row:SetSize(500, 38)
    row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -((index - 1) * 40))
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    row:SetBackdropColor(0.10, 0.12, 0.16, 0.85)
    row:SetBackdropBorderColor(0.2, 0.25, 0.32, 0.7)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
    row.title:SetPoint("RIGHT", row, "RIGHT", -115, 0)
    row.title:SetJustifyH("LEFT")

    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -115, 0)
    row.sub:SetJustifyH("LEFT")

    row.rightTop = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rightTop:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
    row.rightTop:SetJustifyH("RIGHT")

    row.rightBottom = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.rightBottom:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 4)
    row.rightBottom:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.0, 0.8, 1.0, 1.0)
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
        self:SetBackdropBorderColor(0.2, 0.25, 0.32, 0.7)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button)
        if not self.mountID then return end
        if button == "RightButton" or IsShiftKeyDown() then
            addon:SetMountWaypoint(self.mountID, nil, nil, nil, self.bossName, false)
        else
            addon:OpenMountInJournal(self.mountID)
        end
    end)

    rowPool[index] = row
    return row
end

function addon:RefreshRadarUI()
    radarTitle:SetText(L.RADAR_WINDOW_TITLE)
    tabZoneBtn:SetText(L.TAB_CURRENT_ZONE)
    tabAllBtn:SetText(L.TAB_ALL_ATTEMPTS)
    btnPinZone:SetText(L.BTN_PIN_ALL_ZONE)
    btnSettings:SetText(L.BTN_SETTINGS)

    if not radarFrame:IsShown() then return end

    for _, row in ipairs(rowPool) do
        row:Hide()
    end

    local items = {}
    if currentTab == "ZONE" then
        local zoneMounts, mapID = self:GetZoneUncollectedMounts()
        local mapName = (mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)) and C_Map.GetMapInfo(mapID).name or GetRealZoneText() or "Zone"
        subHeader:SetText(string.format(L.SUBHEADER_ZONE, mapName, #zoneMounts))
        items = zoneMounts
    else
        for mountID, info in pairs(self.DropInfoByMount) do
            local name, spellID, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if name and not isCollected then
                local attempts = self:GetMountAttempts(mountID)
                if attempts > 0 then
                    table.insert(items, {
                        mountID = mountID,
                        name = name,
                        spellID = spellID,
                        icon = icon,
                        attempts = attempts,
                        chance = info.chance,
                        boss = info.boss,
                        globalRarity = self:GetGlobalRarity(mountID),
                        locked = self:IsMountRareLockedToday(mountID),
                        coord = self:GetBestMountCoords(mountID),
                    })
                end
            end
        end
        table.sort(items, function(a, b)
            return (a.attempts or 0) > (b.attempts or 0)
        end)
        subHeader:SetText(string.format(L.SUBHEADER_ALL, #items))
    end

    for idx, entry in ipairs(items) do
        local row = GetOrCreateRow(idx)
        row.mountID = entry.mountID
        row.bossName = entry.boss
        row.icon:SetTexture(entry.icon or "Interface\\ICONS\\Ability_Mount_SpectralTiger")

        local lockTag = entry.locked and L.TAG_LOCKED_TODAY or ""
        row.title:SetText(string.format("|cffa335ee%s|r%s", entry.name, lockTag))

        local pctText = self:FormatRarityTier(entry.globalRarity)
        local bossStr = entry.boss and (L.ROW_BOSS_PREFIX .. entry.boss .. " | ") or ""
        local coordStr = (entry.coord and entry.coord.x and entry.coord.x > 0) and string.format("|cff00ccff[%.1f, %.1f]|r ", entry.coord.x, entry.coord.y) or ""
        row.sub:SetText(string.format("|cffbbbbbb%s%s%s%s|r", coordStr, bossStr, L.ROW_WORLD_PREFIX, pctText))

        row.rightTop:SetText(string.format(L.ROW_ATTEMPTS_FMT, entry.attempts or 0))
        if entry.chance and entry.chance > 0 then
            row.rightBottom:SetText(string.format(L.ROW_CHANCE_FMT, entry.chance))
        else
            row.rightBottom:SetText(L.ROW_DROP_MOUNT_FMT)
        end
        row:Show()
    end

    contentFrame:SetHeight(math.max(1, #items * 40))
end

function addon:ToggleRadarWindow()
    if radarFrame:IsShown() then
        radarFrame:Hide()
    else
        radarFrame:Show()
        self:RefreshRadarUI()
    end
end

tabZoneBtn:SetScript("OnClick", function()
    currentTab = "ZONE"
    addon:RefreshRadarUI()
end)

tabAllBtn:SetScript("OnClick", function()
    currentTab = "ALL"
    addon:RefreshRadarUI()
end)

-- ============================================================================
-- 4. LIBDATABROKER-1.1 + ИКОНКА НА МИНИ-КАРТЕ (LIBDBICON-1.0)
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
