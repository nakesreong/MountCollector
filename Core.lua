local addonName, addon = ...
_G.MountCollector = addon

local L = addon.L
local LibStub = _G.LibStub
local MountsRarity = LibStub and LibStub("MountsRarity-2.0", true)

addon.MountBySpell = {}
addon.MountByItem = {}
addon.DropInfoByMount = {}
addon.MountsByNpc = {}
addon.MountsByMap = {}
addon.RecentAttemptLock = {}
addon.RecentAlertLock = {}

-- Оценка активного онлайна (персонажей максимального уровня за 30 дней) по RU/EU/US-серверам
-- Используется вместе с глобальной рарностью Data for Azeroth (MountsRarity-2.0) + живым локальным сканером сервера
addon.RealmPopulations = {
    -- RU Realms
    ["Свежеватель Душ"] = 21500,
    ["Ревущий фьорд"] = 24800,
    ["Гордунни"] = 23400,
    ["Дракономор"] = 6500,
    ["Ясеневый лес"] = 5200,
    ["Страж Смерти"] = 4800,
    ["Черный Шрам"] = 5100,
    ["Борейская тундра"] = 4900,
    ["Вечная Песня"] = 6200,
    ["Галакронд"] = 5800,
    ["Голдринн"] = 4100,
    -- Major EU / US Realms
    ["Silvermoon"] = 28500,
    ["Draenor"] = 29200,
    ["Kazzak"] = 26400,
    ["Tarren Mill"] = 24900,
    ["Twisting Nether"] = 23800,
    ["Ravencrest"] = 21200,
    ["Argent Dawn"] = 22500,
    ["Area 52"] = 31000,
    ["Illidan"] = 29800,
    ["Stormrage"] = 28900,
    ["Tichondrius"] = 22400,
}
addon.DefaultRealmPopulation = 14000

local function SafeNotSecret(val)
    if val == nil then return false end
    if _G.issecretvalue and _G.issecretvalue(val) then
        return false
    end
    return true
end

addon.SafeNotSecret = SafeNotSecret

function addon:GetCharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Realm"
    return name .. " - " .. realm
end

function addon:GetNPCIDFromGUID(guid)
    if not SafeNotSecret(guid) or type(guid) ~= "string" then
        return nil
    end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" or unitType == "Vignette" then
        return tonumber(npcID)
    end
    return nil
end

function addon:InitDB()
    if type(_G.MountCollectorDB) ~= "table" then
        _G.MountCollectorDB = {}
    end
    local db = _G.MountCollectorDB
    db.attempts = db.attempts or {}
    db.realmCensus = db.realmCensus or {}
    db.minimap = db.minimap or { hide = false }
    db.settings = db.settings or {}

    local defaults = {
        language = "auto",
        showInTooltips = true,
        showInJournalRowHover = true,
        showInMountDisplay = true,
        showGlobalRarity = true,
        showServerRarity = true,
        showAttempts = true,
        alertRares = true,
        alertSound = true,
        showNpcTooltip = true,
        announceAttempts = true,
    }
    for k, v in pairs(defaults) do
        if db.settings[k] == nil then
            db.settings[k] = v
        end
    end

    self.db = db
end

-- Получение глобальной рарности из проверенной либы MountsRarity-2.0 (Data for Azeroth)
function addon:GetGlobalRarity(mountID)
    if not mountID then return nil end
    if not MountsRarity and LibStub then
        MountsRarity = LibStub("MountsRarity-2.0", true)
    end
    if MountsRarity and MountsRarity.GetRarityByID then
        local ok, val = pcall(MountsRarity.GetRarityByID, MountsRarity, mountID)
        if ok and type(val) == "number" then
            return val
        end
    end
    return nil
end

-- Окраска и тир редкости маунта (с поддержкой локализации L)
function addon:FormatRarityTier(rarityPct)
    if type(rarityPct) ~= "number" then
        return L.NO_DATA, L.TIER_UNKNOWN, "|cff999999"
    end
    if rarityPct < 1.0 then
        return string.format("|cffff8000%.2f%%|r", rarityPct), L.TIER_MYTHIC, "|cffff8000"
    elseif rarityPct < 3.0 then
        return string.format("|cffff5500%.2f%%|r", rarityPct), L.TIER_ULTRA, "|cffff5500"
    elseif rarityPct < 10.0 then
        return string.format("|cffa335ee%.2f%%|r", rarityPct), L.TIER_EPIC, "|cffa335ee"
    elseif rarityPct < 25.0 then
        return string.format("|cff0070dd%.1f%%|r", rarityPct), L.TIER_RARE, "|cff0070dd"
    elseif rarityPct < 50.0 then
        return string.format("|cff1eff00%.1f%%|r", rarityPct), L.TIER_UNCOMMON, "|cff1eff00"
    else
        return string.format("|cffffffff%.1f%%|r", rarityPct), L.TIER_COMMON, "|cffffffff"
    end
end

-- Оценка рарности на текущем сервере (например, Свежеватель Душ) + живые встречи
function addon:GetServerRarityInfo(mountID)
    local realm = GetRealmName() or "Realm"
    local realmPop = self.RealmPopulations[realm] or self.DefaultRealmPopulation
    local globalPct = self:GetGlobalRarity(mountID)

    local seenCount = 0
    if self.db and self.db.realmCensus and self.db.realmCensus[realm] and self.db.realmCensus[realm][mountID] then
        seenCount = self.db.realmCensus[realm][mountID].count or 0
    end

    local estOwners = nil
    if type(globalPct) == "number" then
        estOwners = math.max(seenCount, math.floor((globalPct / 100.0) * realmPop + 0.5))
    end

    return realm, realmPop, estOwners, seenCount, globalPct
end

-- Построение единого индекса маунтов, боссов, рарников и карт (MountDropsDB + Rarity + RareScanner + C_MountJournal)
function addon:BuildMountIndex()
    if not C_MountJournal or not C_MountJournal.GetMountIDs then return end

    wipe(self.MountBySpell)
    wipe(self.MountByItem)
    wipe(self.DropInfoByMount)
    wipe(self.MountsByNpc)
    wipe(self.MountsByMap)

    local mountIDs = C_MountJournal.GetMountIDs()
    if not mountIDs then return end

    for _, mountID in ipairs(mountIDs) do
        local name, spellID = C_MountJournal.GetMountInfoByID(mountID)
        if spellID and SafeNotSecret(spellID) then
            self.MountBySpell[spellID] = mountID

            local dropData = self.MountDropsBySpell and self.MountDropsBySpell[spellID]
            if dropData then
                local info = {
                    mountID = mountID,
                    name = name,
                    spellID = spellID,
                    itemID = dropData.itemId,
                    chance = dropData.chance or 100,
                    method = dropData.method or "NPC",
                    boss = dropData.boss ~= "" and dropData.boss or nil,
                    npcs = {},
                    stats = dropData.stats or {},
                    quests = dropData.quests or {},
                    maps = dropData.maps or {},
                    rarityKey = dropData.rarityKey,
                }
                if dropData.itemId and dropData.itemId > 0 then
                    self.MountByItem[dropData.itemId] = mountID
                end
                for _, nid in ipairs(dropData.npcs or {}) do
                    info.npcs[nid] = true
                    self.MountsByNpc[nid] = self.MountsByNpc[nid] or {}
                    table.insert(self.MountsByNpc[nid], mountID)
                end
                for _, mid in ipairs(dropData.maps or {}) do
                    self.MountsByMap[mid] = self.MountsByMap[mid] or {}
                    table.insert(self.MountsByMap[mid], mountID)
                end
                self.DropInfoByMount[mountID] = info
            end
        end
    end

    -- Дополняем индекс из таблиц RareScanner (если есть маунты, привязанные через itemID)
    if self.RareScannerNpcToItems and C_MountJournal.GetMountFromItem then
        for npcID, itemIDs in pairs(self.RareScannerNpcToItems) do
            for _, itemID in ipairs(itemIDs) do
                local mountID = self.MountByItem[itemID] or C_MountJournal.GetMountFromItem(itemID)
                if mountID then
                    self.MountByItem[itemID] = mountID
                    local info = self.DropInfoByMount[mountID]
                    if not info then
                        local name, spellID = C_MountJournal.GetMountInfoByID(mountID)
                        info = {
                            mountID = mountID,
                            name = name,
                            spellID = spellID,
                            itemID = itemID,
                            chance = 50,
                            method = "NPC",
                            npcs = {},
                            stats = {},
                            quests = {},
                            maps = {},
                        }
                        self.DropInfoByMount[mountID] = info
                    end
                    if not info.npcs[npcID] then
                        info.npcs[npcID] = true
                        self.MountsByNpc[npcID] = self.MountsByNpc[npcID] or {}
                        table.insert(self.MountsByNpc[npcID], mountID)
                    end
                end
            end
        end
    end

    -- Живая интеграция с Rarity (если установлен и загружен Rarity)
    if _G.Rarity and _G.Rarity.db and _G.Rarity.db.profile and _G.Rarity.db.profile.groups and _G.Rarity.db.profile.groups.mounts then
        for rKey, rEntry in pairs(_G.Rarity.db.profile.groups.mounts) do
            if type(rEntry) == "table" and rEntry.spellId then
                local mountID = self.MountBySpell[rEntry.spellId]
                if mountID then
                    local info = self.DropInfoByMount[mountID]
                    if not info then
                        local name = C_MountJournal.GetMountInfoByID(mountID)
                        info = {
                            mountID = mountID,
                            name = name,
                            spellID = rEntry.spellId,
                            itemID = rEntry.itemId,
                            chance = rEntry.chance or 100,
                            method = rEntry.method or "NPC",
                            boss = rEntry.lockBossName,
                            npcs = {},
                            stats = type(rEntry.statisticId) == "table" and rEntry.statisticId or {},
                            quests = {},
                            maps = {},
                            rarityKey = rKey,
                        }
                        self.DropInfoByMount[mountID] = info
                    end
                    info.rarityEntry = rEntry
                    info.rarityKey = rKey
                    for _, field in ipairs({ "npcs", "tooltipNpcs" }) do
                        if type(rEntry[field]) == "table" then
                            for _, nid in ipairs(rEntry[field]) do
                                if nid ~= 99999 and not info.npcs[nid] then
                                    info.npcs[nid] = true
                                    self.MountsByNpc[nid] = self.MountsByNpc[nid] or {}
                                    table.insert(self.MountsByNpc[nid], mountID)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Получение и синхронизация количества траев по всем персонажам аккаунта (MountCollectorDB + Rarity + Blizzard Statistics)
function addon:GetMountAttempts(mountID)
    if not mountID or not self.db then return 0, nil, nil end
    local info = self.DropInfoByMount[mountID]
    local record = self.db.attempts[mountID]

    local mcTotal = 0
    local byCharSum = 0
    if record then
        mcTotal = record.total or 0
        if record.byChar then
            for _, c in pairs(record.byChar) do
                byCharSum = byCharSum + (tonumber(c) or 0)
            end
        end
        if byCharSum > mcTotal then
            mcTotal = byCharSum
            record.total = mcTotal
        end
    end

    local rarityAttempts = 0
    if info then
        local rEntry = info.rarityEntry
        if not rEntry and info.rarityKey and _G.Rarity and _G.Rarity.db and _G.Rarity.db.profile and _G.Rarity.db.profile.groups and _G.Rarity.db.profile.groups.mounts then
            rEntry = _G.Rarity.db.profile.groups.mounts[info.rarityKey]
            info.rarityEntry = rEntry
        end
        if rEntry and type(rEntry.attempts) == "number" then
            rarityAttempts = rEntry.attempts
        end

        local statSum = 0
        if info.stats and #info.stats > 0 and GetStatistic then
            for _, statID in ipairs(info.stats) do
                local val = GetStatistic(statID)
                if val and SafeNotSecret(val) then
                    local num = tonumber(val)
                    if num and num > 0 then
                        statSum = statSum + num
                    end
                end
            end
        end
        if statSum > rarityAttempts then
            rarityAttempts = statSum
        end
    end

    local finalAttempts = math.max(mcTotal, rarityAttempts)
    if finalAttempts > 0 and finalAttempts > mcTotal then
        record = record or { total = 0, byChar = {} }
        record.total = finalAttempts
        self.db.attempts[mountID] = record
    end

    return finalAttempts, record and record.byChar or nil, info
end

-- Запись нового трая (убийства босса / рарника) на аккаунт
function addon:RecordAttempt(mountID, sourceName)
    if not mountID or not self.db then return end
    local name, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    if isCollected then return end

    local now = GetTime()
    if self.RecentAttemptLock[mountID] and (now - self.RecentAttemptLock[mountID]) < 30 then
        return
    end
    self.RecentAttemptLock[mountID] = now

    local prevTotal = self:GetMountAttempts(mountID)
    local record = self.db.attempts[mountID] or { total = prevTotal, byChar = {} }
    local charKey = self:GetCharKey()

    record.byChar[charKey] = (record.byChar[charKey] or 0) + 1
    record.total = math.max((record.total or 0) + 1, prevTotal + 1)
    record.lastKill = time()
    record.lastChar = charKey
    self.db.attempts[mountID] = record

    local info = self.DropInfoByMount[mountID]
    local chance = (info and info.chance and info.chance > 0) and info.chance or 100
    local luckPct = (1 - math.pow(1 - (1 / chance), record.total)) * 100

    if self.db.settings.announceAttempts then
        print(string.format(
            L.CHAT_ATTEMPT_RECORDED,
            record.total,
            name or "Mount",
            sourceName or "NPC",
            chance,
            record.total,
            luckPct
        ))
    end

    if self.UpdateLDBText then
        self:UpdateLDBText()
    end
    if self.RefreshRadarUI then
        self:RefreshRadarUI()
    end
end

-- Проверка квест-лок-аута рарника (убит ли сегодня/на этой неделе текущим персонажем)
function addon:IsMountRareLockedToday(mountID)
    local info = self.DropInfoByMount[mountID]
    if not info or not info.quests or #info.quests == 0 then
        return false
    end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        for _, qid in ipairs(info.quests) do
            if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                return true
            end
        end
    end
    return false
end

-- Живое сканирование игроков вокруг на текущем сервере
function addon:ScanUnitMount(unit)
    if not unit or not SafeNotSecret(unit) then return end
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return end

    local unitName, unitRealm = UnitName(unit)
    if not SafeNotSecret(unitName) or not unitName then return end
    local realm = (SafeNotSecret(unitRealm) and unitRealm and unitRealm ~= "") and unitRealm or (GetRealmName() or "Realm")

    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then break end
        local spellId = aura.spellId
        if SafeNotSecret(spellId) and spellId then
            local mountID = self.MountBySpell[spellId]
            if mountID then
                self.db.realmCensus[realm] = self.db.realmCensus[realm] or {}
                local entry = self.db.realmCensus[realm][mountID]
                if not entry then
                    entry = { count = 0, players = {} }
                    self.db.realmCensus[realm][mountID] = entry
                end
                if not entry.players[unitName] then
                    entry.players[unitName] = time()
                    entry.count = (entry.count or 0) + 1
                else
                    entry.players[unitName] = time()
                end
                break
            end
        end
    end
end

function addon:CheckUnitForMountDrop(unit)
    if not unit or not SafeNotSecret(unit) or not UnitExists(unit) then return end
    if UnitIsPlayer(unit) then
        self:ScanUnitMount(unit)
        return
    end
    if UnitIsDead(unit) then return end

    local guid = UnitGUID(unit)
    local npcID = self:GetNPCIDFromGUID(guid)
    if not npcID then return end

    local mounts = self.MountsByNpc[npcID]
    if not mounts then return end

    local npcName = UnitName(unit)
    if not SafeNotSecret(npcName) then npcName = "Rare NPC" end

    for _, mountID in ipairs(mounts) do
        local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if not isCollected then
            self:TriggerRareMountAlert(mountID, npcID, npcName)
        end
    end
end

function addon:CheckVignetteForMountDrop(vignetteGUID)
    if not vignetteGUID or not SafeNotSecret(vignetteGUID) then return end
    if not C_VignetteInfo or not C_VignetteInfo.GetVignetteInfo then return end
    local vInfo = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
    if not vInfo or not SafeNotSecret(vInfo.objectGUID) then return end

    local npcID = self:GetNPCIDFromGUID(vInfo.objectGUID)
    if not npcID then return end

    local mounts = self.MountsByNpc[npcID]
    if not mounts then return end

    local vName = SafeNotSecret(vInfo.name) and vInfo.name or "Rare NPC"
    for _, mountID in ipairs(mounts) do
        local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if not isCollected then
            self:TriggerRareMountAlert(mountID, npcID, vName)
        end
    end
end

function addon:GetZoneUncollectedMounts()
    local results = {}
    if not C_Map or not C_Map.GetBestMapForUnit then return results end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return results end

    local seen = {}
    local function addMapMounts(mid)
        local list = self.MountsByMap[mid]
        if not list then return end
        for _, mountID in ipairs(list) do
            if not seen[mountID] then
                seen[mountID] = true
                local name, spellID, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                if name and not isCollected then
                    local attempts, _, info = self:GetMountAttempts(mountID)
                    local globalRarity = self:GetGlobalRarity(mountID)
                    table.insert(results, {
                        mountID = mountID,
                        name = name,
                        spellID = spellID,
                        icon = icon,
                        attempts = attempts,
                        chance = info and info.chance or 100,
                        boss = info and info.boss or nil,
                        method = info and info.method or "NPC",
                        globalRarity = globalRarity,
                        locked = self:IsMountRareLockedToday(mountID),
                    })
                end
            end
        end
    end

    addMapMounts(mapID)
    if C_Map.GetMapInfo then
        local mapInfo = C_Map.GetMapInfo(mapID)
        if mapInfo and mapInfo.parentMapID and mapInfo.parentMapID > 0 then
            addMapMounts(mapInfo.parentMapID)
        end
    end

    table.sort(results, function(a, b)
        if a.locked ~= b.locked then
            return not a.locked
        end
        return (a.attempts or 0) > (b.attempts or 0)
    end)

    return results, mapID
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("NEW_MOUNT_ADDED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == addonName then
            addon:InitDB()
            if addon.InitLDB then
                addon:InitLDB()
            end
        elseif loadedName == "Blizzard_Collections" then
            if addon.HookMountJournal then
                addon:HookMountJournal()
            end
        elseif loadedName == "Rarity" then
            addon:BuildMountIndex()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.5, function()
            addon:BuildMountIndex()
            if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Collections") then
                if addon.HookMountJournal then
                    addon:HookMountJournal()
                end
            end
            if addon.UpdateLDBText then
                addon:UpdateLDBText()
            end
        end)
    elseif event == "NEW_MOUNT_ADDED" then
        addon:BuildMountIndex()
        if addon.UpdateLDBText then
            addon:UpdateLDBText()
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if addon.UpdateLDBText then
            addon:UpdateLDBText()
        end
        if addon.RefreshRadarUI then
            addon:RefreshRadarUI()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        addon:CheckUnitForMountDrop("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        addon:CheckUnitForMountDrop("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        addon:CheckUnitForMountDrop(unit)
    elseif event == "VIGNETTE_MINIMAP_UPDATED" then
        local vignetteGUID = ...
        addon:CheckVignetteForMountDrop(vignetteGUID)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not CombatLogGetCurrentEventInfo then return end
        local _, subEvent, _, _, _, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()
        if subEvent == "UNIT_DIED" or subEvent == "PARTY_KILL" then
            local npcID = addon:GetNPCIDFromGUID(destGUID)
            if npcID and addon.MountsByNpc[npcID] then
                for _, mountID in ipairs(addon.MountsByNpc[npcID]) do
                    addon:RecordAttempt(mountID, SafeNotSecret(destName) and destName or "NPC")
                end
            end
        end
    elseif event == "ENCOUNTER_END" then
        local _, encounterName, _, _, success = ...
        if success == 1 and SafeNotSecret(encounterName) and encounterName then
            for mountID, info in pairs(addon.DropInfoByMount) do
                if info.boss and (info.boss == encounterName or string.find(encounterName, info.boss, 1, true)) then
                    addon:RecordAttempt(mountID, encounterName)
                end
            end
        end
    end
end)
