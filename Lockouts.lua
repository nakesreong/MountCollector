local _, addon = ...

-- ============================================================================
-- MountCollector — Lockouts.lua
-- Модуль учёта попыток (траев) и суточных/недельных КД рарников и твинков аккаунта:
--   * Подсчёт предметов в сумках/банке/банке отряда и 3-дневного КД Уникальных яиц
--     (GetRequirementItemCount, HasUniqueIncubationEggOnChar)
--   * Сканирование серверной статистики убийств боссов и учёт траев по аккаунту
--     (ScanAllCharacterStatistics, GetMountAttempts, SetManualMountAttempts, RecordAttempt)
--   * Проверка суточного КД и таймеров респавна рарников
--     (IsNpcLockedToday, IsMountRareLockedToday, SnapshotPreLockedRares, CheckRecentlyKilledRares)
--   * Радар несобранных дроп-маунтов текущей локации (GetZoneUncollectedMounts)
--   * Сохранение актуального уровня, класса и недельных/суточных КД инстансов персонажа
--     в MountCollectorDB.chars (ScanCurrentCharacterLockouts)
-- ============================================================================

local L = addon.L
local SafeNotSecret = addon.SafeNotSecret

-- Получить количество предмета в сумках/банке/банке отряда или статус игрушки (11.x / 12.x C_Item API)
function addon:GetRequirementItemCount(itemID, charOnly)
    if not itemID or itemID <= 0 then return 0, nil end
    local itemName = (self.GetItemDisplayName and self:GetItemDisplayName(itemID))
        or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
        or ("Item #" .. tostring(itemID))
    if PlayerHasToy and PlayerHasToy(itemID) then
        return 1, itemName
    end
    local count = 0
    if C_Item and C_Item.GetItemCount then
        local ok, c = pcall(C_Item.GetItemCount, itemID, true, false, not charOnly, not charOnly)
        if ok and type(c) == "number" then
            count = c
        end
    end
    return count, itemName
end

-- Маунты, вылупляющиеся из УНИКАЛЬНЫХ инкубационных яиц (пока одно яйцо зреет 3 дня в сумке/банке персонажа, новое упасть НЕ МОЖЕТ!)
local UniqueIncubationEggByMount = {
    [538] = { rawEggID = 94295, crackedEggID = 94296, days = 3 }, -- Красный перворожденный ящер (Red Primal Raptor)
    [539] = { rawEggID = 94295, crackedEggID = 94296, days = 3 }, -- Черный перворожденный ящер (Black Primal Raptor)
    [540] = { rawEggID = 94295, crackedEggID = 94296, days = 3 }, -- Зеленый перворожденный ящер (Green Primal Raptor)
    [265] = { rawEggID = 39878, crackedEggID = 39883, days = 3 }, -- Зеленый протодракон (Green Proto-Drake)
}

function addon:HasUniqueIncubationEggOnChar(mountID)
    local cfg = mountID and UniqueIncubationEggByMount[mountID]
    if not cfg then return false, nil, nil, nil, nil end
    local crackedCnt, crackedName = self:GetRequirementItemCount(cfg.crackedEggID, true)
    if crackedCnt and crackedCnt > 0 then
        return true, "CRACKED", cfg.crackedEggID, crackedName, cfg
    end
    local rawCnt, rawName = self:GetRequirementItemCount(cfg.rawEggID, true)
    if rawCnt and rawCnt > 0 then
        return true, "INCUBATING", cfg.rawEggID, rawName, cfg
    end
    return false, nil, cfg.rawEggID, rawName, cfg
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

    local mergedMap = (self.db.settings and type(self.db.settings.mergedChars) == "table") and self.db.settings.mergedChars or nil
    local externalCharStats = {}
    for cKey, stMap in pairs(SeededRarityCharStats) do
        local resolvedKey = (mergedMap and mergedMap[cKey]) or cKey
        externalCharStats[resolvedKey] = stMap
    end
    local rProfile = (_G.Rarity and _G.Rarity.db and _G.Rarity.db.profile)
        or (_G.RarityDB and _G.RarityDB.profiles and _G.RarityDB.profiles.Default)
    if rProfile and type(rProfile.accountWideStatistics) == "table" then
        for _, pData in pairs(rProfile.accountWideStatistics) do
            if type(pData) == "table" and pData.playerName and pData.server and type(pData.statistics) == "table" then
                local rawKey = pData.playerName .. " - " .. pData.server
                local resolvedKey = (mergedMap and mergedMap[rawKey]) or rawKey
                externalCharStats[resolvedKey] = pData.statistics
            end
        end
    end

    for mountID, info in pairs(self.DropInfoByMount) do
        local record = self.db.attempts[mountID]
        local hasStats = info.stats and #info.stats > 0

        local rarityTotal = (info.rarityKey and SeededRarityMountTotals[info.rarityKey]) or 0
        if rProfile and rProfile.groups and rProfile.groups.mounts and info.rarityKey then
            local rEntry = rProfile.groups.mounts[info.rarityKey]
            if rEntry and type(rEntry.attempts) == "number" and rEntry.attempts > rarityTotal then
                rarityTotal = rEntry.attempts
            end
        end

        if hasStats then
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
        elseif info.method == "COLLECTION" and type(info.sourceItems) == "table" and #info.sourceItems == 1 then
            local colCount = self:GetRequirementItemCount(info.sourceItems[1])
            if colCount > 0 then
                record = record or { total = 0, byChar = {} }
                record.byChar = record.byChar or {}
                record.byChar[charKey] = colCount
                if not record.manualTotal then
                    record.total = colCount
                end
            end
        elseif info.quests and #info.quests > 0 and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
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

    local name = self:GetMountInfoByID(mountID) or ("Mount #" .. tostring(mountID))
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

    if info and info.method == "COLLECTION" and type(info.sourceItems) == "table" and #info.sourceItems == 1 then
        local colCount = self:GetRequirementItemCount(info.sourceItems[1])
        local charKey = self:GetCharKey()
        record = record or { total = 0, byChar = {} }
        record.byChar = record.byChar or {}
        if colCount > 0 then
            record.byChar[charKey] = colCount
            if not record.manualTotal then
                record.total = colCount
            end
            self.db.attempts[mountID] = record
        end
        local finalCol = (record.manualTotal and math.max(record.manualTotal, colCount)) or math.max(colCount, record.total or 0)
        return finalCol, record.byChar, info
    end

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

function addon:RecordAttempt(mountID, sourceName, allowRapidMultiKill)
    if not mountID or not self.db then return end
    local name, _, _, _, _, _, _, _, _, _, isCollected = self:GetMountInfoByID(mountID)
    if isCollected then return end

    local info = self.DropInfoByMount[mountID]
    if info and info.method == "COLLECTION" and type(info.sourceItems) == "table" and #info.sourceItems == 1 then
        self:GetMountAttempts(mountID)
        if self.UpdateLDBText then self:UpdateLDBText() end
        if self.RefreshRadarUI then self:RefreshRadarUI() end
        return
    end

    if self:HasUniqueIncubationEggOnChar(mountID) then
        return
    end

    local now = GetTime()
    if not allowRapidMultiKill then
        if self.RecentAttemptLock[mountID] and (now - self.RecentAttemptLock[mountID]) < 90 then
            return
        end
    end
    self.RecentAttemptLock[mountID] = now

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

    local rEntry = info and info.rarityEntry
    local rarityAlreadyAnnounces = (_G.Rarity and rEntry and _G.Rarity.db and _G.Rarity.db.profile and _G.Rarity.db.profile.enableAnnouncements ~= false)
    self.LastAttemptChatAt = self.LastAttemptChatAt or {}
    if self.db.settings.announceAttempts and not rarityAlreadyAnnounces and (not self.LastAttemptChatAt[mountID] or (now - self.LastAttemptChatAt[mountID]) > 2.5) then
        self.LastAttemptChatAt[mountID] = now
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

-- Интервалы респавна для рарников без суточного КД (можно фармить повторно после респавна)
local RareRespawnWindowByNpc = {
    [32491]  = { ru = "2–8 ч.",      en = "2–8 hrs",    maxAge = 28800, noDailyLock = true }, -- Затерянный во времени протодракон
    [50005]  = { ru = "4–8 ч.",      en = "4–8 hrs",    maxAge = 28800, noDailyLock = true }, -- Посейдус
    [50062]  = { ru = "2–8 ч.",      en = "2–8 hrs",    maxAge = 28800, noDailyLock = true }, -- Эонакс
    [50883]  = { ru = "2–8 ч.",      en = "2–8 hrs",    maxAge = 28800, noDailyLock = true }, -- Бегун
    [50981]  = { ru = "2–8 ч.",      en = "2–8 hrs",    maxAge = 28800, noDailyLock = true }, -- Лук'хок
    [50985]  = { ru = "48–96 ч.",    en = "48–96 hrs",  maxAge = 86400, noDailyLock = true }, -- Кулак
    [50990]  = { ru = "2–8 ч.",      en = "2–8 hrs",    maxAge = 28800, noDailyLock = true }, -- Накк Громовержец
    [50992]  = { ru = "2–8 ч.",      en = "2–8 hrs",    maxAge = 28800, noDailyLock = true }, -- Горок
    [51015]  = { ru = "2–8 ч.",      en = "2–8 hrs",    maxAge = 28800, noDailyLock = true }, -- Шкурохлест
    [69768]  = { ru = "30–60 мин.",  en = "30–60 min",  maxAge = 5400,  noDailyLock = true }, -- Зандаларский военный разведчик
    [69769]  = { ru = "30–60 мин.",  en = "30–60 min",  maxAge = 5400,  noDailyLock = true }, -- Зандаларский завоеватель
    [69841]  = { ru = "30–60 мин.",  en = "30–60 min",  maxAge = 5400,  noDailyLock = true }, -- Зандаларский завоеватель
    [69842]  = { ru = "30–60 мин.",  en = "30–60 min",  maxAge = 5400,  noDailyLock = true }, -- Зандаларский завоеватель
    [73167]  = { ru = "30–60 мин.",  en = "30–60 min",  maxAge = 5400,  noDailyLock = true }, -- Хуолон
    [81001]  = { ru = "15–30 мин.",  en = "15–30 min",  maxAge = 3600,  noDailyLock = true }, -- Нок-Карош
    [163042] = { ru = "1–2 ч.",      en = "1–2 hrs",    maxAge = 7200,  noDailyLock = true }, -- Слоновый облачный змей
    [195353] = { ru = "60–120 мин.", en = "60–120 min", maxAge = 7200,  noDailyLock = true }, -- Ветрогрыз (Breezebiter)
}

function addon:RecordRareKillTimestamp(npcID)
    if not npcID then return end
    self.KilledRareNpcIDsToday = self.KilledRareNpcIDsToday or {}
    self.KilledRareNpcIDsToday[npcID] = GetTime()
    if self.db then
        self.db.lastRareKills = self.db.lastRareKills or {}
        self.db.lastRareKills[npcID] = time()
    end
end

function addon:GetRareRespawnTimerText(npcID)
    if not npcID then return nil end
    local rs = self.RareScannerNpcToMounts and self.RareScannerNpcToMounts[npcID]
    local primaryQid = (rs and type(rs.quests) == "table" and rs.quests[1]) or nil
    local cfg = RareRespawnWindowByNpc[npcID]
    if primaryQid and not (cfg and cfg.noDailyLock) then
        return nil
    end

    local killedEpoch = self.db and self.db.lastRareKills and self.db.lastRareKills[npcID]
    local elapsed = nil
    if type(killedEpoch) == "number" and killedEpoch > 0 then
        elapsed = time() - killedEpoch
    elseif self.KilledRareNpcIDsToday and type(self.KilledRareNpcIDsToday[npcID]) == "number" then
        elapsed = GetTime() - self.KilledRareNpcIDsToday[npcID]
    end
    if not elapsed or elapsed < 0 then return nil end

    local maxAge = (cfg and cfg.maxAge) or 5400
    if elapsed > maxAge then return nil end

    local isRU = (self:GetActiveLocaleCode() == "ruRU")
    local respWindow = (cfg and (isRU and cfg.ru or cfg.en)) or (isRU and "30–60 мин." or "30–60 min")
    local minsAgo = math.max(1, math.floor(elapsed / 60 + 0.5))

    if elapsed < 900 then
        local hideLeft = math.max(1, math.ceil((900 - elapsed) / 60))
        if isRU then
            return string.format("|cffffaa00Убит %d мин. назад (респавн ~%s, метка через %d мин.)|r", minsAgo, respWindow, hideLeft), true
        else
            return string.format("|cffffaa00Killed %d min ago (respawn ~%s, pin in %d min)|r", minsAgo, respWindow, hideLeft), true
        end
    else
        if isRU then
            return string.format("|cffffd100Убит %d мин. назад (респавн ~%s)|r", minsAgo, respWindow), false
        else
            return string.format("|cffffd100Killed %d min ago (respawn ~%s)|r", minsAgo, respWindow), false
        end
    end
end

function addon:GetMountRespawnTimerText(mountID)
    local info = mountID and self.DropInfoByMount and self.DropInfoByMount[mountID]
    if not info or not info.npcs then return nil end
    local bestText = nil
    local bestElapsed = math.huge
    for npcID in pairs(info.npcs) do
        local txt = self:GetRareRespawnTimerText(npcID)
        if txt then
            local killedEpoch = self.db and self.db.lastRareKills and self.db.lastRareKills[npcID]
            local el = (killedEpoch and (time() - killedEpoch)) or 0
            if el >= 0 and el < bestElapsed then
                bestElapsed = el
                bestText = txt
            end
        end
    end
    return bestText
end

function addon:IsNpcLockedToday(npcID)
    if not npcID then
        return false, nil
    end
    local rs = self.RareScannerNpcToMounts and self.RareScannerNpcToMounts[npcID]
    local primaryQid = (rs and type(rs.quests) == "table" and rs.quests[1]) or nil
    if not primaryQid and self.MountsByNpc and self.MountsByNpc[npcID] then
        for _, mID in ipairs(self.MountsByNpc[npcID]) do
            local info = self.DropInfoByMount and self.DropInfoByMount[mID]
            if info and type(info.quests) == "table" and #info.quests == 1 then
                primaryQid = info.quests[1]
                break
            end
        end
    end

    local isRepeatableTimerRare = (RareRespawnWindowByNpc[npcID] and RareRespawnWindowByNpc[npcID].noDailyLock) or (not primaryQid and npcID < 110000)

    if isRepeatableTimerRare and self.db and self.db.lastRareKills and self.db.lastRareKills[npcID] then
        local elapsedEpoch = time() - self.db.lastRareKills[npcID]
        if elapsedEpoch >= 0 and elapsedEpoch < 900 then
            return true, nil
        end
    end

    if self.KilledRareNpcIDsToday and self.KilledRareNpcIDsToday[npcID] then
        local killedAt = self.KilledRareNpcIDsToday[npcID]
        if isRepeatableTimerRare then
            if type(killedAt) == "number" and (GetTime() - killedAt) < 900 then
                return true, nil
            end
        elseif primaryQid or npcID >= 110000 or type(killedAt) ~= "number" or (GetTime() - killedAt) < 900 then
            return true, primaryQid
        end
    end

    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        return false, primaryQid
    end
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
            if info and type(info.quests) == "table" and #info.quests > 0 then
                local numNpcs = 0
                if info.npcs then
                    for _ in pairs(info.npcs) do numNpcs = numNpcs + 1 end
                end
                if #info.quests == 1 or numNpcs <= 1 then
                    for _, qid in ipairs(info.quests) do
                        if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                            return true, qid
                        end
                    end
                    return false, info.quests[1]
                end
            end
        end
    end
    return false, nil
end

function addon:IsMountRareLockedToday(mountID)
    if self:HasUniqueIncubationEggOnChar(mountID) then
        return true, 1, 1
    end
    local info = self.DropInfoByMount[mountID]
    if not info then
        return false, 0, 0
    end

    if info.npcs and self.RareScannerNpcToMounts then
        local groups = {}
        local groupOrder = {}
        for npcID in pairs(info.npcs) do
            local rs = self.RareScannerNpcToMounts[npcID]
            if rs then
                local gKey
                if type(rs.quests) == "table" and #rs.quests > 0 then
                    local qCopy = {}
                    for _, qid in ipairs(rs.quests) do table.insert(qCopy, qid) end
                    table.sort(qCopy)
                    gKey = "q:" .. table.concat(qCopy, ",")
                else
                    gKey = "npc:" .. tostring(npcID)
                end
                if not groups[gKey] then
                    groups[gKey] = { locked = false }
                    table.insert(groupOrder, gKey)
                end
                if self:IsNpcLockedToday(npcID) then
                    groups[gKey].locked = true
                end
            end
        end
        if #groupOrder > 0 then
            local doneCount = 0
            local totalCount = #groupOrder
            for _, gKey in ipairs(groupOrder) do
                if groups[gKey].locked then
                    doneCount = doneCount + 1
                end
            end
            return (doneCount >= totalCount and totalCount > 0), doneCount, totalCount
        end
    end

    if not info.quests or #info.quests == 0 then
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
    local numNpcs = 0
    if info.npcs then
        for _ in pairs(info.npcs) do numNpcs = numNpcs + 1 end
    end
    if numNpcs <= 1 and doneCount > 0 then
        return true, 1, 1
    end
    return (doneCount >= totalCount and totalCount > 0), doneCount, totalCount
end

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

function addon:CheckRecentlyKilledRares()
    if not self.RecentlySpottedUnlockedRares then return end
    local now = GetTime()
    for npcID, spottedAt in pairs(self.RecentlySpottedUnlockedRares) do
        if (now - spottedAt) < 600 then
            local isLocked, lockQid = self:IsNpcLockedToday(npcID)
            if isLocked then
                self.RecentlySpottedUnlockedRares[npcID] = nil
                self:RecordRareKillTimestamp(npcID)
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
                self:SyncActiveTourAfterKillOrAlert(npcID)
            end
        else
            self.RecentlySpottedUnlockedRares[npcID] = nil
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
                local name, spellID, icon, _, _, _, _, _, _, _, isCollected = self:GetMountInfoByID(mountID)
                if name and not isCollected then
                    local attempts, _, info = self:GetMountAttempts(mountID)
                    local globalRarity = self:GetGlobalRarity(mountID)
                    local bestCoord = self:GetBestMountCoords(mountID, mid)
                    local locked, lockedCount, totalLockoutCount = self:IsMountRareLockedToday(mountID)
                    local dStatus = self.GetDungeonMountStatus and self:GetDungeonMountStatus(mountID) or nil
                    local isWorldBoss = (dStatus and dStatus.sourceKind == "WORLD_BOSS") or false
                    if isWorldBoss and dStatus then
                        locked = dStatus.isLockedOnCurrentChar
                    end
                    local bestNpcName = bestCoord and self:GetNpcDisplayName(bestCoord.npcID, (bestCoord.n and bestCoord.n ~= "" and bestCoord.n) or nil) or nil
                    table.insert(results, {
                        mountID = mountID,
                        name = name,
                        spellID = spellID,
                        icon = icon,
                        attempts = attempts,
                        chance = (dStatus and dStatus.chance) or (info and info.chance) or nil,
                        boss = (dStatus and dStatus.bossTitle) or bestNpcName or (info and info.boss) or nil,
                        method = isWorldBoss and "WORLD_BOSS" or (info and info.method or "NPC"),
                        isWorldBoss = isWorldBoss,
                        readyCount = dStatus and dStatus.readyCount or nil,
                        totalEligible = dStatus and dStatus.totalEligible or nil,
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

-- Слить запись старого ника / прошлого сервера (oldCharKey) в текущего персонажа без задвоения траев
function addon:MergeCharacterIntoCurrent(oldCharKey, silent)
    if not self.db or not oldCharKey then return false end
    local currentKey = self:GetCharKey()
    if not currentKey or oldCharKey == currentKey then return false end

    self.db.chars = self.db.chars or {}
    local curData = self.db.chars[currentKey]
    local oldData = self.db.chars[oldCharKey]
    local now = time()

    if type(curData) == "table" and type(oldData) == "table" then
        for _, tblKey in ipairs({ "savedInstances", "savedInstanceNames", "savedLfg", "savedQuests" }) do
            if type(oldData[tblKey]) == "table" then
                curData[tblKey] = curData[tblKey] or {}
                for k, exp in pairs(oldData[tblKey]) do
                    if type(exp) == "number" and exp > now then
                        curData[tblKey][k] = math.max(curData[tblKey][k] or 0, exp)
                    end
                end
            end
        end
    end

    if type(self.db.attempts) == "table" then
        for _, rec in pairs(self.db.attempts) do
            if type(rec) == "table" and type(rec.byChar) == "table" and rec.byChar[oldCharKey] ~= nil then
                local oldVal = tonumber(rec.byChar[oldCharKey]) or 0
                local curVal = tonumber(rec.byChar[currentKey]) or 0
                rec.byChar[currentKey] = math.max(curVal, oldVal)
                rec.byChar[oldCharKey] = nil
                if not rec.manualTotal then
                    local newSum = 0
                    for _, c in pairs(rec.byChar) do
                        newSum = newSum + (tonumber(c) or 0)
                    end
                    rec.total = math.max(newSum, rec.manualTotal or 0)
                end
            end
        end
    end

    if self.db.settings then
        self.db.settings.mergedChars = self.db.settings.mergedChars or {}
        self.db.settings.mergedChars[oldCharKey] = currentKey
        for k, dst in pairs(self.db.settings.mergedChars) do
            if dst == oldCharKey then
                self.db.settings.mergedChars[k] = currentKey
            end
        end
    end

    self.db.chars[oldCharKey] = nil

    if not silent then
        print(string.format(L.CHAT_ALT_MERGED_FMT, tostring(oldCharKey), tostring(currentKey)))
        if self.RefreshRadarUI then self:RefreshRadarUI() end
        if self.RefreshMountJournalSideColumn then self:RefreshMountJournalSideColumn() end
        if self.RefreshAltManagerWindow then self:RefreshAltManagerWindow() end
    end
    return true
end

-- Убрать удалённого / ненужного твинка из ростера КД (общий счётчик траев аккаунта сохраняется!)
function addon:RemoveTrackedAlt(targetCharKey)
    if not self.db or not self.db.chars or not targetCharKey then return false end
    local currentKey = self:GetCharKey()
    if targetCharKey == currentKey then return false end
    if not self.db.chars[targetCharKey] then return false end

    self.db.chars[targetCharKey] = nil
    print(string.format(L.CHAT_ALT_REMOVED_FMT, tostring(targetCharKey)))

    if self.RefreshRadarUI then self:RefreshRadarUI() end
    if self.RefreshMountJournalSideColumn then self:RefreshMountJournalSideColumn() end
    if self.RefreshAltManagerWindow then self:RefreshAltManagerWindow() end
    if self.radarSettingsPanel and self.radarSettingsPanel.controls and self.radarSettingsPanel.controls.Refresh then
        self.radarSettingsPanel.controls:Refresh()
    end
    return true
end

-- Очистить всех твинков, на которых не заходили дольше daysThreshold дней (не трогая текущего чара и траи аккаунта)
function addon:PruneInactiveAlts(daysThreshold)
    if not self.db or not self.db.chars then return 0 end
    local days = math.max(1, tonumber(daysThreshold) or 30)
    local maxAgeSec = days * 86400
    local now = time()
    local currentKey = self:GetCharKey()
    local toRemove = {}

    for cKey, cData in pairs(self.db.chars) do
        if cKey ~= currentKey then
            local lastSeen = (type(cData) == "table") and tonumber(cData.lastSeen) or nil
            if not lastSeen or (now - lastSeen) > maxAgeSec then
                table.insert(toRemove, cKey)
            end
        end
    end

    for _, cKey in ipairs(toRemove) do
        self.db.chars[cKey] = nil
    end

    print(string.format(L.CHAT_ALT_PRUNED_FMT, days, #toRemove))
    if self.RefreshRadarUI then self:RefreshRadarUI() end
    if self.RefreshMountJournalSideColumn then self:RefreshMountJournalSideColumn() end
    if self.RefreshAltManagerWindow then self:RefreshAltManagerWindow() end
    if self.radarSettingsPanel and self.radarSettingsPanel.controls and self.radarSettingsPanel.controls.Refresh then
        self.radarSettingsPanel.controls:Refresh()
    end
    return #toRemove
end

-- Сканирование уровня, класса, GUID и активных КД инстансов/праздничных данжей текущего персонажа
function addon:ScanCurrentCharacterLockouts()
    if not self.db then return end
    self.db.chars = self.db.chars or {}

    local charKey = self:GetCharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Realm"
    local _, classFile = UnitClass("player")
    local level = UnitLevel("player") or 1
    local rawGUID = UnitGUID and UnitGUID("player") or nil
    local playerGUID = (SafeNotSecret(rawGUID) and type(rawGUID) == "string" and string.find(rawGUID, "^Player%-")) and rawGUID or nil
    local now = time()

    local cData = self.db.chars[charKey] or {}
    cData.name = name
    cData.realm = realm
    cData.class = classFile or cData.class or "PRIEST"
    cData.level = (level and level > 0) and level or (cData.level or 1)
    cData.guid = playerGUID or cData.guid
    cData.hidden = nil
    cData.lastSeen = now
    self.db.chars[charKey] = cData

    -- Авто-склейка ренеймов на том же сервере по совпадению постоянного GUID игрока
    if playerGUID then
        local duplicateKeys = {}
        for otherKey, otherData in pairs(self.db.chars) do
            if otherKey ~= charKey and type(otherData) == "table" and otherData.guid == playerGUID then
                table.insert(duplicateKeys, otherKey)
            end
        end
        for _, oldKey in ipairs(duplicateKeys) do
            self:MergeCharacterIntoCurrent(oldKey, true)
        end
    end
    cData.savedInstances = cData.savedInstances or {}
    cData.savedInstanceNames = cData.savedInstanceNames or {}
    cData.savedLfg = cData.savedLfg or {}
    cData.savedQuests = cData.savedQuests or {}

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
    for k, exp in pairs(cData.savedQuests) do
        if type(exp) ~= "number" or exp <= now then
            cData.savedQuests[k] = nil
        end
    end

    local dailyResetSec = (GetQuestResetTime and GetQuestResetTime()) or 86400
    if type(dailyResetSec) ~= "number" or dailyResetSec <= 0 or dailyResetSec > 172800 then
        dailyResetSec = 86400
    end
    local weeklyResetSec = (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()) or 604800
    if type(weeklyResetSec) ~= "number" or weeklyResetSec <= 0 or weeklyResetSec > 700000 then
        weeklyResetSec = 604800
    end

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

    if GetLFGDungeonRewards then
        for _, lfgID in ipairs({ 285, 287, 288 }) do
            local ok, doneToday = pcall(GetLFGDungeonRewards, lfgID)
            if ok and doneToday then
                cData.savedLfg[lfgID] = now + dailyResetSec
            end
        end
    end

    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and type(self.MountDungeonsDB) == "table" then
        for _, dEntry in ipairs(self.MountDungeonsDB) do
            if type(dEntry.questIDs) == "table" and #dEntry.questIDs > 0 then
                local expTime = (dEntry.lockoutType == "WEEKLY") and (now + weeklyResetSec) or (now + dailyResetSec)
                for _, qid in ipairs(dEntry.questIDs) do
                    if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                        cData.savedQuests[qid] = expTime
                    else
                        cData.savedQuests[qid] = nil
                    end
                end
            end
        end
    end

    self.db.chars[charKey] = cData
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
