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
addon.DropInfoByMount = {}
addon.MountQuestsByMountID = {}
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
    wipe(self.DropInfoByMount)
    wipe(self.MountQuestsByMountID)
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

    if preferredMapID then
        for _, c in ipairs(info.coords) do
            if c.m == preferredMapID and c.x and c.x > 0 and c.y and c.y > 0 then
                return c
            end
        end
    end
    for _, c in ipairs(info.coords) do
        if c.x and c.x > 0 and c.y and c.y > 0 then
            return c
        end
    end
    return nil
end

-- Поставить метку на карте и 3D-стрелку (Blizzard UserWaypoint + SuperTrack + TomTom)
function addon:SetMountWaypoint(mountID, preferredMapID, liveX, liveY, customLabel, silent)
    local name = C_MountJournal and C_MountJournal.GetMountInfoByID(mountID) or "Mount"
    local info = self.DropInfoByMount[mountID]
    local mapID = preferredMapID or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    local x, y = liveX, liveY
    local npcLabel = customLabel or (info and info.boss) or name

    if not x or not y or x <= 0 or y <= 0 then
        local c = self:GetBestMountCoords(mountID, mapID)
        if c then
            mapID = c.m
            x = c.x
            y = c.y
            if not customLabel and c.n and c.n ~= "" then
                npcLabel = c.n
            end
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
        print(string.format(L.CHAT_WAYPOINT_SET, npcLabel, dispX, dispY, name))
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
    local primaryCoord = coords[1]
    for _, c in ipairs(coords) do
        if playerMapID and c.m == playerMapID then
            primaryCoord = c
            break
        end
    end

    if _G.TomTom and _G.TomTom.AddWaypoint then
        for idx, c in ipairs(coords) do
            local nx = (c.x > 1) and (c.x / 100.0) or c.x
            local ny = (c.y > 1) and (c.y / 100.0) or c.y
            local label = (c.n and c.n ~= "") and c.n or (info and info.boss) or name
            if #coords > 1 then
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
        for _, qid in ipairs(info.quests) do
            if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                table.insert(doneQuests, "#" .. tostring(qid))
            else
                table.insert(availQuests, "#" .. tostring(qid))
            end
        end
        if #doneQuests > 0 then
            table.insert(lines, string.format(L.LUA_LOCKOUT_LOCKED_FMT, table.concat(doneQuests, ", ")))
        else
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
                add(string.format("  %d. %s (mapID=%s) [%.1f, %.1f] — %s", i, mName, tostring(c.m), c.x or 0, c.y or 0, tostring(c.n or "")))
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
    if self.RefreshWorldMapPins then
        self:RefreshWorldMapPins()
    end
end

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
    if not SafeNotSecret(npcName) then
        local rs = self.RareScannerNpcToMounts and self.RareScannerNpcToMounts[npcID]
        npcName = (rs and rs.name) or "Rare NPC"
    end

    for _, mountID in ipairs(mounts) do
        local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if not isCollected then
            self:TriggerRareMountAlert(mountID, npcID, npcName, false)
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
                        locked = self:IsMountRareLockedToday(mountID),
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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("NEW_MOUNT_ADDED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("LOOT_READY")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

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
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.5, function()
            addon:BuildMountIndex()
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
    elseif event == "NEW_MOUNT_ADDED" then
        addon:BuildMountIndex()
        if addon.UpdateLDBText then
            addon:UpdateLDBText()
        end
        if addon.RefreshWorldMapPins then
            addon:RefreshWorldMapPins()
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
                                for _, mountID in ipairs(addon.MountsByNpc[npcID]) do
                                    addon:RecordAttempt(mountID, "NPC #" .. tostring(npcID))
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
            for mountID, info in pairs(addon.DropInfoByMount) do
                if type(info.quests) == "table" then
                    for _, qid in ipairs(info.quests) do
                        if qid == questID then
                            addon:RecordAttempt(mountID, info.boss or "Rare")
                            break
                        end
                    end
                end
            end
        end
        C_Timer.After(0.5, CheckActiveQuestChainProgress)
    elseif event == "QUEST_ACCEPTED" then
        C_Timer.After(0.5, CheckActiveQuestChainProgress)
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
