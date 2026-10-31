local addonName, addon = ...
_G.MountCollector = addon

-- ============================================================================
-- MountCollector — Core.lua
-- Ядро аддона:
--   1. Индексация маунтов, боссов, рарников, предметов и квестовых цепочек
--      (MountDropsDB + RareScanner + Rarity + MountQuestsDB + MountsRarity-2.0)
--   2. Оценка глобальной рарности (Data for Azeroth) и серверной популяции
--   3. Учёт попыток (траев) по аккаунту и персонажам + расчёт вероятности
--   4. Трекинг прогресса многошаговых квестовых цепочек и авто-навигация TomTom
--   5. Защита от WoW 12.1.5 (Midnight) Secret Aura / Secret Value Taint
-- ============================================================================

local L = addon.L
local LibStub = _G.LibStub
local MountsRarity = LibStub and LibStub("MountsRarity-2.0", true)

addon.MountBySpell = {}
addon.MountByItem = {}
addon.MountsBySourceItem = {}
addon.DropInfoByMount = {}
addon.MountQuestsByMountID = {}
addon.MountDungeonsByMountID = {}
addon.MountsByNpc = {}
addon.MountsByMap = {}
addon.RecentAttemptLock = {}
addon.RecentAlertLock = {}

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

local function IsValidNpcName(name)
    if not SafeNotSecret(name) or type(name) ~= "string" or name == "" then
        return false
    end
    if _G.UNKNOWNOBJECT and name == _G.UNKNOWNOBJECT then
        return false
    end
    if _G.UNKNOWN and name == _G.UNKNOWN then
        return false
    end
    local lower = string.lower(name)
    if lower == "неизвестно" or lower == "unknown" or lower == "rare npc" then
        return false
    end
    return true
end

addon.IsValidNpcName = IsValidNpcName

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
    db.chars = db.chars or {}
    db.realmCensus = db.realmCensus or {}
    db.knownNpcNames = db.knownNpcNames or {}
    db.minimap = db.minimap or { hide = false }
    db.settings = db.settings or {}

    for k, v in pairs(db.knownNpcNames) do
        if not IsValidNpcName(v) then
            db.knownNpcNames[k] = nil
        end
    end
    if not db.knownNpcNames[250780] then
        db.knownNpcNames[250780] = "Волнуш"
    end
    self.KnownNpcNames = db.knownNpcNames

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
        autoWaypoint = true,
        showWorldMapPins = true,
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

local function AddUniqueToList(list, val)
    for _, v in ipairs(list) do
        if v == val then return end
    end
    table.insert(list, val)
end

-- Построение единого индекса маунтов, предметов для маунтов, боссов, рарников и координат
function addon:BuildMountIndex()
    if not C_MountJournal or not C_MountJournal.GetMountIDs then return end

    wipe(self.MountBySpell)
    wipe(self.MountByItem)
    wipe(self.MountsBySourceItem)
    wipe(self.DropInfoByMount)
    wipe(self.MountQuestsByMountID)
    wipe(self.MountDungeonsByMountID)
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
                    quests = {},
                    maps = {},
                    coords = {},
                    rarityKey = dropData.rarityKey,
                }
                for _, qid in ipairs(dropData.quests or {}) do
                    AddUniqueToList(info.quests, qid)
                end
                for _, c in ipairs(dropData.coords or {}) do
                    table.insert(info.coords, c)
                end
                if dropData.itemId and dropData.itemId > 0 then
                    self.MountByItem[dropData.itemId] = mountID
                end
                for _, srcItemID in ipairs(dropData.sourceItems or {}) do
                    if srcItemID and srcItemID > 0 then
                        self.MountByItem[srcItemID] = mountID
                        self.MountsBySourceItem[srcItemID] = self.MountsBySourceItem[srcItemID] or {}
                        AddUniqueToList(self.MountsBySourceItem[srcItemID], mountID)
                    end
                end
                for _, nid in ipairs(dropData.npcs or {}) do
                    info.npcs[nid] = true
                    self.MountsByNpc[nid] = self.MountsByNpc[nid] or {}
                    AddUniqueToList(self.MountsByNpc[nid], mountID)
                end
                for _, mid in ipairs(dropData.maps or {}) do
                    AddUniqueToList(info.maps, mid)
                    self.MountsByMap[mid] = self.MountsByMap[mid] or {}
                    AddUniqueToList(self.MountsByMap[mid], mountID)
                end
                self.DropInfoByMount[mountID] = info
            end
        end
    end

    -- 2. Привязываем все предметы и штуки для маунтов из RareScannerMountItems (mountID -> { itemID1, itemID2... })
    if self.RareScannerMountItems then
        for mountID, itemList in pairs(self.RareScannerMountItems) do
            for _, itemID in ipairs(itemList) do
                if not self.MountByItem[itemID] then
                    self.MountByItem[itemID] = mountID
                end
            end
        end
    end

    -- 3. Дополняем рарниками, квест-локами и точными координатами спавна из RareScannerNpcToMounts
    if self.RareScannerNpcToMounts then
        for npcID, rsData in pairs(self.RareScannerNpcToMounts) do
            for _, mountID in ipairs(rsData.mounts or {}) do
                local name, spellID = C_MountJournal.GetMountInfoByID(mountID)
                if name then
                    local info = self.DropInfoByMount[mountID]
                    if not info then
                        info = {
                            mountID = mountID,
                            name = name,
                            spellID = spellID,
                            chance = nil,
                            method = "NPC",
                            boss = (rsData.name and rsData.name ~= "") and rsData.name or nil,
                            npcs = {},
                            stats = {},
                            quests = {},
                            maps = {},
                            coords = {},
                        }
                        self.DropInfoByMount[mountID] = info
                    elseif not info.boss and rsData.name and rsData.name ~= "" then
                        info.boss = rsData.name
                    end

                    info.npcs[npcID] = true
                    self.MountsByNpc[npcID] = self.MountsByNpc[npcID] or {}
                    AddUniqueToList(self.MountsByNpc[npcID], mountID)

                    for _, qid in ipairs(rsData.quests or {}) do
                        AddUniqueToList(info.quests, qid)
                    end
                    for _, c in ipairs(rsData.coords or {}) do
                        if c.m and c.m > 0 and c.m < 5000 then
                            AddUniqueToList(info.maps, c.m)
                            self.MountsByMap[c.m] = self.MountsByMap[c.m] or {}
                            AddUniqueToList(self.MountsByMap[c.m], mountID)
                            if c.x and c.x > 0 and c.y and c.y > 0 then
                                table.insert(info.coords, {
                                    m = c.m,
                                    x = c.x,
                                    y = c.y,
                                    n = rsData.name or info.boss or name,
                                    npcID = npcID,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    -- 4. Живая синхронизация с Rarity (если Rarity включён)
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
                            coords = {},
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
                                    AddUniqueToList(self.MountsByNpc[nid], mountID)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 5. Индексируем квестовые цепочки и инкубацию яиц из MountQuestsDB
    if type(self.MountQuestsDB) == "table" then
        for _, qChain in ipairs(self.MountQuestsDB) do
            local mID = (qChain.spellID and self.MountBySpell[qChain.spellID])
                or (qChain.itemID and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(qChain.itemID))
                or (qChain.spellID and C_MountJournal.GetMountFromSpell and C_MountJournal.GetMountFromSpell(qChain.spellID))
                or (qChain.itemID and self.MountByItem[qChain.itemID])
                or qChain.mountID
            if mID and C_MountJournal.GetMountInfoByID(mID) then
                qChain.resolvedMountID = mID
                self.MountQuestsByMountID[mID] = qChain
            end
        end
    end

    -- 6. Индексируем данж-лут, рейдовых боссов и праздничные события из MountDungeonsDB
    if type(self.MountDungeonsDB) == "table" then
        for _, dEntry in ipairs(self.MountDungeonsDB) do
            local mID = (dEntry.spellID and self.MountBySpell[dEntry.spellID])
                or (dEntry.itemID and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(dEntry.itemID))
                or (dEntry.spellID and C_MountJournal.GetMountFromSpell and C_MountJournal.GetMountFromSpell(dEntry.spellID))
                or (dEntry.itemID and self.MountByItem[dEntry.itemID])
                or dEntry.mountID
            if mID and C_MountJournal.GetMountInfoByID(mID) then
                dEntry.resolvedMountID = mID
                self.MountDungeonsByMountID[mID] = dEntry

                local info = self.DropInfoByMount[mID]
                if not info then
                    local name, spellID = C_MountJournal.GetMountInfoByID(mID)
                    info = {
                        mountID = mID,
                        name = name,
                        spellID = spellID or dEntry.spellID,
                        itemID = dEntry.itemID,
                        chance = dEntry.chance or 100,
                        method = (dEntry.sourceKind == "EVENT") and "SPECIAL" or "BOSS",
                        boss = dEntry.bossEN or dEntry.bossRU,
                        bossRU = dEntry.bossRU,
                        bossEN = dEntry.bossEN,
                        npcs = {},
                        stats = {},
                        quests = {},
                        maps = {},
                        coords = {},
                    }
                    self.DropInfoByMount[mID] = info
                else
                    if not info.chance and dEntry.chance then
                        info.chance = dEntry.chance
                    end
                    if not info.boss and (dEntry.bossEN or dEntry.bossRU) then
                        info.boss = dEntry.bossEN or dEntry.bossRU
                    end
                    info.bossRU = dEntry.bossRU or info.bossRU
                    info.bossEN = dEntry.bossEN or info.bossEN
                end
                if dEntry.itemID and dEntry.itemID > 0 and not self.MountByItem[dEntry.itemID] then
                    self.MountByItem[dEntry.itemID] = mID
                end
                if dEntry.mapID and dEntry.x and dEntry.y and #info.coords == 0 then
                    table.insert(info.coords, {
                        m = dEntry.mapID,
                        x = dEntry.x,
                        y = dEntry.y,
                        n = dEntry.instanceEN or dEntry.instanceRU or info.boss or info.name,
                    })
                end
            end
        end
    end
end

-- Получить локализованное название квеста по его questID (из клиента или QuestNameDB)
function addon:GetQuestTitleByID(questID)
    if not questID or questID <= 0 then return nil end
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and SafeNotSecret(title) and type(title) == "string" and title ~= "" then
            return title
        end
    end
    if C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
        local ok, title = pcall(C_TaskQuest.GetQuestInfoByQuestID, questID)
        if ok and SafeNotSecret(title) and type(title) == "string" and title ~= "" then
            return title
        end
    end
    if self.QuestNameDB and self.QuestNameDB[questID] then
        local isRU = (self:GetActiveLocaleCode() == "ruRU")
        return (isRU and self.QuestNameDB[questID].ru) or self.QuestNameDB[questID].en
    end
    return nil
end

-- Получить прогресс целей активного квеста из журнала (например: "25/50 Люменит")
function addon:GetQuestObjectivesText(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetQuestObjectives then return nil end
    local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objs) ~= "table" or #objs == 0 then return nil end
    local parts = {}
    for _, obj in ipairs(objs) do
        if obj and SafeNotSecret(obj.text) and type(obj.text) == "string" and obj.text ~= "" then
            table.insert(parts, obj.text)
        end
    end
    if #parts > 0 then
        return table.concat(parts, "; ")
    end
    return nil
end

-- Получить количество предмета в сумках/банке или статус игрушки
function addon:GetRequirementItemCount(itemID)
    if not itemID or itemID <= 0 then return 0, nil end
    local itemName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ("Item #" .. tostring(itemID))
    if PlayerHasToy and PlayerHasToy(itemID) then
        return 1, itemName
    end
    local count = 0
    if C_Item and C_Item.GetItemCount then
        local ok, c = pcall(C_Item.GetItemCount, itemID, true, false, true)
        if ok and type(c) == "number" then
            count = c
        end
    elseif GetItemCount then
        count = GetItemCount(itemID, true) or 0
    end
    return count, itemName
end

-- Оценка статуса пошаговой квестовой цепочки маунта через Lua API
function addon:GetMountQuestChainStatus(mountID)
    local chain = self.MountQuestsByMountID and self.MountQuestsByMountID[mountID]
    if not chain or type(chain.steps) ~= "table" then return nil end

    local isRU = (self:GetActiveLocaleCode() == "ruRU")
    local name, spellID, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    local totalSteps = #chain.steps
    local stepStates = {}

    for idx, s in ipairs(chain.steps) do
        local isDone = false
        local isDoneAccountOnly = false
        local inLog = false
        local doneSub = 0
        local totalSub = (type(s.quests) == "table") and #s.quests or 0
        local activeLogQuestID = nil
        local activeLogQuestTitle = nil
        local activeLogObjectives = nil
        local nextMissingQuestID = nil
        local nextMissingQuestTitle = nil
        local itemStatusLine = nil

        if isCollected then
            isDone = true
            doneSub = totalSub
        else
            if s.doneQuest and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
                if C_QuestLog.IsQuestFlaggedCompleted(s.doneQuest) then
                    isDone = true
                elseif s.accountShared and C_QuestLog.IsQuestFlaggedCompletedOnAccount and C_QuestLog.IsQuestFlaggedCompletedOnAccount(s.doneQuest) then
                    isDone = true
                    isDoneAccountOnly = true
                end
            end
            if not isDone and s.achievementID and GetAchievementInfo then
                local okAch, _, _, _, completed, _, _, _, _, _, _, _, _, completedByMe = pcall(GetAchievementInfo, s.achievementID)
                if okAch and completed then
                    isDone = true
                    if not completedByMe then
                        isDoneAccountOnly = true
                    end
                end
            end

            if s.requiredItemID then
                local haveCount, itemName = self:GetRequirementItemCount(s.requiredItemID)
                local goalCount = s.requiredItemCount or 1
                if haveCount >= goalCount and not s.doneQuest and not s.achievementID and totalSub == 0 then
                    isDone = true
                end
                if not isDone then
                    if s.altItemID and haveCount == 0 then
                        local altCount, altName = self:GetRequirementItemCount(s.altItemID)
                        local altGoal = s.altItemGoal or 10
                        itemStatusLine = string.format(L.LUA_ITEMS_BAGS_ALT_FMT, itemName, haveCount, goalCount, altName, altCount, altGoal)
                    else
                        itemStatusLine = string.format(L.LUA_ITEM_BAGS_FMT, itemName, haveCount, goalCount)
                    end
                end
            end

            if type(s.quests) == "table" and C_QuestLog then
                for _, qid in ipairs(s.quests) do
                    local qDone = C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid)
                    local qInLog = C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(qid)
                    if qDone then
                        doneSub = doneSub + 1
                    else
                        if qInLog then
                            inLog = true
                            if not activeLogQuestID then
                                activeLogQuestID = qid
                                activeLogQuestTitle = self:GetQuestTitleByID(qid)
                                activeLogObjectives = self:GetQuestObjectivesText(qid)
                            end
                        end
                        if not nextMissingQuestID then
                            nextMissingQuestID = qid
                            nextMissingQuestTitle = self:GetQuestTitleByID(qid)
                        end
                    end
                end
                if not s.doneQuest and not s.achievementID and totalSub > 0 and doneSub >= totalSub then
                    isDone = true
                end
            end

            -- Если сам маунт ещё НЕ собран, то финальный шаг получения маунта не может считаться завершённым
            if idx == totalSteps then
                isDone = false
                isDoneAccountOnly = false
            end
        end

        local luaStepDetail = nil
        if not isDone then
            local detailParts = {}
            if activeLogQuestID then
                local qTitle = activeLogQuestTitle or ("Quest #" .. tostring(activeLogQuestID))
                local objPart = activeLogObjectives and (" — |cff00ff96" .. activeLogObjectives .. "|r") or ""
                table.insert(detailParts, string.format(L.LUA_IN_LOG_FMT, qTitle, activeLogQuestID, objPart))
            elseif nextMissingQuestID then
                local qTitle = nextMissingQuestTitle or ("Quest #" .. tostring(nextMissingQuestID))
                local subProg = (totalSub > 1) and string.format(L.LUA_CHAPTER_SUB_FMT, doneSub, totalSub) or ""
                table.insert(detailParts, string.format(L.LUA_NEXT_QUEST_FMT, qTitle, nextMissingQuestID, subProg))
            end
            if itemStatusLine then
                table.insert(detailParts, itemStatusLine)
            end
            if #detailParts > 0 then
                luaStepDetail = table.concat(detailParts, "\n")
            end
        end

        local stepZone = (isRU and s.zoneRU) or s.zoneEN or ""
        local locCode = self:GetActiveLocaleCode()
        if locCode ~= "ruRU" and locCode ~= "enUS" and locCode ~= "enGB" and s.mapID and C_Map and C_Map.GetMapInfo then
            local mInfo = C_Map.GetMapInfo(s.mapID)
            if mInfo and mInfo.name and mInfo.name ~= "" then
                stepZone = mInfo.name
            end
        end

        stepStates[idx] = {
            index = idx,
            step = s,
            isDone = isDone,
            isDoneAccountOnly = isDoneAccountOnly,
            accountShared = s.accountShared == true,
            inLog = inLog,
            doneSubCount = doneSub,
            totalSubCount = totalSub,
            activeLogQuestID = activeLogQuestID,
            nextMissingQuestID = nextMissingQuestID,
            luaStepDetail = luaStepDetail,
            title = (isRU and s.titleRU) or s.titleEN or ("Step " .. idx),
            desc = (isRU and s.descRU) or s.descEN or "",
            npc = (isRU and s.npcRU) or s.npcEN or "",
            zone = stepZone,
            mapID = s.mapID,
            x = s.x,
            y = s.y,
            doneQuest = activeLogQuestID or nextMissingQuestID or s.doneQuest,
        }
    end

    local completedSteps = 0
    local currentStepIndex = nil
    local hasStarted = false

    for idx, st in ipairs(stepStates) do
        if st.isDone then
            completedSteps = completedSteps + 1
            if not st.accountShared then
                hasStarted = true
            end
        else
            if st.inLog or st.doneSubCount > 0 then
                hasStarted = true
            end
            if not currentStepIndex then
                currentStepIndex = idx
                st.isCurrent = true
            end
        end
    end

    if not currentStepIndex then
        currentStepIndex = totalSteps
    end

    return {
        mountID = mountID,
        name = name or "Mount",
        spellID = spellID,
        icon = icon,
        isCollected = isCollected == true,
        chain = chain,
        wowheadUrl = chain.wowheadUrl,
        category = (isRU and chain.categoryRU) or chain.categoryEN or "",
        summary = (isRU and chain.summaryRU) or chain.summaryEN or "",
        classRestriction = chain.classRestriction,
        steps = stepStates,
        completedSteps = completedSteps,
        totalSteps = totalSteps,
        currentStepIndex = currentStepIndex,
        currentStep = stepStates[currentStepIndex],
        hasStarted = hasStarted,
    }
end

local WOWHEAD_LOCALE_PATH = {
    ruRU = "ru/",
    deDE = "de/",
    frFR = "fr/",
    esES = "es/",
    esMX = "es/",
    itIT = "it/",
    ptBR = "pt/",
    koKR = "ko/",
    zhCN = "cn/",
    zhTW = "tw/",
}

function addon:GetMountWowheadURL(mountID, questID)
    local locCode = self:GetActiveLocaleCode()
    local subPath = WOWHEAD_LOCALE_PATH[locCode] or ""
    local domain = "https://www.wowhead.com/" .. subPath
    if questID and questID > 0 then
        return domain .. "quest=" .. tostring(questID)
    end
    local chain = self.MountQuestsByMountID and self.MountQuestsByMountID[mountID]
    if chain and chain.wowheadUrl then
        return (chain.wowheadUrl:gsub("https://www%.wowhead%.com/ru/", domain):gsub("https://www%.wowhead%.com/", domain))
    end
    local info = self.DropInfoByMount and self.DropInfoByMount[mountID]
    if info and info.itemID and info.itemID > 0 then
        return domain .. "item=" .. tostring(info.itemID)
    end
    local _, spellID = C_MountJournal.GetMountInfoByID(mountID)
    if spellID and spellID > 0 then
        return domain .. "spell=" .. tostring(spellID)
    end
    return domain .. "mounts"
end

-- Поставить стрелку TomTom + 3D-метку на конкретный (или текущий активный) шаг квестовой цепочки
function addon:NavigateMountQuestStep(mountID, stepIndex, silent)
    local status = self:GetMountQuestChainStatus(mountID)
    if not status then return false end

    local targetIdx = stepIndex or status.currentStepIndex or 1
    local st = status.steps[targetIdx] or status.steps[1]
    if not st or not st.mapID or not st.x or not st.y then return false end

    self.activeQuestGuideMountID = mountID
    self.activeQuestGuideStepIndex = st.index

    local label = string.format("%s — %s", st.title, st.npc ~= "" and st.npc or status.name)
    self:SetMountWaypoint(mountID, st.mapID, st.x, st.y, label, true)

    if not silent then
        print(string.format(
            L.CHAT_QUEST_NAV_SET,
            status.name,
            st.title,
            st.zone,
            st.x,
            st.y,
            st.npc ~= "" and st.npc or "NPC"
        ))
    end
    return true
end

-- Получить лучшие координаты спавна для маунта (приоритет текущей карте)
function addon:GetBestMountCoords(mountID, preferredMapID)
    local info = self.DropInfoByMount[mountID]
    if not info or not info.coords or #info.coords == 0 then return nil end

    local pMapID = preferredMapID or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    local px, py = nil, nil
    if pMapID and C_Map and C_Map.GetPlayerMapPosition then
        local okPos, pos = pcall(C_Map.GetPlayerMapPosition, pMapID, "player")
        if okPos and pos and pos.GetXY then
            local rx, ry = pos:GetXY()
            if SafeNotSecret(rx) and SafeNotSecret(ry) and rx and ry and rx > 0 and ry > 0 then
                px, py = rx * 100.0, ry * 100.0
            end
        end
    end

    local function findBest(requireUnlocked, filterMapID)
        local bestC = nil
        local bestDistSq = math.huge
        for _, c in ipairs(info.coords) do
            if c.x and c.x > 0 and c.y and c.y > 0 and (not filterMapID or c.m == filterMapID) then
                local isLocked = (c.npcID and self.IsNpcLockedToday and self:IsNpcLockedToday(c.npcID)) or false
                if not requireUnlocked or not isLocked then
                    if px and py and c.m == pMapID then
                        local dx = c.x - px
                        local dy = c.y - py
                        local dSq = dx * dx + dy * dy
                        if dSq < bestDistSq then
                            bestDistSq = dSq
                            bestC = c
                        end
                    elseif not bestC then
                        bestC = c
                    end
                end
            end
        end
        return bestC
    end

    -- 1. Сначала ищем ближайшего НЕ убитого сегодня рарника в целевой/текущей зоне
    if preferredMapID then
        local unlockedInPref = findBest(true, preferredMapID)
        if unlockedInPref then return unlockedInPref end
    end
    -- 2. Ищем любого НЕ убитого сегодня рарника по всем зонам маунта
    local unlockedAny = findBest(true, nil)
    if unlockedAny then return unlockedAny end

    -- 3. Если все рарники сегодня уже убиты (КД), возвращаем ближайшую точку как фоллбэк
    if preferredMapID then
        local anyInPref = findBest(false, preferredMapID)
        if anyInPref then return anyInPref end
    end
    return findBest(false, nil)
end

-- Поставить метку на карте и 3D-стрелку (Blizzard UserWaypoint + SuperTrack + TomTom)
function addon:SetMountWaypoint(mountID, preferredMapID, liveX, liveY, customLabel, silent, customMountNames)
    local name = customMountNames or (C_MountJournal and C_MountJournal.GetMountInfoByID(mountID)) or "Mount"
    local info = self.DropInfoByMount[mountID]
    local mapID = preferredMapID or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    local x, y = liveX, liveY
    local validCustomLabel = IsValidNpcName(customLabel) and customLabel or nil
    local npcLabel = validCustomLabel or (info and info.boss) or name

    local c = self:GetBestMountCoords(mountID, mapID)
    if not x or not y or x <= 0 or y <= 0 then
        if c then
            mapID = c.m
            x = c.x
            y = c.y
        end
    end
    if not validCustomLabel and c then
        local knownName = c.npcID and self.KnownNpcNames and self.KnownNpcNames[c.npcID]
        if IsValidNpcName(knownName) then
            npcLabel = knownName
        elseif c.n and c.n ~= "" then
            npcLabel = c.n
        end
    end

    if not mapID or not x or not y or x <= 0 or y <= 0 then
        return false
    end

    local normX = (x > 1) and (x / 100.0) or x
    local normY = (y > 1) and (y / 100.0) or y
    local dispX = normX * 100.0
    local dispY = normY * 100.0

    -- 1. Стандартная метка и 3D-ромбик Blizzard
    if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local ok, canSet = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
        if not ok or canSet then
            pcall(function()
                local pt = UiMapPoint.CreateFromCoordinates(mapID, normX, normY)
                C_Map.SetUserWaypoint(pt)
                if C_SuperTracked and C_SuperTracked.SetSuperTrackedUserWaypoint then
                    C_SuperTracked.SetSuperTrackedUserWaypoint(true)
                end
            end)
        end
    end

    -- 2. Стрелка TomTom (если установлен TomTom)
    if _G.TomTom and _G.TomTom.AddWaypoint then
        pcall(function()
            if self.lastTomTomUid and _G.TomTom.RemoveWaypoint then
                _G.TomTom:RemoveWaypoint(self.lastTomTomUid)
            end
            self.lastTomTomUid = _G.TomTom:AddWaypoint(mapID, normX, normY, {
                title = string.format("[MountCollector] %s (%s)", npcLabel, name),
                persistent = false,
                minimap = true,
                world = true,
            })
        end)
    end

    if not silent then
        local chatKey = string.format("%s:%.1f:%.1f", tostring(mapID), dispX, dispY)
        local now = GetTime()
        if self.lastWaypointChatKey ~= chatKey or not self.lastWaypointChatTime or (now - self.lastWaypointChatTime) > 15 then
            self.lastWaypointChatKey = chatKey
            self.lastWaypointChatTime = now
            print(string.format(L.CHAT_WAYPOINT_SET, npcLabel, dispX, dispY, name))
        end
    end
    return true
end

-- Отметить все точки спавна рарника / маунта на Карте Мира и в TomTom + проложить маршрут
function addon:PinAllMountSpawns(mountID, openWorldMap)
    if not mountID then return false end
    local qStatus = self:GetMountQuestChainStatus(mountID)
    if qStatus then
        self:NavigateMountQuestStep(mountID, qStatus.currentStepIndex or 1, false)
        if openWorldMap and qStatus.currentStep and qStatus.currentStep.mapID and OpenWorldMap then
            pcall(OpenWorldMap, qStatus.currentStep.mapID)
        end
        return true
    end

    local info = self.DropInfoByMount and self.DropInfoByMount[mountID]
    local name = C_MountJournal and C_MountJournal.GetMountInfoByID(mountID) or "Mount"
    local coords = {}
    local seen = {}

    if info and type(info.coords) == "table" then
        for _, c in ipairs(info.coords) do
            if c.m and c.m > 0 and c.m < 5000 and c.x and c.x > 0 and c.y and c.y > 0 then
                local key = string.format("%d:%.1f:%.1f", c.m, c.x, c.y)
                if not seen[key] then
                    seen[key] = true
                    table.insert(coords, c)
                end
            end
        end
    end

    self.highlightedMapMountID = mountID

    if #coords == 0 then
        return self:SetMountWaypoint(mountID, nil, nil, nil, info and info.boss, false)
    end

    if self.multiTomTomUids and _G.TomTom and _G.TomTom.RemoveWaypoint then
        for _, uid in ipairs(self.multiTomTomUids) do
            pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid)
        end
    end
    self.multiTomTomUids = {}

    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local availCoords = {}
    for _, c in ipairs(coords) do
        if not (c.npcID and self:IsNpcLockedToday(c.npcID)) then
            table.insert(availCoords, c)
        end
    end
    local routeCoords = (#availCoords > 0) and availCoords or coords

    local primaryCoord = self:GetBestMountCoords(mountID, playerMapID) or routeCoords[1]

    if _G.TomTom and _G.TomTom.AddWaypoint then
        for idx, c in ipairs(routeCoords) do
            local nx = (c.x > 1) and (c.x / 100.0) or c.x
            local ny = (c.y > 1) and (c.y / 100.0) or c.y
            local label = (c.n and c.n ~= "") and c.n or (info and info.boss) or name
            if #routeCoords > 1 then
                label = string.format("%s #%d", label, idx)
            end
            pcall(function()
                local uid = _G.TomTom:AddWaypoint(c.m, nx, ny, {
                    title = string.format("[MountCollector] %s (%s)", label, name),
                    persistent = false,
                    minimap = true,
                    world = true,
                })
                if uid then
                    table.insert(self.multiTomTomUids, uid)
                end
            end)
        end
    end

    self:SetMountWaypoint(mountID, primaryCoord.m, primaryCoord.x, primaryCoord.y, primaryCoord.n or (info and info.boss), false)

    if openWorldMap and primaryCoord.m and OpenWorldMap then
        pcall(OpenWorldMap, primaryCoord.m)
    end
    if self.RefreshWorldMapPins then
        self:RefreshWorldMapPins()
    end

    return true
end

-- Проверить особые условия получения маунта (предметы в сумках, фазы зон, ковенанты, КД рарника)
function addon:GetMountSpecialConditions(mountID)
    if not mountID then return nil end
    local isRU = (self:GetActiveLocaleCode() == "ruRU")
    local lines = {}
    local lockedToday = self:IsMountRareLockedToday(mountID)

    -- 1. Запись в SpecialMountConditionsDB
    local spec = self.SpecialMountConditionsDB and self.SpecialMountConditionsDB[mountID]
    if spec then
        local txt = (isRU and spec.condRU) or spec.condEN
        if txt and txt ~= "" then
            table.insert(lines, txt)
        end
        if spec.requiredItemID then
            local count, itemName = self:GetRequirementItemCount(spec.requiredItemID)
            local statusColor = (count > 0) and "|cff00ff96" or "|cffff6666"
            table.insert(lines, string.format(L.LUA_REQ_ITEM_FMT, statusColor, itemName, count))
        end
    end

    -- 2. Предметы-источники из RareScannerMountItems / DropInfoByMount
    local itemIDs = self.RareScannerMountItems and self.RareScannerMountItems[mountID]
    local info = self.DropInfoByMount and self.DropInfoByMount[mountID]
    if not itemIDs and info and type(info.sourceItems) == "table" and #info.sourceItems > 0 then
        itemIDs = info.sourceItems
    end
    if type(itemIDs) == "table" and #itemIDs > 0 then
        for _, iid in ipairs(itemIDs) do
            if iid and iid > 0 and (not spec or spec.requiredItemID ~= iid) and (not info or info.itemID ~= iid) then
                local count, itemName = self:GetRequirementItemCount(iid)
                if count > 0 or #itemIDs <= 3 then
                    local clr = (count > 0) and "|cff00ff96" or "|cffcccccc"
                    table.insert(lines, string.format(L.LUA_SOURCE_ITEM_FMT, iid, clr, itemName, count))
                end
            end
        end
    end

    -- 3. Проверка дневного / недельного КД рарника по всем локаут-квестам
    if info and type(info.quests) == "table" and #info.quests > 0 and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local doneQuests = {}
        local availQuests = {}
        local questToNpcName = {}
        if self.RareScannerNpcToMounts then
            for nid, rsData in pairs(self.RareScannerNpcToMounts) do
                if rsData and type(rsData.quests) == "table" then
                    local nName = (self.KnownNpcNames and self.KnownNpcNames[nid]) or rsData.name
                    if nName and nName ~= "" then
                        for _, rq in ipairs(rsData.quests) do
                            questToNpcName[rq] = nName
                        end
                    end
                end
            end
        end
        for _, qid in ipairs(info.quests) do
            local label = questToNpcName[qid] and string.format("%s (#%d)", questToNpcName[qid], qid) or ("#" .. tostring(qid))
            if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                table.insert(doneQuests, label)
            else
                table.insert(availQuests, label)
            end
        end
        if #info.quests > 1 then
            table.insert(lines, string.format(L.LUA_LOCKOUT_MULTI_SUMMARY_FMT, #doneQuests, #info.quests, #availQuests))
        end
        if #doneQuests > 0 then
            table.insert(lines, string.format(L.LUA_LOCKOUT_LOCKED_FMT, table.concat(doneQuests, ", ")))
        end
        if #availQuests > 0 and (#info.quests == 1 or #doneQuests > 0) then
            table.insert(lines, string.format(L.LUA_LOCKOUT_AVAIL_FMT, table.concat(availQuests, ", ")))
        elseif #doneQuests == 0 then
            table.insert(lines, string.format(L.LUA_LOCKOUT_AVAIL_FMT, table.concat(availQuests, ", ")))
        end
    end

    if #lines == 0 then return nil end
    return {
        text = table.concat(lines, "\n"),
        lines = lines,
        lockedToday = lockedToday,
    }
end

-- Построить полный диагностический отчёт Lua-Дебаггера по маунту и его квестовой цепочке
function addon:BuildMountDebugReport(mountID)
    local isRU = (self:GetActiveLocaleCode() == "ruRU")
    local out = {}
    local function add(line)
        table.insert(out, line or "")
    end

    local charKey = self:GetCharKey()
    local classLoc, classToken = UnitClass("player")
    local factionToken, factionLoc = UnitFactionGroup("player")
    local level = UnitLevel("player") or 0
    local pMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pMapName = (pMapID and C_Map.GetMapInfo and C_Map.GetMapInfo(pMapID)) and C_Map.GetMapInfo(pMapID).name or GetRealZoneText() or "?"
    local px, py = 0, 0
    if pMapID and C_Map.GetPlayerMapPosition then
        local okPos, pos = pcall(C_Map.GetPlayerMapPosition, pMapID, "player")
        if okPos and pos and pos.GetXY then
            local x, y = pos:GetXY()
            if SafeNotSecret(x) and SafeNotSecret(y) and x and y then
                px, py = x * 100.0, y * 100.0
            end
        end
    end

    add("=== MountCollector Lua Quest & Source Debugger (v1.4.0) ===")
    add(string.format("Character: %s | Class: %s (%s) | Level: %d | Faction: %s", charKey, tostring(classLoc), tostring(classToken), level, tostring(factionLoc or factionToken)))
    add(string.format("Player Map: %s (mapID = %s) [%.1f, %.1f]", tostring(pMapName), tostring(pMapID), px, py))
    add("------------------------------------------------------------")

    if not mountID then
        add("No mount selected.")
        return table.concat(out, "\n")
    end

    local name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    local _, description, sourceText = C_MountJournal.GetMountInfoExtraByID(mountID)
    add(string.format("Mount: %s (mountID = %d | spellID = %s | isCollected = %s | sourceType = %s)", tostring(name), mountID, tostring(spellID), tostring(isCollected), tostring(sourceType)))

    local qStatus = self:GetMountQuestChainStatus(mountID)
    if qStatus then
        add(string.format("Quest Chain Category: %s | Class Restriction: %s", tostring(qStatus.category), tostring(qStatus.classRestriction or "None")))
        add(string.format("Calculated Progress: %d / %d steps done | Current Active Step Index: #%d", qStatus.completedSteps, qStatus.totalSteps, qStatus.currentStepIndex or 1))
        add(" ")
        add("=== STEP-BY-STEP QUEST FLAG EVALUATION ===")
        for _, st in ipairs(qStatus.steps) do
            local s = st.step
            local stateStr = st.isDone and (st.isDoneAccountOnly and "DONE (ACCOUNT)" or "DONE (CHAR)") or (st.isCurrent and "CURRENT STEP" or "LOCKED/TODO")
            add(string.format("\n[Step %d] %s -> [%s]", st.index, st.title, stateStr))
            if s.doneQuest then
                local cDone = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(s.doneQuest) or false
                local aDone = C_QuestLog and C_QuestLog.IsQuestFlaggedCompletedOnAccount and C_QuestLog.IsQuestFlaggedCompletedOnAccount(s.doneQuest) or false
                add(string.format("  doneQuest = %d | CharCompleted = %s | AccountCompleted = %s", s.doneQuest, tostring(cDone), tostring(aDone)))
            end
            if s.achievementID and GetAchievementInfo then
                local okA, _, aName, _, aComp, _, _, _, _, _, _, _, _, aByMe = pcall(GetAchievementInfo, s.achievementID)
                if okA then
                    add(string.format("  achievementID = %d (%s) | AccountCompleted = %s | CompletedByThisChar = %s", s.achievementID, tostring(aName), tostring(aComp), tostring(aByMe)))
                end
            end
            if s.requiredItemID then
                local cnt, iName = self:GetRequirementItemCount(s.requiredItemID)
                add(string.format("  requiredItemID = %d (%s) | Owned = %d / %d", s.requiredItemID, tostring(iName), cnt, s.requiredItemCount or 1))
            end
            if type(s.quests) == "table" and #s.quests > 0 then
                add(string.format("  Step Quests (%d total, %d completed on char):", #s.quests, st.doneSubCount or 0))
                for qIdx, qid in ipairs(s.quests) do
                    local cDone = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) or false
                    local aDone = C_QuestLog and C_QuestLog.IsQuestFlaggedCompletedOnAccount and C_QuestLog.IsQuestFlaggedCompletedOnAccount(qid) or false
                    local onQ = C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(qid) or false
                    local qTitle = self:GetQuestTitleByID(qid) or "?"
                    local objStr = onQ and self:GetQuestObjectivesText(qid) or nil
                    local mark = cDone and "[DONE]" or (onQ and "[IN LOG]" or (aDone and "[ACCT]" or "[MISSING]"))
                    add(string.format("    %2d. %-9s #%d — %s%s", qIdx, mark, qid, qTitle, objStr and (" (" .. objStr .. ")") or ""))
                end
            end
        end
    end

    local dropInfo = self.DropInfoByMount and self.DropInfoByMount[mountID]
    if dropInfo then
        add(" ")
        add("=== RARE / BOSS DROP & LOCKOUT DATA ===")
        local attempts = self:GetMountAttempts(mountID)
        add(string.format("Boss/Rare: %s | Method: %s | Chance: 1/%s | Account Attempts: %d", tostring(dropInfo.boss or "NPC"), tostring(dropInfo.method), tostring(dropInfo.chance or "?"), attempts))
        if type(dropInfo.quests) == "table" and #dropInfo.quests > 0 then
            local qParts = {}
            for _, qid in ipairs(dropInfo.quests) do
                local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) or false
                table.insert(qParts, string.format("#%d=%s", qid, tostring(done)))
            end
            add("Lockout Quests Today: " .. table.concat(qParts, ", "))
        end
        if type(dropInfo.coords) == "table" and #dropInfo.coords > 0 then
            add(string.format("Spawn Coordinates (%d points):", #dropInfo.coords))
            for i, c in ipairs(dropInfo.coords) do
                local mName = (c.m and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(c.m)) and C_Map.GetMapInfo(c.m).name or ("Map " .. tostring(c.m))
                local npcLock, qid = false, nil
                if c.npcID then
                    npcLock, qid = self:IsNpcLockedToday(c.npcID)
                end
                local lockTag = c.npcID and (npcLock and string.format(" [KILLED TODAY q#%s]", tostring(qid or "?")) or string.format(" [AVAILABLE q#%s]", tostring(qid or "?"))) or ""
                add(string.format("  %d. %s (mapID=%s) [%.1f, %.1f] — %s (npcID=%s)%s", i, mName, tostring(c.m), c.x or 0, c.y or 0, tostring(c.n or ""), tostring(c.npcID or "?"), lockTag))
            end
        end
    end

    -- Выводим все текущие активные квесты в журнале игрока (чтобы легко найти любой неучтённый квест!)
    add(" ")
    add("=== ACTIVE QUESTS IN PLAYER'S QUEST LOG RIGHT NOW ===")
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
        local currentHeader = "General"
        local printedAny = false
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info then
                if info.isHeader then
                    currentHeader = SafeNotSecret(info.title) and info.title or "Category"
                elseif not info.isHidden and SafeNotSecret(info.questID) and info.questID and info.questID > 0 then
                    printedAny = true
                    local qTitle = SafeNotSecret(info.title) and info.title or ("Quest #" .. tostring(info.questID))
                    local objTxt = self:GetQuestObjectivesText(info.questID)
                    add(string.format("  [%s] #%d — %s%s", currentHeader, info.questID, qTitle, objTxt and (" | Objectives: " .. objTxt) or ""))
                end
            end
        end
        if not printedAny then
            add("  (Quest log is empty)")
        end
    end

    return table.concat(out, "\n")
end

local function ParseStatisticValue(val)
    if not val or not SafeNotSecret(val) then return 0 end
    if type(val) == "number" then return val > 0 and val or 0 end
    if type(val) ~= "string" then return 0 end
    if val == "--" or val == "-" or val == "" then return 0 end
    local cleaned = val:gsub("[^%d]", "")
    local num = tonumber(cleaned)
    return (num and num > 0) and num or 0
end

-- Предсохранённый слепок статистики персонажей и траев из RarityDB (чтобы история не терялась при выключенном Rarity)
local SeededRarityCharStats = {
    ["Моржовый - Свежеватель Душ"] = {
        [1088] = 1, [1098] = 2, [1391] = 1, [4688] = 3, [5577] = 1, [5971] = 4,
        [6162] = 1, [6168] = 1, [8146] = 1, [8148] = 2, [8150] = 1, [8152] = 4,
        [8170] = 1, [8172] = 4, [8178] = 2, [8568] = 1, [8626] = 2, [8628] = 1,
        [8630] = 4, [8637] = 4, [9365] = 3, [10929] = 5, [10930] = 1, [10931] = 4,
        [10979] = 1, [10980] = 5, [11894] = 1, [11895] = 3, [11896] = 5, [11957] = 3,
        [11958] = 2, [11959] = 4, [11986] = 1, [12118] = 1, [12745] = 5, [12752] = 7,
        [12763] = 7, [13600] = 1, [13601] = 1, [14110] = 2, [14138] = 2,
    },
    ["Ньарлатхотеп - Свежеватель Душ"] = {
        [1097] = 1, [4688] = 1, [6989] = 1, [9279] = 1, [9365] = 2, [10928] = 1,
        [10931] = 1, [10979] = 1, [11893] = 1, [11957] = 5, [11958] = 2, [11959] = 2,
        [11986] = 1, [12118] = 1, [13366] = 1, [13600] = 3, [13601] = 3, [13603] = 2,
        [14107] = 1, [14110] = 12, [14138] = 9, [14398] = 1, [14458] = 1, [40295] = 8,
    },
    ["Ньарлатхотеп - Пиратская Бухта"] = {
        [1097] = 1, [4688] = 1, [6989] = 1, [9279] = 1, [9365] = 2, [10928] = 1,
        [10931] = 1, [10979] = 1, [11893] = 1, [11957] = 5, [11958] = 2, [11959] = 2,
        [11986] = 1, [12118] = 1, [13366] = 1, [13600] = 3, [13601] = 3, [13603] = 2,
        [14107] = 1, [14110] = 12, [14138] = 9, [14398] = 1, [14458] = 1, [40295] = 8,
    },
}

local SeededRarityMountTotals = {
    ["Solar Spirehawk"] = 2,
    ["Cobalt Dragonhawk"] = 7,
    ["Invincible's Reins"] = 5,
    ["Experiment 12-B"] = 1,
    ["Reins of the Thundering Cobalt Cloud Serpent"] = 1,
    ["Flametalon of Alysrazor"] = 4,
    ["Shackled Ur'zul"] = 3,
    ["Fiendish Hellfire Core"] = 5,
    ["Reins of the Heavenly Onyx Cloud Serpent"] = 2,
    ["Reins of the Sureki Skyrazor"] = 16,
    ["Ironhoof Destroyer"] = 7,
    ["Sharkbait's Favorite Crackers"] = 7,
    ["Reins of the Azure Drake"] = 1,
    ["Spawn of Horridon"] = 5,
    ["Ny'alotha Allseer"] = 20,
    ["Antoran Charhound"] = 30,
    ["Mummified Raptor Skull"] = 7,
    ["Deathcharger's Reins"] = 2,
    ["Ashes of Al'ar"] = 1,
    ["The Headless Horseman's Ghoulish Charger"] = 4,
    ["Cerulean Hawkstrider"] = 7,
    ["Kor'kron Juggernaut"] = 4,
    ["Abyss Worm"] = 11,
    ["Reins of the Drake of the South Wind"] = 1,
    ["Living Infernal Core"] = 8,
    ["The Horseman's Reins"] = 6,
    ["Underrot Crawg Harness"] = 5,
    ["Life-Binder's Handmaiden"] = 1,
    ["Clutch of Ji-Kun"] = 5,
    ["Reins of the Onyxian Drake"] = 2,
}

-- Сканирование полной таблицы «Достижения -> Статистика» (GetStatistic) для текущего персонажа
-- и суммирование киллов боссов по всем персонажам аккаунта
function addon:ScanAllCharacterStatistics()
    if not self.db or not self.DropInfoByMount then return end
    local charKey = self:GetCharKey()

    -- 1. Собираем таблицу accountWideStatistics из RarityDB (если загружен) + наш предсохранённый слепок
    local externalCharStats = {}
    for cKey, stMap in pairs(SeededRarityCharStats) do
        externalCharStats[cKey] = stMap
    end
    local rProfile = (_G.Rarity and _G.Rarity.db and _G.Rarity.db.profile)
        or (_G.RarityDB and _G.RarityDB.profiles and _G.RarityDB.profiles.Default)
    if rProfile and type(rProfile.accountWideStatistics) == "table" then
        for _, pData in pairs(rProfile.accountWideStatistics) do
            if type(pData) == "table" and pData.playerName and pData.server and type(pData.statistics) == "table" then
                local cKey = pData.playerName .. " - " .. pData.server
                externalCharStats[cKey] = pData.statistics
            end
        end
    end

    -- 2. Проходим по всем маунтам с боссами/статистикой
    for mountID, info in pairs(self.DropInfoByMount) do
        local record = self.db.attempts[mountID]
        local hasStats = info.stats and #info.stats > 0

        -- Проверяем базовый счётчик из Rarity
        local rarityTotal = (info.rarityKey and SeededRarityMountTotals[info.rarityKey]) or 0
        if rProfile and rProfile.groups and rProfile.groups.mounts and info.rarityKey then
            local rEntry = rProfile.groups.mounts[info.rarityKey]
            if rEntry and type(rEntry.attempts) == "number" and rEntry.attempts > rarityTotal then
                rarityTotal = rEntry.attempts
            end
        end

        if hasStats then
            -- Сначала подтягиваем сохранённую статистику других персонажей из externalCharStats
            for extCharKey, statTable in pairs(externalCharStats) do
                local extSum = 0
                for _, statID in ipairs(info.stats) do
                    local v = statTable[statID]
                    if type(v) == "number" and v > 0 then
                        extSum = extSum + v
                    end
                end
                if extSum > 0 then
                    record = record or { total = 0, byChar = {} }
                    record.byChar = record.byChar or {}
                    if extSum > (record.byChar[extCharKey] or 0) then
                        record.byChar[extCharKey] = extSum
                    end
                end
            end

            -- Теперь сканируем живую статистику ТЕКУЩЕГО персонажа через GetStatistic(statID)
            if GetStatistic then
                local currentCharStatSum = 0
                for _, statID in ipairs(info.stats) do
                    local ok, val = pcall(GetStatistic, statID)
                    if ok and val then
                        currentCharStatSum = currentCharStatSum + ParseStatisticValue(val)
                    end
                end
                if currentCharStatSum > 0 then
                    record = record or { total = 0, byChar = {} }
                    record.byChar = record.byChar or {}
                    if currentCharStatSum > (record.byChar[charKey] or 0) then
                        record.byChar[charKey] = currentCharStatSum
                    end
                end
            end
        elseif info.quests and #info.quests > 0 and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
            -- Если это рарник(и) с суточными квестами КД, проверяем, сколько из них уже закрыто СЕГОДНЯ на текущем персонаже
            local doneTodayOnChar = 0
            for _, qid in ipairs(info.quests) do
                if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                    doneTodayOnChar = doneTodayOnChar + 1
                end
            end
            if doneTodayOnChar > 0 then
                record = record or { total = 0, byChar = {} }
                record.byChar = record.byChar or {}
                if doneTodayOnChar > (record.byChar[charKey] or 0) then
                    record.byChar[charKey] = doneTodayOnChar
                end
            end
        end

        if record or rarityTotal > 0 then
            record = record or { total = 0, byChar = {} }
            record.byChar = record.byChar or {}
            local byCharSum = 0
            for _, c in pairs(record.byChar) do
                byCharSum = byCharSum + (tonumber(c) or 0)
            end
            local computed = math.max(record.manualTotal or 0, record.total or 0, byCharSum, rarityTotal)
            if computed > 0 then
                record.total = computed
                self.db.attempts[mountID] = record
            end
        end
    end
end

function addon:SetManualMountAttempts(mountID, count, resetToAuto)
    if not mountID or not self.db then return end
    local record = self.db.attempts[mountID] or { total = 0, byChar = {} }
    record.byChar = record.byChar or {}

    if resetToAuto then
        record.manualTotal = nil
        local byCharSum = 0
        for _, c in pairs(record.byChar) do
            byCharSum = byCharSum + (tonumber(c) or 0)
        end
        record.total = byCharSum
        self.db.attempts[mountID] = record
        self:ScanAllCharacterStatistics()
    else
        local num = math.max(0, math.floor(tonumber(count) or 0))
        record.manualTotal = num
        record.total = num
        self.db.attempts[mountID] = record
    end

    local name = C_MountJournal.GetMountInfoByID(mountID) or ("Mount #" .. tostring(mountID))
    print(string.format(L.CHAT_ATTEMPTS_SET, name, record.total or 0))

    if self.UpdateLDBText then
        self:UpdateLDBText()
    end
    if self.RefreshRadarUI then
        self:RefreshRadarUI()
    end
end

function addon:GetMountAttempts(mountID)
    if not mountID or not self.db then return 0, nil, nil end
    local info = self.DropInfoByMount[mountID]
    local record = self.db.attempts[mountID]

    local mcTotal = 0
    local byCharSum = 0
    if record then
        mcTotal = math.max(record.manualTotal or 0, record.total or 0)
        if record.byChar then
            for _, c in pairs(record.byChar) do
                byCharSum = byCharSum + (tonumber(c) or 0)
            end
        end
        if byCharSum > mcTotal and not record.manualTotal then
            mcTotal = byCharSum
            record.total = mcTotal
        end
    end

    local rarityAttempts = 0
    if info then
        if info.rarityKey and SeededRarityMountTotals[info.rarityKey] then
            rarityAttempts = SeededRarityMountTotals[info.rarityKey]
        end
        local rEntry = info.rarityEntry
        if not rEntry and info.rarityKey and _G.Rarity and _G.Rarity.db and _G.Rarity.db.profile and _G.Rarity.db.profile.groups and _G.Rarity.db.profile.groups.mounts then
            rEntry = _G.Rarity.db.profile.groups.mounts[info.rarityKey]
            info.rarityEntry = rEntry
        end
        if rEntry and type(rEntry.attempts) == "number" and rEntry.attempts > rarityAttempts then
            rarityAttempts = rEntry.attempts
        end

        local statSum = 0
        if info.stats and #info.stats > 0 and GetStatistic then
            for _, statID in ipairs(info.stats) do
                local ok, val = pcall(GetStatistic, statID)
                if ok and val then
                    statSum = statSum + ParseStatisticValue(val)
                end
            end
        end
        if statSum > 0 then
            local charKey = self:GetCharKey()
            record = record or { total = 0, byChar = {} }
            record.byChar = record.byChar or {}
            if statSum > (record.byChar[charKey] or 0) then
                record.byChar[charKey] = statSum
                byCharSum = 0
                for _, c in pairs(record.byChar) do
                    byCharSum = byCharSum + (tonumber(c) or 0)
                end
            end
            self.db.attempts[mountID] = record
        end
        if byCharSum > rarityAttempts then
            rarityAttempts = byCharSum
        elseif statSum > rarityAttempts then
            rarityAttempts = statSum
        end
    end

    local finalAttempts = (record and record.manualTotal) and math.max(record.manualTotal, record.total or 0) or math.max(mcTotal, byCharSum, rarityAttempts)
    if finalAttempts > 0 and (not record or finalAttempts > (record.total or 0)) then
        record = record or { total = 0, byChar = {} }
        record.total = finalAttempts
        self.db.attempts[mountID] = record
    end

    return finalAttempts, record and record.byChar or nil, info
end

function addon:RecordAttempt(mountID, sourceName)
    if not mountID or not self.db then return end
    local name, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    if isCollected then return end

    local now = GetTime()
    if self.RecentAttemptLock[mountID] and (now - self.RecentAttemptLock[mountID]) < 90 then
        return
    end
    self.RecentAttemptLock[mountID] = now

    local info = self.DropInfoByMount[mountID]
    local prevTotal = self:GetMountAttempts(mountID)
    local record = self.db.attempts[mountID] or { total = 0, byChar = {} }
    local charKey = self:GetCharKey()

    record.byChar = record.byChar or {}
    record.byChar[charKey] = (record.byChar[charKey] or 0) + 1

    local byCharSum = 0
    for _, c in pairs(record.byChar) do
        byCharSum = byCharSum + (tonumber(c) or 0)
    end

    if record.manualTotal then
        record.manualTotal = record.manualTotal + 1
        record.total = math.max(record.manualTotal, byCharSum)
    else
        record.total = math.max((record.total or 0) + 1, prevTotal + 1, byCharSum)
    end

    record.lastKill = time()
    record.lastChar = charKey
    self.db.attempts[mountID] = record

    local chance = (info and info.chance and info.chance > 0) and info.chance or 100
    local luckPct = (1 - math.pow(1 - (1 / chance), record.total)) * 100

    local rarityAlreadyAnnounces = (_G.Rarity and rEntry and _G.Rarity.db and _G.Rarity.db.profile and _G.Rarity.db.profile.enableAnnouncements ~= false)
    if self.db.settings.announceAttempts and not rarityAlreadyAnnounces then
        print(string.format(
            L.CHAT_ATTEMPT_RECORDED,
            record.total,
            name or "Mount",
            sourceName or (info and info.boss) or "NPC",
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
    if self.RefreshWorldMapPins then
        self:RefreshWorldMapPins()
    end
end

-- Проверить, убит ли уже сегодня конкретный рарник (по его индивидуальному скрытому daily questID)
function addon:IsNpcLockedToday(npcID)
    if not npcID or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        return false, nil
    end
    local rs = self.RareScannerNpcToMounts and self.RareScannerNpcToMounts[npcID]
    if rs and type(rs.quests) == "table" and #rs.quests > 0 then
        for _, qid in ipairs(rs.quests) do
            if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                return true, qid
            end
        end
        return false, rs.quests[1]
    end
    local mounts = self.MountsByNpc and self.MountsByNpc[npcID]
    if mounts then
        for _, mID in ipairs(mounts) do
            local info = self.DropInfoByMount and self.DropInfoByMount[mID]
            if info and type(info.quests) == "table" and #info.quests == 1 then
                local qid = info.quests[1]
                if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                    return true, qid
                end
                return false, qid
            end
        end
    end
    return false, nil
end

-- Проверить, закрыты ли на сегодня рарники для маунта (возвращает: allLocked, doneCount, totalCount)
function addon:IsMountRareLockedToday(mountID)
    local info = self.DropInfoByMount[mountID]
    if not info or not info.quests or #info.quests == 0 then
        return false, 0, 0
    end
    local doneCount = 0
    local totalCount = #info.quests
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        for _, qid in ipairs(info.quests) do
            if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                doneCount = doneCount + 1
            end
        end
    end
    return (doneCount >= totalCount and totalCount > 0), doneCount, totalCount
end

function addon:ScanUnitMount(unit)
    if InCombatLockdown and InCombatLockdown() then return end
    if IsInInstance and (select(1, IsInInstance())) then return end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return end
    if not unit or not SafeNotSecret(unit) then return end
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    if UnitIsFriend and not UnitIsFriend("player", unit) then return end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return end

    local unitName, unitRealm = UnitName(unit)
    if not SafeNotSecret(unitName) or not unitName then return end
    local realm = (SafeNotSecret(unitRealm) and unitRealm and unitRealm ~= "") and unitRealm or (GetRealmName() or "Realm")

    for i = 1, 40 do
        if C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret and C_Secrets.ShouldUnitAuraIndexBeSecret(unit, i, "HELPFUL") then
            break
        end
        local okAura, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not okAura or not aura then break end
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

-- Сделать слепок уже закрытых на сегодня суточных квестов рарников (при входе в мир или смене зоны),
-- чтобы при первом килле рарника (когда сервер мгновенно ставит флаг квеста при смерти моба до открытия окна лута)
-- аддон точно знал, что до этого боя квест ещё НЕ был выполнен!
function addon:SnapshotPreLockedRares()
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end
    self.CompletedRareQuestsSnapshot = self.CompletedRareQuestsSnapshot or {}
    self.RecentlySpottedUnlockedRares = self.RecentlySpottedUnlockedRares or {}
    local now = GetTime()
    if self.RareScannerNpcToMounts then
        for npcID, rs in pairs(self.RareScannerNpcToMounts) do
            local seenUnlocked = self.RecentlySpottedUnlockedRares[npcID] and ((now - self.RecentlySpottedUnlockedRares[npcID]) < 600)
            if rs and type(rs.quests) == "table" then
                for _, qid in ipairs(rs.quests) do
                    local done = C_QuestLog.IsQuestFlaggedCompleted(qid)
                    if done then
                        if not seenUnlocked and not (self.JustCompletedLockoutQuestAt and self.JustCompletedLockoutQuestAt[qid] and (now - self.JustCompletedLockoutQuestAt[qid]) < 120) then
                            self.CompletedRareQuestsSnapshot[qid] = true
                        end
                    else
                        self.CompletedRareQuestsSnapshot[qid] = false
                    end
                end
            end
        end
    end
    if self.DropInfoByMount then
        for _, info in pairs(self.DropInfoByMount) do
            if info and type(info.quests) == "table" then
                for _, qid in ipairs(info.quests) do
                    if self.CompletedRareQuestsSnapshot[qid] == nil then
                        self.CompletedRareQuestsSnapshot[qid] = (C_QuestLog.IsQuestFlaggedCompleted(qid) == true)
                    end
                end
            end
        end
    end
end

-- Проверить после выхода из боя рарников, которых мы видели живыми и открытыми:
-- если их суточный квест только что переключился в true (например, Волнуш убежал к подсолнуху или пуш-лут без трупа), засчитываем трай!
function addon:CheckRecentlyKilledRares()
    if not self.RecentlySpottedUnlockedRares then return end
    local now = GetTime()
    for npcID, spottedAt in pairs(self.RecentlySpottedUnlockedRares) do
        if (now - spottedAt) < 600 then
            local isLocked, lockQid = self:IsNpcLockedToday(npcID)
            if isLocked then
                self.RecentlySpottedUnlockedRares[npcID] = nil
                if lockQid then
                    self.CompletedRareQuestsSnapshot = self.CompletedRareQuestsSnapshot or {}
                    self.CompletedRareQuestsSnapshot[lockQid] = true
                    self.JustCompletedLockoutQuestAt = self.JustCompletedLockoutQuestAt or {}
                    self.JustCompletedLockoutQuestAt[lockQid] = now
                end
                local rs = self.RareScannerNpcToMounts and self.RareScannerNpcToMounts[npcID]
                local srcName = (self.KnownNpcNames and self.KnownNpcNames[npcID])
                    or (rs and rs.name and rs.name ~= "" and rs.name)
                    or ("NPC #" .. tostring(npcID))
                if self.MountsByNpc and self.MountsByNpc[npcID] then
                    for _, mountID in ipairs(self.MountsByNpc[npcID]) do
                        self:RecordAttempt(mountID, srcName)
                    end
                end
                if self.RefreshWorldMapPins then
                    self:RefreshWorldMapPins()
                end
            end
        else
            self.RecentlySpottedUnlockedRares[npcID] = nil
        end
    end
end

function addon:CheckUnitForMountDrop(unit, isRetry)
    if not unit or not SafeNotSecret(unit) or not UnitExists(unit) then return end
    if UnitIsPlayer(unit) then
        self:ScanUnitMount(unit)
        return
    end

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

    for _, mountID in ipairs(mounts) do
        local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if not isCollected then
            self:TriggerRareMountAlert(mountID, npcID, npcName, false)
            break
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
    else
        local rs = self.RareScannerNpcToMounts and self.RareScannerNpcToMounts[npcID]
        vName = (self.KnownNpcNames and self.KnownNpcNames[npcID]) or (rs and rs.name) or "Rare NPC"
    end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local liveX, liveY = nil, nil
    if mapID and C_VignetteInfo.GetVignettePosition then
        local ok, pos = pcall(C_VignetteInfo.GetVignettePosition, vignetteGUID, mapID)
        if ok and pos and pos.GetXY then
            local vx, vy = pos:GetXY()
            if SafeNotSecret(vx) and SafeNotSecret(vy) and vx and vy and vx > 0 and vy > 0 then
                liveX = vx * 100.0
                liveY = vy * 100.0
            end
        end
    end

    for _, mountID in ipairs(mounts) do
        local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if not isCollected then
            self:TriggerRareMountAlert(mountID, npcID, vName, false, mapID, liveX, liveY)
            break
        end
    end
end

function addon:GetZoneUncollectedMounts(targetMapID)
    local results = {}
    if not C_Map then return results end
    local mapID = targetMapID or (C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
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
                    local bestCoord = self:GetBestMountCoords(mountID, mid)
                    local locked, lockedCount, totalLockoutCount = self:IsMountRareLockedToday(mountID)
                    table.insert(results, {
                        mountID = mountID,
                        name = name,
                        spellID = spellID,
                        icon = icon,
                        attempts = attempts,
                        chance = info and info.chance or nil,
                        boss = (bestCoord and bestCoord.n ~= "" and bestCoord.n) or (info and info.boss) or nil,
                        method = info and info.method or "NPC",
                        globalRarity = globalRarity,
                        locked = locked,
                        lockedCount = lockedCount or 0,
                        totalLockoutCount = totalLockoutCount or 0,
                        coord = bestCoord,
                    })
                end
            end
        end
    end

    addMapMounts(mapID)
    if not targetMapID and C_Map.GetMapInfo then
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

-- Сканирование уровня, класса и активных КД инстансов/праздничных данжей текущего персонажа
function addon:ScanCurrentCharacterLockouts()
    if not self.db then return end
    self.db.chars = self.db.chars or {}

    local charKey = self:GetCharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Realm"
    local _, classFile = UnitClass("player")
    local level = UnitLevel("player") or 1
    local now = time()

    local cData = self.db.chars[charKey] or {}
    cData.name = name
    cData.realm = realm
    cData.class = classFile or cData.class or "PRIEST"
    cData.level = (level and level > 0) and level or (cData.level or 1)
    cData.lastSeen = now
    cData.savedInstances = cData.savedInstances or {}
    cData.savedInstanceNames = cData.savedInstanceNames or {}
    cData.savedLfg = cData.savedLfg or {}

    -- Очищаем истекшие КД
    for k, exp in pairs(cData.savedInstances) do
        if type(exp) ~= "number" or exp <= now then
            cData.savedInstances[k] = nil
        end
    end
    for k, exp in pairs(cData.savedInstanceNames) do
        if type(exp) ~= "number" or exp <= now then
            cData.savedInstanceNames[k] = nil
        end
    end
    for k, exp in pairs(cData.savedLfg) do
        if type(exp) ~= "number" or exp <= now then
            cData.savedLfg[k] = nil
        end
    end

    -- 1. Сохранённые рейды и эпохальные подземелья (GetNumSavedInstances)
    if GetNumSavedInstances and GetSavedInstanceInfo then
        local numSaved = GetNumSavedInstances() or 0
        for i = 1, numSaved do
            local instName, _, reset, _, locked, extended, _, _, _, _, _, _, _, instanceId = GetSavedInstanceInfo(i)
            if (locked or extended) and type(reset) == "number" and reset > 0 then
                local expiresAt = now + reset
                if type(instanceId) == "number" and instanceId > 0 then
                    cData.savedInstances[instanceId] = math.max(cData.savedInstances[instanceId] or 0, expiresAt)
                end
                if SafeNotSecret(instName) and type(instName) == "string" and instName ~= "" then
                    local lowerName = string.lower(instName)
                    cData.savedInstanceNames[lowerName] = math.max(cData.savedInstanceNames[lowerName] or 0, expiresAt)
                end
            end
        end
    end

    -- 2. Праздничные боссы в поиске подземелий (Всадник без головы 285, Корен Худовар 287, Королевская химическая компания 288)
    if GetLFGDungeonRewards then
        local resetSec = (GetQuestResetTime and GetQuestResetTime()) or 86400
        if type(resetSec) ~= "number" or resetSec <= 0 or resetSec > 172800 then
            resetSec = 86400
        end
        for _, lfgID in ipairs({ 285, 287, 288 }) do
            local ok, doneToday = pcall(GetLFGDungeonRewards, lfgID)
            if ok and doneToday then
                cData.savedLfg[lfgID] = now + resetSec
            end
        end
    end

    self.db.chars[charKey] = cData
end

local function FormatClassColoredChar(name, classFile, level)
    local shortName = tostring(name or "Character"):gsub("%s*%-.+$", "")
    local colorPrefix = "|cffffffff"
    if classFile and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile] and _G.RAID_CLASS_COLORS[classFile].colorStr then
        colorPrefix = "|" .. _G.RAID_CLASS_COLORS[classFile].colorStr
    end
    if level and level > 0 then
        return string.format("%s%s|r |cffaaaaaa(%d)|r", colorPrefix, shortName, level)
    end
    return string.format("%s%s|r", colorPrefix, shortName)
end

local function IsCharLockedForDungeonEntry(cData, dEntry, now)
    if not cData or not dEntry then return false end
    if dEntry.lockoutType == "UNLIMITED" then
        return false
    end
    if dEntry.lfgDungeonID and cData.savedLfg and cData.savedLfg[dEntry.lfgDungeonID] and cData.savedLfg[dEntry.lfgDungeonID] > now then
        return true
    end
    if dEntry.instanceMapID and cData.savedInstances and cData.savedInstances[dEntry.instanceMapID] and cData.savedInstances[dEntry.instanceMapID] > now then
        return true
    end
    if cData.savedInstanceNames then
        local ruLower = dEntry.instanceRU and string.lower(dEntry.instanceRU) or nil
        local enLower = dEntry.instanceEN and string.lower(dEntry.instanceEN) or nil
        for savedName, exp in pairs(cData.savedInstanceNames) do
            if exp and exp > now then
                if (ruLower and (savedName == ruLower or string.find(ruLower, savedName, 1, true) or string.find(savedName, ruLower, 1, true)))
                    or (enLower and (savedName == enLower or string.find(enLower, savedName, 1, true) or string.find(savedName, enLower, 1, true))) then
                    return true
                end
            end
        end
    end
    return false
end

-- Получить полную сводку по данж/рейд/ивент-маунту + матрицу твинков аккаунта с учётом минимального уровня (minLevel)
function addon:GetDungeonMountStatus(mountID)
    local dEntry = self.MountDungeonsByMountID and self.MountDungeonsByMountID[mountID]
    if not dEntry then return nil end

    self:ScanCurrentCharacterLockouts()

    local isRU = (self:GetActiveLocaleCode() == "ruRU")
    local name, spellID, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    local now = time()
    local minLevel = dEntry.minLevel or 10
    local chance = dEntry.chance or 100
    local chancePct = (chance > 0) and (100.0 / chance) or 1.0

    local lockoutTitle = L.LOCKOUT_WEEKLY
    if dEntry.lockoutType == "DAILY" then
        lockoutTitle = L.LOCKOUT_DAILY
    elseif dEntry.lockoutType == "UNLIMITED" then
        lockoutTitle = L.LOCKOUT_UNLIMITED
    end

    local eventTitle = nil
    if dEntry.sourceKind == "EVENT" or dEntry.eventRU or dEntry.eventEN then
        eventTitle = (isRU and dEntry.eventRU) or dEntry.eventEN or dEntry.eventRU
    end

    local instanceTitle = (isRU and dEntry.instanceRU) or dEntry.instanceEN or dEntry.instanceRU or "Instance"
    local bossTitle = (isRU and dEntry.bossRU) or dEntry.bossEN or dEntry.bossRU or "Boss"
    local difficultyTitle = (isRU and dEntry.difficultyRU) or dEntry.difficultyEN or dEntry.difficultyRU or "Normal"
    local zoneTitle = (isRU and dEntry.zoneRU) or dEntry.zoneEN or dEntry.zoneRU or instanceTitle
    local howToGet = (isRU and dEntry.howToGetRU) or dEntry.howToGetEN or dEntry.howToGetRU or ""

    local currentCharKey = self:GetCharKey()
    local eligibleChars = {}
    local underleveledChars = {}
    local readyCount = 0
    local isLockedOnCurrentChar = false

    if self.db and type(self.db.chars) == "table" then
        for charKey, cData in pairs(self.db.chars) do
            if type(cData) == "table" then
                local lvl = tonumber(cData.level) or 1
                local isLocked = IsCharLockedForDungeonEntry(cData, dEntry, now)
                if charKey == currentCharKey then
                    isLockedOnCurrentChar = isLocked
                end
                local entry = {
                    charKey = charKey,
                    name = cData.name or charKey,
                    realm = cData.realm or "",
                    class = cData.class,
                    level = lvl,
                    isCurrent = (charKey == currentCharKey),
                    isLocked = isLocked,
                    coloredName = FormatClassColoredChar(cData.name or charKey, cData.class, lvl),
                }
                if lvl >= minLevel then
                    table.insert(eligibleChars, entry)
                    if not isLocked then
                        readyCount = readyCount + 1
                    end
                else
                    table.insert(underleveledChars, entry)
                end
            end
        end
    end

    table.sort(eligibleChars, function(a, b)
        if a.isCurrent ~= b.isCurrent then
            return a.isCurrent
        end
        if a.isLocked ~= b.isLocked then
            return not a.isLocked
        end
        if a.level ~= b.level then
            return a.level > b.level
        end
        return tostring(a.name) < tostring(b.name)
    end)

    table.sort(underleveledChars, function(a, b)
        if a.level ~= b.level then
            return a.level > b.level
        end
        return tostring(a.name) < tostring(b.name)
    end)

    return {
        mountID = mountID,
        name = name or dEntry.nameRU or dEntry.nameEN or ("Mount #" .. tostring(mountID)),
        spellID = spellID or dEntry.spellID,
        icon = icon,
        isCollected = isCollected,
        sourceKind = dEntry.sourceKind or "RAID",
        eventTitle = eventTitle,
        instanceTitle = instanceTitle,
        bossTitle = bossTitle,
        difficultyTitle = difficultyTitle,
        zoneTitle = zoneTitle,
        howToGet = howToGet,
        chance = chance,
        chancePct = chancePct,
        lockoutType = dEntry.lockoutType or "WEEKLY",
        lockoutTitle = lockoutTitle,
        minLevel = minLevel,
        mapID = dEntry.mapID,
        x = dEntry.x,
        y = dEntry.y,
        isLockedOnCurrentChar = isLockedOnCurrentChar,
        eligibleChars = eligibleChars,
        underleveledChars = underleveledChars,
        readyCount = readyCount,
        totalEligible = #eligibleChars,
        entry = dEntry,
    }
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
eventFrame:RegisterEvent("NEW_MOUNT_ADDED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("LOOT_READY")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

local function CheckActiveQuestChainProgress()
    if addon.RefreshRadarUI then
        addon:RefreshRadarUI()
    end
    if not addon.activeQuestGuideMountID then return end
    local status = addon:GetMountQuestChainStatus(addon.activeQuestGuideMountID)
    if not status or status.isCollected then
        addon.activeQuestGuideMountID = nil
        addon.activeQuestGuideStepIndex = nil
        return
    end
    if status.currentStepIndex and addon.activeQuestGuideStepIndex and status.currentStepIndex ~= addon.activeQuestGuideStepIndex then
        addon.activeQuestGuideStepIndex = status.currentStepIndex
        local st = status.currentStep
        if st then
            print(string.format(L.CHAT_QUEST_STEP_ADVANCED, status.name, st.title))
            addon:NavigateMountQuestStep(addon.activeQuestGuideMountID, status.currentStepIndex, true)
        end
    end
end

-- Хук на открытие сумок/сундуков/тыкв с маунтами (Заполненная добычей тыква, Коробка в виде сердца, Сундуки идеала и т.д.)
local function OnPossibleMountContainerUsed(itemID)
    if not itemID or not addon.MountsBySourceItem or not addon.MountsBySourceItem[itemID] then return end
    local mountList = addon.MountsBySourceItem[itemID]
    local itemName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ("Item #" .. tostring(itemID))
    C_Timer.After(0.6, function()
        for _, mountID in ipairs(mountList) do
            addon:RecordAttempt(mountID, itemName)
        end
    end)
end

if C_Container and C_Container.UseContainerItem and hooksecurefunc then
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
        if C_Container.GetContainerItemID and SafeNotSecret(bag) and SafeNotSecret(slot) then
            local ok, itemID = pcall(C_Container.GetContainerItemID, bag, slot)
            if ok and itemID and SafeNotSecret(itemID) then
                OnPossibleMountContainerUsed(itemID)
            end
        end
    end)
end

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
        elseif loadedName == "Blizzard_WorldMap" then
            if addon.InitWorldMapPins then
                addon:InitWorldMapPins()
            end
        elseif loadedName == "Rarity" then
            addon:BuildMountIndex()
            addon:ScanAllCharacterStatistics()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if RequestRaidInfo then
            pcall(RequestRaidInfo)
        end
        C_Timer.After(1.5, function()
            addon:BuildMountIndex()
            addon:SnapshotPreLockedRares()
            addon:ScanAllCharacterStatistics()
            addon:ScanCurrentCharacterLockouts()
            if C_AddOns and C_AddOns.IsAddOnLoaded then
                if C_AddOns.IsAddOnLoaded("Blizzard_Collections") and addon.HookMountJournal then
                    addon:HookMountJournal()
                end
                if C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") and addon.InitWorldMapPins then
                    addon:InitWorldMapPins()
                end
            end
            if addon.UpdateLDBText then
                addon:UpdateLDBText()
            end
        end)
    elseif event == "UPDATE_INSTANCE_INFO" or event == "PLAYER_LEVEL_UP" then
        addon:ScanCurrentCharacterLockouts()
        if addon.RefreshRadarUI then
            addon:RefreshRadarUI()
        end
    elseif event == "NEW_MOUNT_ADDED" then
        addon:BuildMountIndex()
        if addon.UpdateLDBText then
            addon:UpdateLDBText()
        end
        if addon.RefreshWorldMapPins then
            addon:RefreshWorldMapPins()
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        addon:SnapshotPreLockedRares()
        if addon.UpdateLDBText then
            addon:UpdateLDBText()
        end
        if addon.RefreshRadarUI then
            addon:RefreshRadarUI()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(2.0, function()
            addon:CheckRecentlyKilledRares()
        end)
    elseif event == "PLAYER_TARGET_CHANGED" then
        addon:CheckUnitForMountDrop("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        addon:CheckUnitForMountDrop("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        addon:CheckUnitForMountDrop(unit)
    elseif event == "LOOT_READY" then
        if GetNumLootItems and GetLootSourceInfo then
            local seenGuids = {}
            local numItems = GetNumLootItems() or 0
            for slot = 1, numItems do
                local okSrc, srcInfo = pcall(function() return { GetLootSourceInfo(slot) } end)
                if okSrc and type(srcInfo) == "table" then
                    for i = 1, #srcInfo, 2 do
                        local srcGuid = srcInfo[i]
                        if srcGuid and SafeNotSecret(srcGuid) and not seenGuids[srcGuid] then
                            seenGuids[srcGuid] = true
                            local npcID = addon:GetNPCIDFromGUID(srcGuid)
                            if npcID and addon.MountsByNpc[npcID] then
                                local rs = addon.RareScannerNpcToMounts and addon.RareScannerNpcToMounts[npcID]
                                local srcName = (addon.KnownNpcNames and addon.KnownNpcNames[npcID])
                                    or (rs and rs.name and rs.name ~= "" and rs.name)
                                    or ("NPC #" .. tostring(npcID))
                                local isLocked, lockQid = addon:IsNpcLockedToday(npcID)
                                local now = GetTime()
                                local wasSpottedUnlocked = addon.RecentlySpottedUnlockedRares and addon.RecentlySpottedUnlockedRares[npcID] and ((now - addon.RecentlySpottedUnlockedRares[npcID]) < 600)
                                local wasNotPreCompleted = lockQid and (not addon.CompletedRareQuestsSnapshot or addon.CompletedRareQuestsSnapshot[lockQid] ~= true)
                                if isLocked and (wasSpottedUnlocked or wasNotPreCompleted) then
                                    if addon.RecentlySpottedUnlockedRares then
                                        addon.RecentlySpottedUnlockedRares[npcID] = nil
                                    end
                                    if lockQid then
                                        addon.CompletedRareQuestsSnapshot = addon.CompletedRareQuestsSnapshot or {}
                                        addon.CompletedRareQuestsSnapshot[lockQid] = true
                                        addon.JustCompletedLockoutQuestAt = addon.JustCompletedLockoutQuestAt or {}
                                        addon.JustCompletedLockoutQuestAt[lockQid] = now
                                    end
                                end
                                local justTurnedIn = lockQid and addon.JustCompletedLockoutQuestAt and addon.JustCompletedLockoutQuestAt[lockQid] and ((now - addon.JustCompletedLockoutQuestAt[lockQid]) < 120)
                                if isLocked and not justTurnedIn then
                                    addon.SkipLockoutNoticeAt = addon.SkipLockoutNoticeAt or {}
                                    if not addon.SkipLockoutNoticeAt[npcID] or (now - addon.SkipLockoutNoticeAt[npcID]) > 60 then
                                        addon.SkipLockoutNoticeAt[npcID] = now
                                        if addon.db and addon.db.settings and addon.db.settings.announceAttempts then
                                            print(string.format(L.CHAT_ATTEMPT_SKIPPED_LOCKOUT, srcName))
                                        end
                                    end
                                else
                                    for _, mountID in ipairs(addon.MountsByNpc[npcID]) do
                                        addon:RecordAttempt(mountID, srcName)
                                    end
                                    if addon.RefreshWorldMapPins then
                                        addon:RefreshWorldMapPins()
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        if questID and SafeNotSecret(questID) then
            addon.JustCompletedLockoutQuestAt = addon.JustCompletedLockoutQuestAt or {}
            addon.JustCompletedLockoutQuestAt[questID] = GetTime()
            addon.CompletedRareQuestsSnapshot = addon.CompletedRareQuestsSnapshot or {}
            addon.CompletedRareQuestsSnapshot[questID] = true

            local matchedNpcName = nil
            if addon.RareScannerNpcToMounts then
                for nid, rsData in pairs(addon.RareScannerNpcToMounts) do
                    if rsData and type(rsData.quests) == "table" then
                        for _, rq in ipairs(rsData.quests) do
                            if rq == questID then
                                matchedNpcName = (addon.KnownNpcNames and addon.KnownNpcNames[nid]) or rsData.name
                                break
                            end
                        end
                    end
                    if matchedNpcName then break end
                end
            end

            for mountID, info in pairs(addon.DropInfoByMount) do
                if type(info.quests) == "table" then
                    for _, qid in ipairs(info.quests) do
                        if qid == questID then
                            addon:RecordAttempt(mountID, matchedNpcName or info.boss or "Rare")
                            break
                        end
                    end
                end
            end
            if addon.RefreshWorldMapPins then
                addon:RefreshWorldMapPins()
            end
        end
        C_Timer.After(0.5, CheckActiveQuestChainProgress)
    elseif event == "QUEST_ACCEPTED" then
        C_Timer.After(0.5, CheckActiveQuestChainProgress)
    elseif event == "ENCOUNTER_END" then
        local _, encounterName, _, _, success = ...
        if success == 1 and SafeNotSecret(encounterName) and encounterName then
            for mountID, info in pairs(addon.DropInfoByMount) do
                local matched = false
                for _, bName in ipairs({ info.boss, info.bossRU, info.bossEN }) do
                    if bName and bName ~= "" and (bName == encounterName or string.find(encounterName, bName, 1, true) or string.find(bName, encounterName, 1, true)) then
                        matched = true
                        break
                    end
                end
                if matched then
                    addon:RecordAttempt(mountID, encounterName)
                end
            end
            if RequestRaidInfo then
                pcall(RequestRaidInfo)
            end
            C_Timer.After(2.0, function()
                addon:ScanAllCharacterStatistics()
                addon:ScanCurrentCharacterLockouts()
                if addon.RefreshRadarUI then
                    addon:RefreshRadarUI()
                end
            end)
        end
    end
end)
