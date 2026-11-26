local _, addon = ...

-- ============================================================================
-- MountCollector — Progression.lua
-- Единый движок прогресса структурированных источников маунтов:
--   1. Многошаговые квестовые цепочки, секреты и инкубация яиц (GetMountQuestChainStatus)
--   2. Особые условия дропа и Lua-диагностика (GetMountSpecialConditions, BuildMountDebugReport)
--   3. Матрица твинков по данжам, рейдам и мировым боссам (GetDungeonMountStatus)
--   4. Мета-достижения «Слава герою / рейдеру / знатоку вылазок» (GetGloryMountStatus)
--   5. Торговцы маунтами: живой баланс золота/валют/предметов, репутация и Известность отряда
--      (GetVendorMountStatus)
-- ============================================================================

local L = addon.L
local SafeNotSecret = addon.SafeNotSecret

function addon:IsRussianLocale()
    return self.GetActiveLocaleCode and (self:GetActiveLocaleCode() == "ruRU") or false
end

local function FormatSpacedNumber(val)
    local n = math.floor(tonumber(val) or 0)
    local s = tostring(math.abs(n))
    local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^%s+", "")
    if n < 0 then
        return "-" .. formatted
    end
    return formatted
end

-- ============================================================================
-- 1. КВЕСТОВЫЕ ЦЕПОЧКИ, СЕКРЕТЫ И LUA-ДИАГНОСТИКА
-- ============================================================================

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

function addon:GetMountSpecialConditions(mountID)
    if not mountID then return nil end
    local isRU = (self:GetActiveLocaleCode() == "ruRU")
    local lines = {}
    local lockedToday = self:IsMountRareLockedToday(mountID)

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

function addon:BuildMountDebugReport(mountID)
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

    add("=== MountCollector Lua Quest, Vendor & Source Debugger (v1.8.2) ===")
    add(string.format("Character: %s | Class: %s (%s) | Level: %d | Faction: %s", charKey, tostring(classLoc), tostring(classToken), level, tostring(factionLoc or factionToken)))
    add(string.format("Player Map: %s (mapID = %s) [%.1f, %.1f]", tostring(pMapName), tostring(pMapID), px, py))
    add("------------------------------------------------------------")

    if not mountID then
        add("No mount selected.")
        return table.concat(out, "\n")
    end

    local name, spellID, _, _, _, sourceType, _, _, _, _, isCollected = self:GetMountInfoByID(mountID)
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

    local vStatus = self:GetVendorMountStatus(mountID)
    if vStatus then
        add(" ")
        add("=== VENDOR, WALLET & REPUTATION EVALUATION ===")
        add(string.format("Vendor: %s | Zone: %s (mapID = %s [%.1f, %.1f])", tostring(vStatus.vendorTitle), tostring(vStatus.zoneTitle), tostring(vStatus.mapID), vStatus.x or 0, vStatus.y or 0))
        add(string.format("CanAffordAll = %s | RepMet = %s | CanBuyNow = %s", tostring(vStatus.canAffordAll), tostring(vStatus.repMet), tostring(vStatus.canBuyNow)))
        add("Reputation: " .. tostring((vStatus.repPlainText or vStatus.repSummaryText or "None"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
        for _, wLine in ipairs(vStatus.walletLines or {}) do
            add("  " .. tostring(wLine:gsub("|T[^|]+|t%s*", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
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

-- ============================================================================
-- 2. ПОДЗЕМЕЛЬЯ, РЕЙДЫ, ПРАЗДНИЧНЫЕ БОССЫ И МИРОВЫЕ БОССЫ (МАТРИЦА ТВИНКОВ)
-- ============================================================================

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

-- ============================================================================
-- 3. МЕТА-ДОСТИЖЕНИЯ «СЛАВА ГЕРОЮ / РЕЙДЕРУ / ЗНАТОКУ ВЫЛАЗОК»
-- ============================================================================

function addon:GetGloryMountStatus(mountID)
    if not mountID or not self.MountGloryByMountID then return nil end
    local gEntry = self.MountGloryByMountID[mountID]
    if not gEntry then return nil end

    local name, spellID, icon, _, _, _, _, _, _, _, isCollected = self:GetMountInfoByID(mountID)
    local isRU = (self:GetActiveLocaleCode() == "ruRU")
    local achID = gEntry.achievementID or 0

    local liveAchName, achCompleted = nil, false
    if achID > 0 and GetAchievementInfo then
        local ok, _, aName, _, aDone = pcall(GetAchievementInfo, achID)
        if ok then
            liveAchName = aName
            achCompleted = (aDone == true)
        end
    end

    local achTitle = (isRU and gEntry.titleRU) or gEntry.titleEN or liveAchName or ("Achievement #" .. tostring(achID))
    local expansionTitle = (isRU and gEntry.expansionRU) or gEntry.expansionEN or "WoW"
    local instanceTitle = (isRU and gEntry.instanceRU) or gEntry.instanceEN or achTitle
    local zoneTitle = (isRU and gEntry.zoneRU) or gEntry.zoneEN or instanceTitle
    local soloNote = (isRU and gEntry.soloNoteRU) or gEntry.soloNoteEN or ""

    local critDoneByAsset = {}
    local critDoneByIdx = {}
    if achID > 0 and GetAchievementNumCriteria and GetAchievementCriteriaInfo then
        local okNum, numCrit = pcall(GetAchievementNumCriteria, achID)
        if okNum and type(numCrit) == "number" and numCrit > 0 then
            for i = 1, numCrit do
                local okC, _, _, cDone, _, _, _, _, assetID = pcall(GetAchievementCriteriaInfo, achID, i)
                if okC then
                    if cDone then
                        critDoneByIdx[i] = true
                        if type(assetID) == "number" and assetID > 0 then
                            critDoneByAsset[assetID] = true
                        end
                    end
                end
            end
        end
    end

    local subList = {}
    local completedCount = 0
    local rawSubs = gEntry.subAchievements or {}
    local totalCount = #rawSubs

    for idx, sub in ipairs(rawSubs) do
        local subID = sub.achID or 0
        local subLiveName, subLiveDesc, subDone = nil, nil, false
        if subID > 0 and GetAchievementInfo then
            local okS, _, sName, _, sComp, _, _, _, sDesc = pcall(GetAchievementInfo, subID)
            if okS then
                subLiveName = sName
                subLiveDesc = sDesc
                subDone = (sComp == true)
            end
        end

        local isSubDone = isCollected or achCompleted or subDone or critDoneByAsset[subID] or critDoneByIdx[idx] or false
        if isSubDone then
            completedCount = completedCount + 1
        end

        local sTitle = (isRU and sub.titleRU) or sub.titleEN or subLiveName or ("#" .. tostring(subID))
        local sDesc = (isRU and sub.descRU) or sub.descEN or subLiveDesc or ""

        table.insert(subList, {
            index = idx,
            achID = subID,
            title = sTitle,
            desc = sDesc,
            isDone = isSubDone,
        })
    end

    local progressPct = (totalCount > 0) and math.floor((completedCount / totalCount) * 100 + 0.5) or (isCollected and 100 or 0)

    return {
        mountID = mountID,
        name = name or ("Mount #" .. tostring(mountID)),
        spellID = spellID or gEntry.spellID,
        icon = icon,
        isCollected = isCollected,
        achievementID = achID,
        achTitle = achTitle,
        expansionTitle = expansionTitle,
        instanceTitle = instanceTitle,
        zoneTitle = zoneTitle,
        soloable = (gEntry.soloable == true),
        minPlayers = gEntry.minPlayers or 1,
        soloNote = soloNote,
        mapID = gEntry.mapID,
        x = gEntry.x,
        y = gEntry.y,
        completedCount = completedCount,
        totalCount = totalCount,
        progressPct = progressPct,
        hasStarted = (completedCount > 0),
        subAchievements = subList,
        entry = gEntry,
    }
end

function addon:GetInstanceGloryCrosslink(mapID, instanceEN)
    if not self.MountGloryDB or not mapID then return nil end
    for _, gEntry in ipairs(self.MountGloryDB) do
        if gEntry.mapID == mapID and gEntry.minPlayers and gEntry.minPlayers < 8 then
            local mID = gEntry.resolvedMountID or gEntry.mountID
            local st = mID and self:GetGloryMountStatus(mID)
            if st and not st.isCollected then
                if not instanceEN or not gEntry.instanceEN or string.find(gEntry.instanceEN, instanceEN, 1, true) or string.find(instanceEN, gEntry.instanceEN, 1, true) then
                    return st
                end
            end
        end
    end
    return nil
end

-- ============================================================================
-- 4. ТОРГОВЦЫ МАУНТАМИ: ЖИВОЙ КОШЕЛЁК, ВАЛЮТЫ, РЕПУТАЦИЯ И ИЗВЕСТНОСТЬ (RENOWN)
-- ============================================================================

local STANDING_NAMES_RU = {
    [1] = "Ненависть",
    [2] = "Враждебность",
    [3] = "Неприязнь",
    [4] = "Равнодушие",
    [5] = "Дружелюбие",
    [6] = "Уважение",
    [7] = "Почтение",
    [8] = "Превознесение",
}

local STANDING_NAMES_EN = {
    [1] = "Hated",
    [2] = "Hostile",
    [3] = "Unfriendly",
    [4] = "Neutral",
    [5] = "Friendly",
    [6] = "Honored",
    [7] = "Revered",
    [8] = "Exalted",
}

local function GetStandingLabel(standingID, isRU)
    if isRU then
        return STANDING_NAMES_RU[standingID] or ("Уровень " .. tostring(standingID))
    end
    return STANDING_NAMES_EN[standingID] or ("Standing " .. tostring(standingID))
end

function addon:GetVendorMountStatus(mountID)
    if not mountID or not self.MountVendorsByMountID then return nil end
    local vEntry = self.MountVendorsByMountID[mountID]
    if not vEntry or not vEntry.primary then return nil end

    local name, spellID, icon, _, _, _, _, isFactionSpecific, faction, shouldHideOnChar, isCollected = self:GetMountInfoByID(mountID)
    if not name then return nil end

    local isRU = (self:GetActiveLocaleCode() == "ruRU")
    local playerFaction = UnitFactionGroup and UnitFactionGroup("player") or nil

    -- Проверяем противоположность фракции самого маунта (faction == 0 Орда, faction == 1 Альянс)
    local isOppositeFaction = (shouldHideOnChar == true)
    if isFactionSpecific and playerFaction then
        if (playerFaction == "Alliance" and faction == 0) or (playerFaction == "Horde" and faction == 1) then
            isOppositeFaction = true
        end
    end

    -- Выбираем подходящего торговца для фракции игрока (если в Mount.db2 два блока Альянс/Орда)
    local block = vEntry.primary
    local altBlock = vEntry.alt
    if altBlock and playerFaction then
        if playerFaction == "Horde" and (altBlock.side == "HORDE" or block.side == "ALLIANCE") then
            block = altBlock
            altBlock = vEntry.primary
        elseif playerFaction == "Alliance" and (altBlock.side == "ALLIANCE" or block.side == "HORDE") then
            block = altBlock
            altBlock = vEntry.primary
        end
    end

    local vendorTitle = (isRU and block.vendorRU and block.vendorRU ~= "" and block.vendorRU) or block.vendorEN or "Vendor"
    local zoneTitle = (isRU and block.zoneRU and block.zoneRU ~= "" and block.zoneRU) or block.zoneEN or ((block.mapID and block.mapID > 0 and self:GetMapName(block.mapID)) or "")

    -- 1. Оценка живого баланса золота, валют и предметов
    local costs = vEntry.costs or {}
    local hasKnownCost = (#costs > 0)
    local canAffordAll = hasKnownCost
    local shortCostParts = {}
    local walletLines = {}

    local playerGold = math.floor(((GetMoney and GetMoney()) or 0) / 10000)

    for _, c in ipairs(costs) do
        if c.kind == "GOLD" then
            local reqGold = tonumber(c.amount) or 0
            local okGold = (playerGold >= reqGold)
            if not okGold then canAffordAll = false end
            local goldIcon = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"
            local clr = okGold and "|cff33ff88" or "|cffffd100"
            table.insert(shortCostParts, string.format("%s%s|r %s", clr, FormatSpacedNumber(reqGold), goldIcon))
            if okGold then
                table.insert(walletLines, string.format(
                    isRU and "• %s Золото: |cff33ff88%s / %s (Хватает!)|r" or "• %s Gold: |cff33ff88%s / %s (Enough!)|r",
                    goldIcon, FormatSpacedNumber(playerGold), FormatSpacedNumber(reqGold)
                ))
            else
                local diff = math.max(0, reqGold - playerGold)
                table.insert(walletLines, string.format(
                    isRU and "• %s Золото: |cffffaa00%s / %s|r |cff888888(не хватает: %s)|r" or "• %s Gold: |cffffaa00%s / %s|r |cff888888(missing: %s)|r",
                    goldIcon, FormatSpacedNumber(playerGold), FormatSpacedNumber(reqGold), FormatSpacedNumber(diff)
                ))
            end
        elseif c.kind == "CURRENCY" then
            local reqAmt = tonumber(c.amount) or 0
            local cInfo = (c.id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) and C_CurrencyInfo.GetCurrencyInfo(c.id) or nil
            local haveAmt = (cInfo and SafeNotSecret(cInfo.quantity) and tonumber(cInfo.quantity)) or 0
            local cName = (isRU and c.nameRU and c.nameRU ~= "" and c.nameRU)
                or (not isRU and c.nameEN and c.nameEN ~= "" and c.nameEN)
                or (cInfo and SafeNotSecret(cInfo.name) and cInfo.name)
                or c.nameEN
                or ("Currency #" .. tostring(c.id))
            local cIcon = (cInfo and SafeNotSecret(cInfo.iconFileID) and cInfo.iconFileID)
                and string.format("|T%s:13:13:0:0|t", tostring(cInfo.iconFileID))
                or ""
            local okCur = (haveAmt >= reqAmt)
            if not okCur then canAffordAll = false end
            local clr = okCur and "|cff33ff88" or "|cff00ccff"
            table.insert(shortCostParts, string.format("%s%s|r %s%s", clr, FormatSpacedNumber(reqAmt), cIcon ~= "" and (cIcon .. " ") or "", cName))
            if okCur then
                table.insert(walletLines, string.format(
                    isRU and "• %s%s: |cff33ff88%s / %s (Хватает!)|r" or "• %s%s: |cff33ff88%s / %s (Enough!)|r",
                    cIcon ~= "" and (cIcon .. " ") or "", cName, FormatSpacedNumber(haveAmt), FormatSpacedNumber(reqAmt)
                ))
            else
                local diff = math.max(0, reqAmt - haveAmt)
                table.insert(walletLines, string.format(
                    isRU and "• %s%s: |cffffaa00%s / %s|r |cff888888(ещё %s)|r" or "• %s%s: |cffffaa00%s / %s|r |cff888888(%s more)|r",
                    cIcon ~= "" and (cIcon .. " ") or "", cName, FormatSpacedNumber(haveAmt), FormatSpacedNumber(reqAmt), FormatSpacedNumber(diff)
                ))
            end
        elseif c.kind == "ITEM" then
            local reqAmt = tonumber(c.amount) or 1
            if c.id and C_Item and C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, c.id)
            end
            local haveAmt, rawItemName = self:GetRequirementItemCount(c.id, false)
            local iName = (isRU and c.nameRU and c.nameRU ~= "" and c.nameRU)
                or (not isRU and c.nameEN and c.nameEN ~= "" and c.nameEN)
                or ((rawItemName and not string.find(rawItemName, "^Item #")) and rawItemName)
                or c.nameEN
                or rawItemName
                or ("Item #" .. tostring(c.id))
            local rawIcon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(c.id)
            local iIcon = rawIcon and string.format("|T%s:13:13:0:0|t", tostring(rawIcon)) or ""
            local okItem = (haveAmt >= reqAmt)
            if not okItem then canAffordAll = false end
            local clr = okItem and "|cff33ff88" or "|cffa335ee"
            table.insert(shortCostParts, string.format("%s%s|r %s%s", clr, FormatSpacedNumber(reqAmt), iIcon ~= "" and (iIcon .. " ") or "", iName))
            if okItem then
                table.insert(walletLines, string.format(
                    isRU and "• %s%s: |cff33ff88%s / %s шт. (В наличии!)|r" or "• %s%s: |cff33ff88%s / %s owned (Enough!)|r",
                    iIcon ~= "" and (iIcon .. " ") or "", iName, FormatSpacedNumber(haveAmt), FormatSpacedNumber(reqAmt)
                ))
            else
                local diff = math.max(0, reqAmt - haveAmt)
                table.insert(walletLines, string.format(
                    isRU and "• %s%s: |cffffaa00%s / %s шт.|r |cff888888(ещё %s)|r" or "• %s%s: |cffffaa00%s / %s|r |cff888888(%s more)|r",
                    iIcon ~= "" and (iIcon .. " ") or "", iName, FormatSpacedNumber(haveAmt), FormatSpacedNumber(reqAmt), FormatSpacedNumber(diff)
                ))
            end
        end
    end

    local shortCostText = (#shortCostParts > 0) and table.concat(shortCostParts, " + ") or (isRU and "|cffaaaaaaСмотрите ассортимент торговца|r" or "|cffaaaaaaSee vendor inventory|r")
    if #walletLines == 0 then
        table.insert(walletLines, isRU
            and "• Стоимость зависит от сезона / жетона обмена у самого торговца."
            or "• Purchase token or seasonal cost is listed directly on the vendor.")
    end

    -- 2. Оценка репутации, дружбы и Известности отряда (Warband Major Faction Renown)
    local facID = block.factionID or 0
    local reqStanding = block.reqStanding or 0
    local reqRenown = block.reqRenown or 0
    local reqNote = (isRU and block.reqNoteRU and block.reqNoteRU ~= "" and block.reqNoteRU) or block.reqNoteEN or ""
    local facName = (isRU and block.factionRU and block.factionRU ~= "" and block.factionRU) or block.factionEN or ""

    local hasRepReq = (reqStanding > 0) or (reqRenown > 0) or (reqNote ~= "") or (facID > 0)
    local repMet = true
    local repUncertain = false
    local repSummaryText = L.VENDOR_FREE_REP
    local repDetailLines = {}

    if hasRepReq then
        local mfData = (facID > 0 and C_MajorFactions and C_MajorFactions.GetMajorFactionData) and C_MajorFactions.GetMajorFactionData(facID) or nil
        local frInfo = (facID > 0 and C_GossipInfo and C_GossipInfo.GetFriendshipReputation) and C_GossipInfo.GetFriendshipReputation(facID) or nil
        local repData = (facID > 0 and C_Reputation and C_Reputation.GetFactionDataByID) and C_Reputation.GetFactionDataByID(facID) or nil

        if facName == "" then
            if mfData and SafeNotSecret(mfData.name) and mfData.name then
                facName = mfData.name
            elseif repData and SafeNotSecret(repData.name) and repData.name then
                facName = repData.name
            end
        end

        if mfData and SafeNotSecret(mfData.renownLevel) and (reqRenown > 0 or (tonumber(mfData.renownLevel) or 0) > 0) then
            local curRenown = tonumber(mfData.renownLevel) or 0
            if reqRenown > 0 then
                repMet = (curRenown >= reqRenown)
                local clr = repMet and "|cff33ff88" or "|cffffaa00"
                repSummaryText = string.format(
                    isRU and "|cffffffff%s|r — %sИзвестность %d / %d|r" or "|cffffffff%s|r — %sRenown %d / %d|r",
                    facName, clr, curRenown, reqRenown
                )
                table.insert(repDetailLines, repSummaryText)
            else
                repSummaryText = string.format(
                    isRU and "|cffffffff%s|r — |cff00ccffИзвестность %d|r" or "|cffffffff%s|r — |cff00ccffRenown %d|r",
                    facName, curRenown
                )
                table.insert(repDetailLines, repSummaryText)
            end
        elseif frInfo and frInfo.friendshipFactionID and frInfo.friendshipFactionID > 0 then
            local curRank = (SafeNotSecret(frInfo.reaction) and frInfo.reaction) or ""
            local isMaxFriend = (frInfo.nextThreshold == nil)
            if reqStanding >= 8 or (reqNote ~= "" and (string.find(string.lower(block.reqNoteEN or ""), "best") or string.find(string.lower(block.reqNoteEN or ""), "tier 6") or string.find(string.lower(block.reqNoteEN or ""), "max") or string.find(string.lower(block.reqNoteEN or ""), "true friend"))) then
                repMet = isMaxFriend
            elseif reqNote ~= "" then
                repMet = isMaxFriend
                if not isMaxFriend then repUncertain = true end
            end
            local clr = repMet and "|cff33ff88" or "|cffffaa00"
            local reqDisp = (reqNote ~= "" and reqNote) or (reqStanding > 0 and GetStandingLabel(reqStanding, isRU)) or facName
            repSummaryText = string.format("%s%s|r |cffcccccc(%s: %s)|r", clr, reqDisp, isRU and "сейчас" or "current", curRank ~= "" and curRank or "?")
            table.insert(repDetailLines, repSummaryText)
        elseif repData and SafeNotSecret(repData.reaction) then
            local curReaction = tonumber(repData.reaction) or 0
            local curLabel = GetStandingLabel(curReaction, isRU)
            local curVal = (tonumber(repData.currentStanding) or 0) - (tonumber(repData.currentReactionThreshold) or 0)
            local maxVal = (tonumber(repData.nextReactionThreshold) or 0) - (tonumber(repData.currentReactionThreshold) or 0)
            local progPart = (curReaction < 8 and maxVal > 0) and string.format(" (%s/%s)", FormatSpacedNumber(math.max(0, curVal)), FormatSpacedNumber(maxVal)) or ""
            if reqStanding > 0 then
                repMet = (curReaction >= reqStanding)
                local reqLabel = GetStandingLabel(reqStanding, isRU)
                local clr = repMet and "|cff33ff88" or "|cffffaa00"
                if repMet then
                    repSummaryText = string.format("|cffffffff%s|r — %s%s|r", facName, clr, curLabel)
                else
                    repSummaryText = string.format(
                        isRU and "|cffffffff%s|r — требуется %s%s|r |cffcccccc(сейчас: %s%s)|r"
                            or "|cffffffff%s|r — requires %s%s|r |cffcccccc(now: %s%s)|r",
                        facName, clr, reqLabel, curLabel, progPart
                    )
                end
                table.insert(repDetailLines, repSummaryText)
            else
                if reqNote ~= "" then
                    repUncertain = true
                    repMet = false
                    repSummaryText = "|cffffd100" .. reqNote .. "|r"
                else
                    repSummaryText = string.format("|cffffffff%s|r — |cff00ccff%s%s|r", facName, curLabel, progPart)
                end
                table.insert(repDetailLines, repSummaryText)
            end
        else
            -- Фракция ещё не открыта у персонажа или нестандартная заметка
            if reqRenown > 0 then
                repMet = false
                repSummaryText = string.format(
                    isRU and "|cffffffff%s|r — |cffffaa00Известность 0 / %d|r" or "|cffffffff%s|r — |cffffaa00Renown 0 / %d|r",
                    facName ~= "" and facName or "Faction", reqRenown
                )
            elseif reqStanding > 0 then
                repMet = false
                repSummaryText = string.format(
                    isRU and "|cffffffff%s|r — |cffffaa00требуется %s|r" or "|cffffffff%s|r — |cffffaa00requires %s|r",
                    facName ~= "" and facName or "Faction", GetStandingLabel(reqStanding, isRU)
                )
            elseif reqNote ~= "" then
                repMet = false
                repUncertain = true
                repSummaryText = "|cffffaa00" .. reqNote .. "|r"
            elseif facName ~= "" then
                repSummaryText = "|cffffffff" .. facName .. "|r"
            end
            table.insert(repDetailLines, repSummaryText)
        end
    end

    local canBuyNow = (not isCollected) and hasKnownCost and canAffordAll and repMet and (not repUncertain)

    return {
        mountID = mountID,
        name = name,
        spellID = spellID or vEntry.spellID,
        icon = icon,
        isCollected = (isCollected == true),
        isOppositeFaction = isOppositeFaction,
        vendorTitle = vendorTitle,
        zoneTitle = zoneTitle,
        mapID = block.mapID,
        x = block.x,
        y = block.y,
        altBlock = altBlock,
        hasKnownCost = hasKnownCost,
        canAffordAll = canAffordAll,
        shortCostText = shortCostText,
        walletLines = walletLines,
        hasRepReq = hasRepReq,
        repMet = repMet,
        repUncertain = repUncertain,
        repSummaryText = repSummaryText,
        repDetailLines = repDetailLines,
        canBuyNow = canBuyNow,
        entry = vEntry,
    }
end
