local _, addon = ...

-- ============================================================================
-- MountCollector — MapPins.lua
-- Модуль интерактивных меток на Карте Мира (WorldMapFrame) и круглой иконки миникарты:
--   * Отрисовка иконок неполученных и доступных сегодня рарников/ворлдбоссов на карте зоны
--     (GetOrCreateMapPin, RefreshWorldMapPins, InitWorldMapPins)
--   * Интеграция с LibDataBroker-1.1 и LibDBIcon-1.0 (круглая иконка золотой подковы у миникарты,
--     поддержка кастомных панелей HidingBar / ElvUI / TitanPanel / Bazooka и Addon Compartment)
-- ============================================================================

local L = addon.L
local LibStub = _G.LibStub
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
local ui = addon.UIState
local ApplyFlatBackdrop = addon.ApplyFlatBackdrop

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

    pin.badge = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pin.badge:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
    pin.badge:SetTextColor(1.0, 0.92, 0.15, 1.0)
    pin.badge:SetText("")

    pin:SetScript("OnEnter", function(self)
        if not self.mountID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local mName, _, mIcon = addon:GetMountInfoByID(self.mountID)
        local iconTag = mIcon and string.format("|T%s:18:18:0:0|t ", mIcon) or ""
        local displayMounts = iconTag .. (mName or "Mount")
        if self.mountIDs and #self.mountIDs > 1 then
            local parts = {}
            for _, mID in ipairs(self.mountIDs) do
                local n, _, ic = addon:GetMountInfoByID(mID)
                if n then
                    local it = ic and string.format("|T%s:16:16:0:0|t ", ic) or ""
                    table.insert(parts, it .. n)
                end
            end
            if #parts > 1 then
                displayMounts = table.concat(parts, " / ")
            end
        end
        local npcLine = self.npcName and ("|cffffd100" .. self.npcName .. "|r — ") or ""
        GameTooltip:SetText(npcLine .. displayMounts, 1, 1, 1)
        if self.npcID then
            local timerText = addon.GetRareRespawnTimerText and addon:GetRareRespawnTimerText(self.npcID) or nil
            if timerText then
                GameTooltip:AddDoubleLine(L.TT_STATUS_TODAY, timerText)
            else
                local npcLocked = addon:IsNpcLockedToday(self.npcID)
                GameTooltip:AddDoubleLine(L.TT_STATUS_TODAY, npcLocked and L.TT_NPC_STATUS_LOCKED or L.TT_NPC_STATUS_AVAIL)
            end
        end
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
            local combinedNames = nil
            if self.mountIDs and #self.mountIDs > 1 then
                local names = {}
                for _, mID in ipairs(self.mountIDs) do
                    local mName, _, _, _, _, _, _, _, _, _, mCol = addon:GetMountInfoByID(mID)
                    if mName and not mCol then
                        table.insert(names, mName)
                    end
                end
                if #names > 1 then
                    combinedNames = table.concat(names, ", ")
                end
            end
            addon:SetMountWaypoint(self.mountID, self.mapID, self.coordX, self.coordY, self.npcName, false, combinedNames, self.npcID)
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
    local pinByCoordKey = {}
    for _, mountID in ipairs(list) do
        local name, _, icon, _, _, _, _, _, _, _, isCollected = self:GetMountInfoByID(mountID)
        local isHighlighted = (self.highlightedMapMountID and self.highlightedMapMountID == mountID)
        if name and (not isCollected or isHighlighted) then
            local info = self.DropInfoByMount[mountID]
            local locked = self:IsMountRareLockedToday(mountID)
            if info and info.coords then
                for _, c in ipairs(info.coords) do
                    local coordVisited = self.IsSpawnCoordRecentlyVisited and self:IsSpawnCoordRecentlyVisited(mapID, c.x, c.y)
                    local pinLocked = (c.npcID and self:IsNpcLockedToday(c.npcID)) or locked or coordVisited
                    if not pinLocked and c.m == mapID and c.x and c.x > 0 and c.y and c.y > 0 then
                        local coordKey = string.format("%d:%.1f:%.1f", mapID, c.x, c.y)
                        local existingPin = pinByCoordKey[coordKey]
                        if existingPin then
                            existingPin.mountIDs = existingPin.mountIDs or { existingPin.mountID }
                            local alreadyAdded = false
                            for _, mID in ipairs(existingPin.mountIDs) do
                                if mID == mountID then
                                    alreadyAdded = true
                                    break
                                end
                            end
                            if not alreadyAdded then
                                table.insert(existingPin.mountIDs, mountID)
                            end
                            if isHighlighted and not existingPin.pinLocked then
                                existingPin:SetSize(28, 28)
                                existingPin.icon:SetDesaturated(false)
                                existingPin:SetBackdropBorderColor(0.0, 0.95, 1.0, 1.0)
                                existingPin:SetAlpha(1.0)
                            end
                        else
                            pinIdx = pinIdx + 1
                            local pin = GetOrCreateMapPin(canvas, pinIdx)
                            pin.mountID = mountID
                            pin.mountIDs = { mountID }
                            pin.npcID = c.npcID
                            pin.pinLocked = pinLocked
                            pin.mapID = mapID
                            pin.coordX = c.x
                            pin.coordY = c.y
                            pin.npcName = self:GetNpcDisplayName(c.npcID, ((c.n and c.n ~= "") and c.n) or info.boss or name)
                            pin.icon:SetTexture(icon or "Interface\\ICONS\\Ability_Mount_SpectralTiger")

                            local tourStepNum = nil
                            local isCurrentTourStep = false
                            if self.activeSpawnTour and self.activeSpawnTour.mountID == mountID and self.activeSpawnTour.points then
                                for tIdx, tPt in ipairs(self.activeSpawnTour.points) do
                                    if not tPt.visited and tPt.m == mapID and math.abs((tPt.x or 0) - c.x) < 0.15 and math.abs((tPt.y or 0) - c.y) < 0.15 then
                                        tourStepNum = tIdx
                                        isCurrentTourStep = (tIdx == self.activeSpawnTour.index)
                                        break
                                    end
                                end
                            end

                            if pin.badge then
                                if tourStepNum and not pinLocked then
                                    pin.badge:SetText(tostring(tourStepNum))
                                    pin.badge:Show()
                                else
                                    pin.badge:SetText("")
                                    pin.badge:Hide()
                                end
                            end

                            if pinLocked then
                                pin:SetSize(22, 22)
                                pin.icon:SetDesaturated(true)
                                pin:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.75)
                                pin:SetAlpha(0.55)
                            elseif isCurrentTourStep then
                                pin:SetSize(30, 30)
                                pin.icon:SetDesaturated(false)
                                pin:SetBackdropBorderColor(0.0, 1.0, 0.55, 1.0)
                                pin:SetAlpha(1.0)
                            elseif isHighlighted then
                                pin:SetSize(28, 28)
                                pin.icon:SetDesaturated(false)
                                pin:SetBackdropBorderColor(0.0, 0.95, 1.0, 1.0)
                                pin:SetAlpha(1.0)
                            else
                                pin:SetSize(24, 24)
                                pin.icon:SetDesaturated(false)
                                pin:SetBackdropBorderColor(1.0, 0.78, 0.0, 1.0)
                                pin:SetAlpha(1.0)
                            end

                            local px = (c.x / 100.0) * cw
                            local py = -(c.y / 100.0) * ch
                            pin:ClearAllPoints()
                            pin:SetPoint("CENTER", canvas, "TOPLEFT", px, py)
                            pin:Show()
                            pinByCoordKey[coordKey] = pin
                        end
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

function addon:EnsureRoundMinimapButton()
    if not LDBIcon then
        LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    end
    if not LDBIcon then return end
    local btn = LDBIcon:GetMinimapButton("MountCollector")
    if not btn then return end

    -- Делаем иконку подковы идеально круглой внутри золотого кольца миникарты (Circular MaskTexture)
    if btn.icon and btn.CreateMaskTexture and not btn.mcRoundMask then
        local mask = btn:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(btn.icon)
        btn.icon:AddMaskTexture(mask)
        btn.mcRoundMask = mask
    end
    if btn.icon and not btn._MSQ_CFG then
        btn.icon:SetSize(20, 20)
        btn.icon:ClearAllPoints()
        btn.icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    end

    -- Если кнопка висит прямо на миникарте (не спрятана внутрь выдвижной панели вроде HidingBar),
    -- отключаем принудительное скрытие по курсору от BasicMinimap, чтобы круглая подкова всегда была видна!
    if self.db and self.db.minimap and not self.db.minimap.hide then
        if btn:GetParent() == _G.Minimap then
            LDBIcon:ShowOnEnter("MountCollector", false)
            btn:SetAlpha(1)
            btn:Show()
        end
    end
end

function addon:InitLDB()
    if not LDB or self.ldbObj then return end

    local horseshoeIcon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(168412))
        or "Interface\\ICONS\\inv_blacksmith_leystonehoofplates_orange"

    self.ldbObj = LDB:NewDataObject("MountCollector", {
        type = "launcher",
        label = "MountCollector",
        text = "MountCollector",
        icon = horseshoeIcon,
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
        self:EnsureRoundMinimapButton()
    end
end
