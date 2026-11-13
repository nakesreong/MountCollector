local _, addon = ...

-- ============================================================================
-- MountCollector — Lockouts.lua
-- Модуль учёта попыток (траев), суточных/недельных КД твинков и квестовых цепочек:
--   * Оценка прогресса пошаговых квестовых цепочек и секретов (GetMountQuestChainStatus)
--   * Проверка особых условий получения и генерация Lua-отчёта (GetMountSpecialConditions, BuildMountDebugReport)
--   * Сканирование серверной статистики убийств боссов и учёт траев по аккаунту
--     (ScanAllCharacterStatistics, GetMountAttempts, SetManualMountAttempts, RecordAttempt)
--   * Проверка суточного КД рарников (IsNpcLockedToday, IsMountRareLockedToday, SnapshotPreLockedRares)
--   * Сканирование недельных/суточных КД всех твинков аккаунта по данжам, рейдам и ворлдбоссам
--     (ScanCurrentCharacterLockouts, GetDungeonMountStatus)
-- ============================================================================

local L = addon.L
local SafeNotSecret = addon.SafeNotSecret
local IsValidNpcName = addon.IsValidNpcName

-- Получить локализованное название квеста по его questID (из клиента или QuestNameDB)
function addon:GetQuestTitleByID(questID)
    if not questID or questID <= 0 then return nil end
    local locCode = self:GetActiveLocaleCode()
    if self.QuestNameDB and self.QuestNameDB[questID] then
        if locCode == "enUS" and self.QuestNameDB[questID].en and self.QuestNameDB[questID].en ~= "" then
            return self.QuestNameDB[questID].en
        elseif locCode == "ruRU" and self.QuestNameDB[questID].ru and self.QuestNameDB[questID].ru ~= "" then
            return self.QuestNameDB[questID].ru
        end
    end
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
        local isRU = (locCode == "ruRU")
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

-- Получить количество предмета в сумках/банке/банке отряда или статус игрушки
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
    elseif GetItemCount then
        count = GetItemCount(itemID, true) or 0
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

-- Оценка статуса пошаговой квестовой цепочки маунта через Lua API
function addon:GetMountQuestChainStatus(mountID)
    local chain = self.MountQuestsByMountID and self.MountQuestsByMountID[mountID]
    if not chain or type(chain.steps) ~= "table" then return nil end

    local isRU = (self:GetActiveLocaleCode() == "ruRU")
    local name, spellID, icon, _, _, _, _, _, _, _, isCollected = self:GetMountInfoByID(mountID)
    local totalSteps = #chain.steps
    local stepStates = {}

    local isAltTint = (chain.mountID and mountID ~= chain.mountID) or false
    local altStep = isAltTint and ((chain.altMountSteps and chain.altMountSteps[mountID]) or chain.altVendorStep) or nil
    local baseChainDone = false
    if isAltTint and altStep then
        local _, _, _, _, _, _, _, _, _, _, primaryCol = self:GetMountInfoByID(chain.mountID)
        if primaryCol then
            baseChainDone = true
        else
            local lastS = chain.steps[totalSteps]
            if lastS and lastS.doneQuest and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
                if C_QuestLog.IsQuestFlaggedCompleted(lastS.doneQuest)
                    or (C_QuestLog.IsQuestFlaggedCompletedOnAccount and C_QuestLog.IsQuestFlaggedCompletedOnAccount(lastS.doneQuest)) then
                    baseChainDone = true
                end
            end
        end
    end

    for idx, rawS in ipairs(chain.steps) do
        local s = (idx == totalSteps and altStep and (baseChainDone or isCollected)) and altStep or rawS
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
        elseif baseChainDone and altStep then
            if idx < totalSteps then
                isDone = true
                doneSub = totalSub
            else
                isDone = false
            end
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
            if idx == totalSteps and altStep and baseChainDone then
                local altLine = (isRU and altStep.luaDetailRU) or altStep.luaDetailEN
                if altLine and altLine ~= "" then
                    table.insert(detailParts, altLine)
                end
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


function addon:GetMountSpecialConditions(mountID)
    if not mountID then return nil end
    local isRU = (self:GetActiveLocaleCode() == "ruRU")
    local lines = {}
    local lockedToday = self:IsMountRareLockedToday(mountID)

    -- 0. Проверка 3-дневного КД Уникального инкубационного яйца (например, «Древнее яйцо» #94295 на Острове Великанов)
    local hasEgg, eggState, eggItemID, eggName, eggCfg = self:HasUniqueIncubationEggOnChar(mountID)
    if eggCfg then
        if hasEgg and eggState == "INCUBATING" then
            if isRU then
                table.insert(lines, string.format(
                    "|cffff5555Статус КД яйца (Lua): ЗАБЛОКИРОВАНО (%d дн.) — в сумке/банке уже лежит Уникальное «%s» (#%d)!|r\n|cffffaa00Пока это яйцо не вылупится, второе яйцо этому персонажу упасть НЕ МОЖЕТ (счётчик киллов динозавров на паузе).|r",
                    eggCfg.days or 3, tostring(eggName), eggItemID
                ))
            else
                table.insert(lines, string.format(
                    "|cffff5555Egg Lockout Status (Lua): LOCKED (%d days) — Unique '%s' (#%d) is already in your bags/bank!|r\n|cffffaa00Another egg CANNOT drop on this character until it hatches (dinosaur kill counter paused).|r",
                    eggCfg.days or 3, tostring(eggName), eggItemID
                ))
            end
        elseif hasEgg and eggState == "CRACKED" then
            if isRU then
                table.insert(lines, string.format(
                    "|cff00ff96Статус яйца (Lua): «%s» (#%d) СОЗРЕЛО В СУМКЕ! Откройте его прямо сейчас (пока оно в сумке, новое яйцо не упадёт)!|r",
                    tostring(eggName), eggItemID
                ))
            else
                table.insert(lines, string.format(
                    "|cff00ff96Egg Status (Lua): '%s' (#%d) has HATCHED in your bags! Open it now (another egg cannot drop while you hold it)!|r",
                    tostring(eggName), eggItemID
                ))
            end
        else
            if isRU then
                table.insert(lines, string.format(
                    "|cff00ff96Статус яйца (Lua): СВОБОДНО — Уникального «%s» (#%d) в сумке/банке нет, можно выбивать!|r",
                    tostring(eggName), eggItemID
                ))
            else
                table.insert(lines, string.format(
                    "|cff00ff96Egg Status (Lua): AVAILABLE — No Unique '%s' (#%d) in bags/bank, ready to farm!|r",
                    tostring(eggName), eggItemID
                ))
            end
        end
    end

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
                    local nName = self:GetNpcDisplayName(nid, rsData.name)
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
    local pMapName = (pMapID and self:GetMapName(pMapID)) or GetRealZoneText() or "?"
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

    add("=== MountCollector Lua Quest & Source Debugger (v1.7.0) ===")
    add(string.format("Character: %s | Class: %s (%s) | Level: %d | Faction: %s", charKey, tostring(classLoc), tostring(classToken), level, tostring(factionLoc or factionToken)))
    add(string.format("Player Map: %s (mapID = %s) [%.1f, %.1f]", tostring(pMapName), tostring(pMapID), px, py))
    add("------------------------------------------------------------")

    if not mountID then
        add("No mount selected.")
        return table.concat(out, "\n")
    end

    local name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction, shouldHideOnChar, isCollected = self:GetMountInfoByID(mountID)
    local _, description, sourceText = self:GetMountInfoExtraByID(mountID)
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
                local mName = (c.m and self:GetMapName(c.m)) or ("Map " .. tostring(c.m))
                local npcLock, qid = false, nil
                if c.npcID then
                    npcLock, qid = self:IsNpcLockedToday(c.npcID)
                end
                local lockTag = c.npcID and (npcLock and string.format(" [KILLED TODAY q#%s]", tostring(qid or "?")) or string.format(" [AVAILABLE q#%s]", tostring(qid or "?"))) or ""
                local dispNpc = self:GetNpcDisplayName(c.npcID, c.n) or ""
                add(string.format("  %d. %s (mapID=%s) [%.1f, %.1f] — %s (npcID=%s)%s", i, mName, tostring(c.m), c.x or 0, c.y or 0, tostring(dispNpc), tostring(c.npcID or "?"), lockTag))
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
        elseif info.method == "COLLECTION" and type(info.sourceItems) == "table" and #info.sourceItems == 1 then
            -- Для маунтов за сбор валюты/предметов (например, 9 999 Исполинских костей динозавра #94288 для Ящера цвета кости #537)
            -- синхронизируем счётчик прогресса с реальным количеством собранных предметов в сумках/банке/банке отряда
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
    -- Для маунтов за сбор предметов (например, 9 999 костей динозавра) прогресс равен числу предметов, а не киллов
    if info and info.method == "COLLECTION" and type(info.sourceItems) == "table" and #info.sourceItems == 1 then
        self:GetMountAttempts(mountID)
        if self.UpdateLDBText then self:UpdateLDBText() end
        if self.RefreshRadarUI then self:RefreshRadarUI() end
        return
    end

    -- Если у персонажа уже лежит Уникальное инкубационное яйцо (например, «Древнее яйцо» #94295), новое яйцо упасть не может!
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
    if self:HasUniqueIncubationEggOnChar(mountID) then
        return true, 1, 1
    end
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
                self:SyncActiveTourAfterKillOrAlert()
            end
        else
            self.RecentlySpottedUnlockedRares[npcID] = nil
        end
    end
end

-- Проверить, находится ли игрок внутри инстанса (подземелье, рейд, сценарий, БГ, арена).


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
                    local dStatus = self:GetDungeonMountStatus(mountID)
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
    cData.savedQuests = cData.savedQuests or {}

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
        for _, lfgID in ipairs({ 285, 287, 288 }) do
            local ok, doneToday = pcall(GetLFGDungeonRewards, lfgID)
            if ok and doneToday then
                cData.savedLfg[lfgID] = now + dailyResetSec
            end
        end
    end

    -- 3. Мировые боссы и праздничные квесты из MountDungeonsDB (Ша Злости, Галеон, Налак, Ундаста, Рухмар, Краулок, Беледар, Судьболом)
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

local function FormatClassColoredChar(name, classFile, level)
    local shortName = tostring(name or "Character"):gsub("%s*%-.+$", "")
    if addon.LocalizeCharName then
        shortName = addon:LocalizeCharName(shortName)
    end
    local colorPrefix = "|cffffffff"
    if classFile and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile] and _G.RAID_CLASS_COLORS[classFile].colorStr then
        colorPrefix = "|c" .. _G.RAID_CLASS_COLORS[classFile].colorStr
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
    if type(dEntry.questIDs) == "table" and cData.savedQuests then
        for _, qid in ipairs(dEntry.questIDs) do
            if cData.savedQuests[qid] and cData.savedQuests[qid] > now then
                return true
            end
        end
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
    local name, spellID, icon, _, _, _, _, _, _, _, isCollected = self:GetMountInfoByID(mountID)
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

    if dEntry.spellID == 448941 then
        local srvTime = (GetServerTime and GetServerTime()) or time()
        local cycleOffset = (srvTime - 3600) % 10800
        local timerLine
        if cycleOffset < 1800 then
            local remMin = math.max(1, math.ceil((1800 - cycleOffset) / 60))
            timerLine = isRU
                and string.format("\n|cff33ff88★ ТЁМНАЯ ФАЗА БЕЛЕДАРА АКТИВНА СЕЙЧАС! (осталось ~%d мин.)|r", remMin)
                or string.format("\n|cff33ff88★ BELEDAR VOID PHASE IS ACTIVE RIGHT NOW! (~%d min remaining)|r", remMin)
        else
            local waitSec = 10800 - cycleOffset
            local wHours = math.floor(waitSec / 3600)
            local wMins = math.ceil((waitSec % 3600) / 60)
            if wHours > 0 then
                timerLine = isRU
                    and string.format("\n|cff00ccff⏱ До следующей Тёмной фазы Беледара (спавна босса): %d ч. %d мин.|r", wHours, wMins)
                    or string.format("\n|cff00ccff⏱ Next Beledar Void Shift (boss spawn) in: %dh %dm|r", wHours, wMins)
            else
                timerLine = isRU
                    and string.format("\n|cffffd100⏱ До следующей Тёмной фазы Беледара (спавна босса): %d мин.!|r", wMins)
                    or string.format("\n|cffffd100⏱ Next Beledar Void Shift (boss spawn) in: %d min!|r", wMins)
            end
        end
        howToGet = howToGet .. timerLine
    end

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


function addon:CheckActiveQuestChainProgress()
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
