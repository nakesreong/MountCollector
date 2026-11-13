local _, addon = ...

-- ============================================================================
-- MountCollector — RareRadar.lua
-- Модуль детектора рарников и ворлдбоссов в открытом мире и всплывающего баннера:
--   * Жёсткий фильтр инстансов (IsPlayerInInstancedContent, IsOpenWorldRareOrWorldBossMount) —
--     гарантирует отсутствие спама плашки внутри подземелий и рейдов!
--   * Детектор рарников по неймплейтам, таргету, маусоверу, виньеткам миникарты и крикам
--     (CheckUnitForMountDrop, CheckVignetteForMountDrop, ScanAllActiveVignettes, CheckMonsterChatForMountDrop)
--   * Всплывающий радар-баннер MountCollectorAlertFrame с защищённым SecureActionButton-оверлеем
--     (ЛКМ — взятие рарника в цель и метка без ADDON_ACTION_FORBIDDEN)
--   * Временный авто-перехват клавиши Target Nearest Enemy (Tab) на подлёте к рарнику вне боя
-- ============================================================================

local L = addon.L
local SafeNotSecret = addon.SafeNotSecret
local IsValidNpcName = addon.IsValidNpcName
local ApplyFlatBackdrop = addon.ApplyFlatBackdrop
local CreateFlatButton = addon.CreateFlatButton

-- Всплывающий радар-алерт должен срабатывать ТОЛЬКО в открытом мире на рарниках и мировых боссах,
-- никогда не спамя на боссах внутри подземелий и рейдов!
function addon:IsPlayerInInstancedContent()
    if not IsInInstance then return false end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok then return false end
    if inInstance and instanceType and instanceType ~= "none" then
        return true
    end
    return false
end

-- Проверить, относится ли маунт к открытому миру (рарник или ворлдбосс), а не к инстансовому данжу/рейду
function addon:IsOpenWorldRareOrWorldBossMount(mountID)
    if not mountID then return false end
    local dEntry = self.MountDungeonsByMountID and self.MountDungeonsByMountID[mountID]
    if dEntry and dEntry.sourceKind ~= "WORLD_BOSS" and not dEntry.isWorldBoss then
        return false
    end
    return true
end

function addon:CheckUnitForMountDrop(unit, isRetry)
    if not unit or not SafeNotSecret(unit) or not UnitExists(unit) then return end
    if UnitIsPlayer(unit) then
        self:ScanUnitMount(unit)
        return
    end

    -- Никогда не спамим радар-баннерами внутри данжей, рейдов, сценариев и PvP-инстансов!
    if self:IsPlayerInInstancedContent() then return end

    local guid = UnitGUID(unit)
    local npcID = self:GetNPCIDFromGUID(guid)
    if not npcID then return end

    local mounts = self.MountsByNpc[npcID]
    local isAlive = not UnitIsDead(unit)
    if isAlive and mounts then
        local isLockedNow, lockQid = self:IsNpcLockedToday(npcID)
        if not isLockedNow then
            self.RecentlySpottedUnlockedRares = self.RecentlySpottedUnlockedRares or {}
            self.RecentlySpottedUnlockedRares[npcID] = GetTime()
            if lockQid then
                self.CompletedRareQuestsSnapshot = self.CompletedRareQuestsSnapshot or {}
                self.CompletedRareQuestsSnapshot[lockQid] = false
            end
        end
    end

    local npcName = UnitName(unit)
    if IsValidNpcName(npcName) then
        self.KnownNpcNames = self.KnownNpcNames or {}
        self.KnownNpcNames[npcID] = npcName
        self.NpcByRareName = self.NpcByRareName or {}
        self.NpcByRareName[string.lower(npcName)] = npcID
    else
        if isAlive and mounts and not isRetry then
            C_Timer.After(0.25, function()
                if UnitExists(unit) then
                    self:CheckUnitForMountDrop(unit, true)
                end
            end)
            return
        end
        local rs = self.RareScannerNpcToMounts and self.RareScannerNpcToMounts[npcID]
        npcName = (self.KnownNpcNames and self.KnownNpcNames[npcID]) or (rs and rs.name) or "Rare NPC"
    end

    if not isAlive or not mounts then return end

    -- Если этот конкретный рарник уже убит сегодня этим персонажем (КД до сброса), не вопим и не ставим метку на второй круг!
    if self:IsNpcLockedToday(npcID) then return end

    local npcMapID, npcX, npcY = nil, nil, nil
    local rsEntry = self.RareScannerNpcToMounts and self.RareScannerNpcToMounts[npcID]
    if rsEntry and type(rsEntry.coords) == "table" and rsEntry.coords[1] then
        local rc = rsEntry.coords[1]
        npcMapID, npcX, npcY = rc.m, rc.x, rc.y
    end

    for _, mountID in ipairs(mounts) do
        if self:IsOpenWorldRareOrWorldBossMount(mountID) and not self:IsMountRareLockedToday(mountID) then
            local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if not isCollected then
                self:TriggerRareMountAlert(mountID, npcID, npcName, false, npcMapID, npcX, npcY)
                break
            end
        end
    end
end

function addon:CheckVignetteForMountDrop(vignetteGUID, isRetry)
    if self:IsPlayerInInstancedContent() then return end
    if not vignetteGUID or not SafeNotSecret(vignetteGUID) then return end
    if not C_VignetteInfo or not C_VignetteInfo.GetVignetteInfo then return end
    local vInfo = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
    if not vInfo then
        if not isRetry then
            C_Timer.After(0.35, function()
                self:CheckVignetteForMountDrop(vignetteGUID, true)
            end)
        end
        return
    end

    local npcID = SafeNotSecret(vInfo.objectGUID) and self:GetNPCIDFromGUID(vInfo.objectGUID) or nil
    if not npcID and IsValidNpcName(vInfo.name) and self.NpcByRareName then
        npcID = self.NpcByRareName[string.lower(vInfo.name)]
    end
    if not npcID then
        if not isRetry then
            C_Timer.After(0.35, function()
                self:CheckVignetteForMountDrop(vignetteGUID, true)
            end)
        end
        return
    end

    local mounts = self.MountsByNpc[npcID]
    if not mounts then return end

    -- Если этот конкретный рарник уже убит сегодня (КД до сброса), игнорируем его звезду на миникарте
    local isLockedNow, lockQid = self:IsNpcLockedToday(npcID)
    if isLockedNow then return end

    self.RecentlySpottedUnlockedRares = self.RecentlySpottedUnlockedRares or {}
    self.RecentlySpottedUnlockedRares[npcID] = GetTime()
    if lockQid then
        self.CompletedRareQuestsSnapshot = self.CompletedRareQuestsSnapshot or {}
        self.CompletedRareQuestsSnapshot[lockQid] = false
    end

    local vName = IsValidNpcName(vInfo.name) and vInfo.name or nil
    if vName then
        self.KnownNpcNames = self.KnownNpcNames or {}
        self.KnownNpcNames[npcID] = vName
        self.NpcByRareName = self.NpcByRareName or {}
        self.NpcByRareName[string.lower(vName)] = npcID
    else
        local rs = self.RareScannerNpcToMounts and self.RareScannerNpcToMounts[npcID]
        vName = (self.KnownNpcNames and self.KnownNpcNames[npcID]) or (rs and rs.name) or "Rare NPC"
    end

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local liveX, liveY = nil, nil
    if mapID and C_VignetteInfo.GetVignettePosition then
        local tryMaps = { mapID }
        if C_Map.GetMapInfo then
            local mInfo = C_Map.GetMapInfo(mapID)
            if mInfo and mInfo.parentMapID and mInfo.parentMapID > 0 then
                table.insert(tryMaps, mInfo.parentMapID)
            end
        end
        for _, candMap in ipairs(tryMaps) do
            local ok, pos = pcall(C_VignetteInfo.GetVignettePosition, vignetteGUID, candMap)
            if ok and pos and pos.GetXY then
                local vx, vy = pos:GetXY()
                if SafeNotSecret(vx) and SafeNotSecret(vy) and vx and vy and vx > 0 and vy > 0 then
                    mapID = candMap
                    liveX = vx * 100.0
                    liveY = vy * 100.0
                    break
                end
            end
        end
    end

    for _, mountID in ipairs(mounts) do
        if self:IsOpenWorldRareOrWorldBossMount(mountID) and not self:IsMountRareLockedToday(mountID) then
            local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if not isCollected then
                self:TriggerRareMountAlert(mountID, npcID, vName, false, mapID, liveX, liveY)
                break
            end
        end
    end
end

-- Просканировать все активные виньетки миникарты/карты (радиус 250-400+ ярдов, как в RareScanner)
function addon:ScanAllActiveVignettes()
    if self:IsPlayerInInstancedContent() then return end
    if not C_VignetteInfo or not C_VignetteInfo.GetVignettes then return end
    local ok, vignettes = pcall(C_VignetteInfo.GetVignettes)
    if not ok or type(vignettes) ~= "table" then return end
    for _, vGUID in ipairs(vignettes) do
        self:CheckVignetteForMountDrop(vGUID, false)
    end
end

-- Дальнобойный детект рарников по крику / эмоции / фразе в чат на всю локацию
function addon:CheckMonsterChatForMountDrop(senderName)
    if self:IsPlayerInInstancedContent() then return end
    if not IsValidNpcName(senderName) or not self.NpcByRareName then return end
    local npcID = self.NpcByRareName[string.lower(senderName)]
    if not npcID then return end
    local mounts = self.MountsByNpc and self.MountsByNpc[npcID]
    if not mounts then return end
    if self:IsNpcLockedToday(npcID) then return end

    self.KnownNpcNames = self.KnownNpcNames or {}
    self.KnownNpcNames[npcID] = senderName

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    for _, mountID in ipairs(mounts) do
        if self:IsOpenWorldRareOrWorldBossMount(mountID) and not self:IsMountRareLockedToday(mountID) then
            local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if not isCollected then
                local c = self:GetBestMountCoords(mountID, mapID)
                self:TriggerRareMountAlert(mountID, npcID, senderName, false, c and c.m or mapID, c and c.x, c and c.y)
                break
            end
        end
    end
end


-- ============================================================================
-- 1. ВСПЛЫВАЮЩИЙ РАДАР-БАННЕР ПРИ ОБНАРУЖЕНИИ РАРНИКА / БОССА
-- ============================================================================
local alertFrame = CreateFrame("Button", "MountCollectorAlertFrame", UIParent, "BackdropTemplate")
alertFrame:SetSize(440, 82)
alertFrame:SetPoint("TOP", UIParent, "TOP", 0, -130)
alertFrame:SetFrameStrata("HIGH")
ApplyFlatBackdrop(alertFrame, 0.05, 0.05, 0.07, 0.97, 1.0, 0.82, 0.0, 1.0)
alertFrame:EnableMouse(true)
alertFrame:SetMovable(true)
alertFrame:RegisterForDrag("LeftButton")
alertFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
alertFrame:SetScript("OnDragStart", alertFrame.StartMoving)
alertFrame:SetScript("OnDragStop", alertFrame.StopMovingOrSizing)
alertFrame:Hide()

local alertIconBorder = CreateFrame("Frame", nil, alertFrame, "BackdropTemplate")
alertIconBorder:SetSize(54, 54)
alertIconBorder:SetPoint("TOPLEFT", alertFrame, "TOPLEFT", 10, -10)
ApplyFlatBackdrop(alertIconBorder, 0.02, 0.02, 0.03, 1.0, 0.85, 0.68, 0.15, 1.0)

local alertIcon = alertIconBorder:CreateTexture(nil, "ARTWORK")
alertIcon:SetPoint("TOPLEFT", alertIconBorder, "TOPLEFT", 2, -2)
alertIcon:SetPoint("BOTTOMRIGHT", alertIconBorder, "BOTTOMRIGHT", -2, 2)
alertIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local alertHeader = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
alertHeader:SetPoint("TOPLEFT", alertIconBorder, "TOPRIGHT", 10, -1)
alertHeader:SetPoint("RIGHT", alertFrame, "RIGHT", -30, 0)
alertHeader:SetJustifyH("LEFT")
alertHeader:SetWordWrap(true)

local alertMountName = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
alertMountName:SetPoint("TOPLEFT", alertHeader, "BOTTOMLEFT", 0, -4)
alertMountName:SetPoint("RIGHT", alertFrame, "RIGHT", -12, 0)
alertMountName:SetJustifyH("LEFT")
alertMountName:SetWordWrap(true)

local alertStats = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
alertStats:SetPoint("TOPLEFT", alertMountName, "BOTTOMLEFT", 0, -4)
alertStats:SetPoint("RIGHT", alertFrame, "RIGHT", -12, 0)
alertStats:SetJustifyH("LEFT")
alertStats:SetWordWrap(true)

local closeAlertBtn = CreateFlatButton(alertFrame, 20, 20, "X", false)
closeAlertBtn:SetPoint("TOPRIGHT", alertFrame, "TOPRIGHT", -5, -5)
closeAlertBtn:SetFrameLevel(alertFrame:GetFrameLevel() + 6)
closeAlertBtn:SetScript("OnClick", function() alertFrame:Hide() end)

-- Защищённая кнопка SecureActionButtonTemplate поверх баннера для взятия рарника в цель (/targetexact) по клику ЛКМ!
-- ВАЖНО: крепим к UIParent (не к alertFrame!), чтобы сам alertFrame никогда не становился защищённым и спокойно скрывался в бою!
local secureTargetBtn = CreateFrame("Button", "MountCollectorAlertSecureBtn", UIParent, "SecureActionButtonTemplate")
secureTargetBtn:SetSize(440, 82)
secureTargetBtn:SetPoint("TOP", UIParent, "TOP", 0, -130)
secureTargetBtn:SetFrameStrata("HIGH")
secureTargetBtn:SetFrameLevel(alertFrame:GetFrameLevel() + 2)
secureTargetBtn:RegisterForClicks("AnyUp", "AnyDown")
secureTargetBtn:RegisterForDrag("LeftButton")
secureTargetBtn:Hide()

local function SyncSecureAlertOverlay()
    if InCombatLockdown and InCombatLockdown() then
        addon.pendingAlertOverlaySync = true
        return
    end
    addon.pendingAlertOverlaySync = false
    if not alertFrame:IsShown() then
        secureTargetBtn:Hide()
        return
    end
    local w, h = alertFrame:GetSize()
    secureTargetBtn:SetSize(math.max(200, (w or 440) - 28), h or 82)
    secureTargetBtn:ClearAllPoints()
    local cx, cy = alertFrame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if cx and cy and ux and uy then
        secureTargetBtn:SetPoint("CENTER", UIParent, "CENTER", cx - ux - 14, cy - uy)
    else
        secureTargetBtn:SetPoint("TOP", UIParent, "TOP", -14, -130)
    end
    secureTargetBtn:Show()
end

secureTargetBtn:SetScript("OnDragStart", function()
    alertFrame:StartMoving()
end)
secureTargetBtn:SetScript("OnDragStop", function()
    alertFrame:StopMovingOrSizing()
    SyncSecureAlertOverlay()
end)
alertFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SyncSecureAlertOverlay()
end)

secureTargetBtn:SetScript("OnEnter", function()
    alertFrame:SetBackdropBorderColor(0.0, 0.95, 1.0, 1.0)
end)
secureTargetBtn:SetScript("OnLeave", function()
    alertFrame:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
end)

function addon:ClearAutoTargetOverrideBinding()
    if self.autoTargetOverrideTimer then
        self.autoTargetOverrideTimer:Cancel()
        self.autoTargetOverrideTimer = nil
    end
    if not self.hasAutoTargetOverride then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingClearAutoTargetOverride = true
        return
    end
    self.pendingClearAutoTargetOverride = false
    self.hasAutoTargetOverride = false
    if ClearOverrideBindings then
        pcall(ClearOverrideBindings, secureTargetBtn)
    end
end

function addon:EnableAutoTargetOverrideBinding(cleanName)
    if not cleanName or cleanName == "" then return end
    if not self.db or not self.db.settings or self.db.settings.autoTargetOnApproach == false then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if SetOverrideBindingClick then
        pcall(SetOverrideBindingClick, secureTargetBtn, true, "MOUSEWHEELUP", "MountCollectorAlertSecureBtn", "LeftButton")
        pcall(SetOverrideBindingClick, secureTargetBtn, true, "MOUSEWHEELDOWN", "MountCollectorAlertSecureBtn", "LeftButton")
        self.hasAutoTargetOverride = true
        if self.autoTargetOverrideTimer then
            self.autoTargetOverrideTimer:Cancel()
        end
        self.autoTargetOverrideTimer = C_Timer.NewTimer(10, function()
            addon:ClearAutoTargetOverrideBinding()
        end)
    end
end

function addon:UpdateAlertSecureTarget(npcName)
    local cleanName = (type(npcName) == "string") and npcName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s*%b()", "") or ""
    if cleanName == "" or cleanName == "Rare NPC" or cleanName == "Неизвестно" or cleanName:find("^NPC #") then
        cleanName = ""
    end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingAlertTargetName = cleanName
        self.pendingAlertOverlaySync = true
        return
    end
    self.pendingAlertTargetName = nil
    secureTargetBtn:SetAttribute("type1", "macro")
    if cleanName ~= "" then
        secureTargetBtn:SetAttribute("macrotext1", "/targetexact " .. cleanName .. "\n/target " .. cleanName)
    else
        secureTargetBtn:SetAttribute("macrotext1", "")
    end
    secureTargetBtn:SetAttribute("type2", "macro")
    secureTargetBtn:SetAttribute("macrotext2", "")
    SyncSecureAlertOverlay()
    if cleanName ~= "" then
        self:EnableAutoTargetOverrideBinding(cleanName)
    else
        self:ClearAutoTargetOverrideBinding()
    end
end

function addon:FlushPendingAlertTarget()
    if InCombatLockdown and InCombatLockdown() then return end
    if self.pendingClearAutoTargetOverride then
        self:ClearAutoTargetOverrideBinding()
    end
    if self.pendingAlertTargetName ~= nil then
        self:UpdateAlertSecureTarget(self.pendingAlertTargetName)
    end
    if self.pendingAlertOverlaySync then
        SyncSecureAlertOverlay()
    end
end

local function HandleAlertClick(_, button)
    addon:ClearAutoTargetOverrideBinding()
    if button == "RightButton" then
        alertFrame:Hide()
    elseif alertFrame.currentMountID then
        addon:SetMountWaypoint(alertFrame.currentMountID, alertFrame.alertMapID, alertFrame.alertX, alertFrame.alertY, alertFrame.alertNpcName, false)
        if IsShiftKeyDown and IsShiftKeyDown() then
            addon:OpenMountInJournal(alertFrame.currentMountID)
        end
    end
end

secureTargetBtn:HookScript("PostClick", function(self, button, down)
    local useKeyDown = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("ActionButtonUseKeyDown")
    if (down and not useKeyDown) or (not down and useKeyDown) then return end
    HandleAlertClick(self, button)
end)

alertFrame:SetScript("OnClick", HandleAlertClick)
alertFrame:SetScript("OnShow", function()
    SyncSecureAlertOverlay()
end)
alertFrame:SetScript("OnHide", function()
    addon:ClearAutoTargetOverrideBinding()
    SyncSecureAlertOverlay()
    if addon.SyncActiveTourAfterKillOrAlert then
        addon:SyncActiveTourAfterKillOrAlert()
    end
end)

function addon:TriggerRareMountAlert(mountID, npcID, npcName, forceShow, mapID, liveX, liveY)
    if not forceShow then
        if not self.db or not self.db.settings.alertRares then return end
        if self.IsPlayerInInstancedContent and self:IsPlayerInInstancedContent() then return end
        if self.IsOpenWorldRareOrWorldBossMount and not self:IsOpenWorldRareOrWorldBossMount(mountID) then return end
    end
    local key = (npcID and npcID > 0 and npcID ~= 99999) and ("npc:" .. tostring(npcID)) or (tostring(npcID or 0) .. ":" .. tostring(mountID or 0))
    local now = GetTime()
    if not forceShow and self.RecentAlertLock[key] and (now - self.RecentAlertLock[key]) < 120 then
        return
    end
    self.RecentAlertLock[key] = now

    local name, _, icon, _, _, _, _, _, _, _, isCollected = self:GetMountInfoByID(mountID)
    if not name or (isCollected and not forceShow) then return end

    -- Если с этого NPC падает сразу несколько несобранных маунтов, объединяем их названия в один алерт и одну метку
    local displayMountNames = name
    if not forceShow and npcID and self.MountsByNpc and self.MountsByNpc[npcID] and #self.MountsByNpc[npcID] > 1 then
        local namesList = {}
        for _, mID in ipairs(self.MountsByNpc[npcID]) do
            local mName, _, _, _, _, _, _, _, _, _, mCol = self:GetMountInfoByID(mID)
            if mName and not mCol then
                table.insert(namesList, mName)
            end
        end
        if #namesList > 1 then
            displayMountNames = table.concat(namesList, ", ")
        end
    end

    local attempts, _, dropInfo = self:GetMountAttempts(mountID)
    local globalPct = self:GetGlobalRarity(mountID)
    local pctText = self:FormatRarityTier(globalPct)
    local chanceStr = (dropInfo and dropInfo.chance) and string.format("1/%d | ", dropInfo.chance) or ""

    local displayNpcName = (npcID and npcID ~= 99999 and self:GetNpcDisplayName(npcID, npcName)) or npcName or "Rare NPC"

    alertFrame.currentMountID = mountID
    alertFrame.alertNpcID = npcID
    alertFrame.alertMapID = mapID
    alertFrame.alertX = liveX
    alertFrame.alertY = liveY
    alertFrame.alertNpcName = displayNpcName

    local clientTargetName = (npcID and self.KnownNpcNames and self.KnownNpcNames[npcID]) or npcName
    self:UpdateAlertSecureTarget(clientTargetName)

    alertIcon:SetTexture(icon or "Interface\\ICONS\\Ability_Mount_SpectralTiger")
    alertHeader:SetText(string.format(L.ALERT_HEADER_NEARBY, displayNpcName))
    alertMountName:SetText(string.format(L.ALERT_NOT_COLLECTED, displayMountNames))
    alertStats:SetText(string.format(L.ALERT_STATS_LINE, attempts, chanceStr, pctText))

    local h1 = alertHeader:GetStringHeight() or 16
    local h2 = alertMountName:GetStringHeight() or 16
    local h3 = alertStats:GetStringHeight() or 16
    local contentH = math.max(74, 10 + h1 + 4 + h2 + 4 + h3 + 12)
    alertFrame:SetHeight(contentH)

    local shouldShowBanner = forceShow or (not self.db or not self.db.settings or self.db.settings.showAlertBanner ~= false)
    if shouldShowBanner then
        alertFrame:Show()
        SyncSecureAlertOverlay()
    else
        alertFrame:Hide()
    end

    if self.db and self.db.settings.alertSound and PlaySound then
        PlaySound(8959, "Master")
    end

    if self.db and self.db.settings.autoWaypoint then
        self:SetMountWaypoint(mountID, mapID, liveX, liveY, npcName, false, displayMountNames)
    end

    if self.alertHideTimer then
        self.alertHideTimer:Cancel()
    end
    self.alertHideTimer = C_Timer.NewTimer(15, function()
        addon:ClearAutoTargetOverrideBinding()
        if alertFrame:IsShown() then
            alertFrame:Hide()
        end
    end)
end

-- ============================================================================
