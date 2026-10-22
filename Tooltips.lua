local _, addon = ...

local L = addon.L
local SafeNotSecret = addon.SafeNotSecret

local lastTooltipFrame = nil
local lastTooltipMountID = nil
local lastTooltipTime = 0

function addon:AppendMountCollectorLines(tooltip, mountID, includeSourceText)
    if not tooltip or not mountID then return end
    if not self.db or not self.db.settings or not self.db.settings.showInTooltips then return end
    if not C_MountJournal or not C_MountJournal.GetMountInfoByID then return end

    local now = GetTime()
    if lastTooltipFrame == tooltip and lastTooltipMountID == mountID and (now - lastTooltipTime) < 0.05 then
        return
    end
    lastTooltipFrame = tooltip
    lastTooltipMountID = mountID
    lastTooltipTime = now

    local name, spellID, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    if not name then return end

    local _, description, sourceText = C_MountJournal.GetMountInfoExtraByID(mountID)

    if includeSourceText then
        if isCollected then
            tooltip:AddLine(L.STATUS_COLLECTED)
        else
            tooltip:AddLine(L.STATUS_NOT_COLLECTED)
        end
        if sourceText and sourceText ~= "" then
            tooltip:AddLine(" ")
            tooltip:AddLine(sourceText, 1, 1, 1, true)
        end
        if description and description ~= "" then
            tooltip:AddLine(" ")
            tooltip:AddLine(description, 1, 0.82, 0, true)
        end
    end

    local cfg = self.db.settings
    if not cfg.showGlobalRarity and not cfg.showServerRarity and not cfg.showAttempts then
        tooltip:Show()
        return
    end

    local realm, realmPop, estOwners, seenCount, globalPct = self:GetServerRarityInfo(mountID)
    local pctText, tierText = self:FormatRarityTier(globalPct)
    local attempts, byChar, dropInfo = self:GetMountAttempts(mountID)

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff00ccff=== Mount|r|cffffaa00Collector|r |cff00ccff===|r")

    -- 1. Рарность по миру (Data for Azeroth / Armory)
    if cfg.showGlobalRarity then
        if globalPct then
            tooltip:AddDoubleLine(
                L.TT_GLOBAL_RARITY,
                string.format("%s (%s)", pctText, tierText)
            )
        else
            tooltip:AddDoubleLine(
                L.TT_GLOBAL_RARITY,
                L.NO_DATA
            )
        end
    end

    -- 2. Рарность по серверу (Свежеватель Душ и др.)
    if cfg.showServerRarity then
        if estOwners then
            local seenStr = seenCount > 0 and string.format(L.TT_SERVER_SEEN_INLINE, seenCount) or ""
            tooltip:AddDoubleLine(
                string.format(L.TT_SERVER_RARITY, realm),
                string.format(L.TT_SERVER_OWNERS, estOwners, realmPop, seenStr)
            )
        elseif seenCount > 0 then
            tooltip:AddDoubleLine(
                string.format(L.TT_SERVER_RARITY, realm),
                string.format(L.TT_SERVER_SEEN_ONLY, seenCount)
            )
        end
    end

    -- 3. Дроп-шанс и количество траев по всем персонажам аккаунта
    local hasRealChance = dropInfo and dropInfo.chance and dropInfo.chance > 0
    if cfg.showAttempts and (hasRealChance or attempts > 0) then
        local chance = hasRealChance and dropInfo.chance or nil
        if chance then
            local dropPct = 100.0 / chance
            tooltip:AddDoubleLine(
                L.TT_DROP_CHANCE,
                string.format(L.TT_DROP_CHANCE_VAL, chance, dropPct)
            )
        end

        if not isCollected or attempts > 0 then
            local luckStr = ""
            if chance and attempts > 0 then
                local luckPct = (1 - math.pow(1 - (1 / chance), attempts)) * 100
                luckStr = string.format(L.TT_LUCK_INLINE, luckPct)
            end

            tooltip:AddDoubleLine(
                L.TT_ACCOUNT_ATTEMPTS,
                string.format("|cffffd100%d|r%s", attempts, luckStr)
            )
        end

        if byChar then
            local charParts = {}
            for charKey, count in pairs(byChar) do
                if count and count > 0 then
                    local shortName = strsplit(" ", charKey)
                    table.insert(charParts, string.format("%s: |cffffffff%d|r", shortName or charKey, count))
                end
            end
            if #charParts > 0 then
                tooltip:AddDoubleLine(
                    L.TT_BY_CHARACTERS,
                    "|cffcccccc" .. table.concat(charParts, ", ") .. "|r"
                )
            end
        end

        if not isCollected and self:IsMountRareLockedToday(mountID) then
            tooltip:AddDoubleLine(
                L.TT_STATUS_TODAY,
                L.TT_LOCKED_TODAY
            )
        end
    end

    tooltip:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    if Enum.TooltipDataType.Mount then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Mount, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            if not data or not SafeNotSecret(data.id) then return end
            addon:AppendMountCollectorLines(tooltip, data.id, false)
        end)
    end

    if Enum.TooltipDataType.Spell then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            if not data or not SafeNotSecret(data.id) then return end
            local mountID = addon.MountBySpell[data.id]
            if mountID then
                local inJournal = MountJournal and MountJournal:IsShown() and MouseIsOver(MountJournal)
                addon:AppendMountCollectorLines(tooltip, mountID, inJournal)
            end
        end)
    end

    if Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            if not data or not SafeNotSecret(data.id) then return end
            local mountID = addon.MountByItem[data.id]
            if not mountID and C_MountJournal and C_MountJournal.GetMountFromItem then
                mountID = C_MountJournal.GetMountFromItem(data.id)
            end
            if mountID then
                addon:AppendMountCollectorLines(tooltip, mountID, false)
            end
        end)
    end

    if Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            if not addon.db or not addon.db.settings or not addon.db.settings.showNpcTooltip then return end
            if tooltip ~= GameTooltip or not tooltip.GetUnit then return end
            local _, unit = tooltip:GetUnit()
            if not unit or not SafeNotSecret(unit) or UnitIsPlayer(unit) then return end

            local guid = UnitGUID(unit)
            local npcID = addon:GetNPCIDFromGUID(guid)
            if not npcID then return end

            local mounts = addon.MountsByNpc[npcID]
            if not mounts or #mounts == 0 then return end

            tooltip:AddLine(" ")
            tooltip:AddLine(L.TT_NPC_DROPS_HEADER)
            for _, mountID in ipairs(mounts) do
                local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                if name then
                    local attempts, _, dropInfo = addon:GetMountAttempts(mountID)
                    local globalPct = addon:GetGlobalRarity(mountID)
                    local pctStr = globalPct and string.format(L.TT_WORLD_PCT_SHORT, globalPct) or L.TT_RARE_SHORT
                    local chanceStr = (dropInfo and dropInfo.chance) and string.format("1/%d", dropInfo.chance) or ""
                    local statusStr = isCollected and L.TAG_COLLECTED or L.TAG_NOT_COLLECTED
                    local iconTag = icon and string.format("|T%s:14:14:0:0|t ", icon) or ""

                    tooltip:AddDoubleLine(
                        string.format("%s|cffa335ee%s|r %s", iconTag, name, statusStr),
                        string.format(L.TT_NPC_ATTEMPTS_FMT, attempts, chanceStr, pctStr)
                    )
                end
            end
            tooltip:Show()
        end)
    end
end

local journalHooked = false

local function SetupMountRowButtonHook(button)
    if not button or button._mcHooked then return end
    button._mcHooked = true

    button:HookScript("OnEnter", function(self)
        if not addon.db or not addon.db.settings or not addon.db.settings.showInJournalRowHover then return end
        local mountID = self.mountID
        if not mountID and self.GetElementData then
            local data = self:GetElementData()
            if type(data) == "table" then
                mountID = data.mountID
            end
        end
        if not mountID then return end

        local name, spellID, icon = C_MountJournal.GetMountInfoByID(mountID)
        if not name then return end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local iconTag = icon and string.format("|T%s:18:18:0:0|t ", icon) or ""
        GameTooltip:SetText(iconTag .. name, 1, 1, 1)
        lastTooltipTime = 0
        addon:AppendMountCollectorLines(GameTooltip, mountID, true)
        GameTooltip:Show()
    end)

    button:HookScript("OnLeave", function()
        if GameTooltip:IsOwned(button) then
            GameTooltip:Hide()
        end
    end)
end

function addon:HookMountJournal()
    if journalHooked or not _G.MountJournal then return end
    journalHooked = true

    if MountJournal.ScrollBox then
        hooksecurefunc(MountJournal.ScrollBox, "Update", function(scrollBox)
            if not scrollBox.ForEachFrame then return end
            scrollBox:ForEachFrame(function(button)
                SetupMountRowButtonHook(button)
            end)
        end)
        if MountJournal.ScrollBox.ForEachFrame then
            MountJournal.ScrollBox:ForEachFrame(function(button)
                SetupMountRowButtonHook(button)
            end)
        end
    end

    if _G.MountJournal_UpdateMountDisplay then
        hooksecurefunc("MountJournal_UpdateMountDisplay", function()
            local infoBtn = MountJournal.MountDisplay and MountJournal.MountDisplay.InfoButton
            if not infoBtn then return end

            if not infoBtn.MountCollectorSummary then
                local fs = infoBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetJustifyH("LEFT")
                fs:SetWidth(340)
                infoBtn.MountCollectorSummary = fs
            end

            local summaryFS = infoBtn.MountCollectorSummary
            if not addon.db or not addon.db.settings or not addon.db.settings.showInMountDisplay then
                summaryFS:SetText("")
                summaryFS:Hide()
                return
            end

            local mountID = MountJournal.selectedMountID
            if not mountID then
                summaryFS:SetText("")
                summaryFS:Hide()
                return
            end

            -- Привязываем наш блок аккуратно ПОД Lore (описание маунта), чтобы текст никогда не налезал на Lore!
            summaryFS:ClearAllPoints()
            if infoBtn.Lore and infoBtn.Lore:GetText() and infoBtn.Lore:GetText() ~= "" then
                summaryFS:SetPoint("TOPLEFT", infoBtn.Lore, "BOTTOMLEFT", 0, -8)
            elseif infoBtn.Source then
                summaryFS:SetPoint("TOPLEFT", infoBtn.Source, "BOTTOMLEFT", 0, -8)
            else
                summaryFS:SetPoint("TOPLEFT", infoBtn, "BOTTOMLEFT", 0, -8)
            end

            local realm, _, estOwners, seenCount, globalPct = addon:GetServerRarityInfo(mountID)
            local pctText, tierText = addon:FormatRarityTier(globalPct)
            local attempts, _, dropInfo = addon:GetMountAttempts(mountID)

            local extraLines = {}
            if globalPct and addon.db.settings.showGlobalRarity then
                local srvPart = ""
                if addon.db.settings.showServerRarity and estOwners then
                    srvPart = string.format(L.MD_SERVER_PART, realm, estOwners)
                    if seenCount > 0 then
                        srvPart = srvPart .. string.format(L.MD_SEEN_PART, seenCount)
                    end
                end
                table.insert(extraLines, string.format("%s %s (%s)%s", L.MD_RARITY_LABEL, pctText, tierText, srvPart))
            end

            if addon.db.settings.showAttempts and ((dropInfo and dropInfo.chance and not isCollected) or attempts > 0) then
                local chanceStr = (dropInfo and dropInfo.chance) and string.format(L.MD_CHANCE_PART, dropInfo.chance) or ""
                table.insert(extraLines, string.format(L.MD_ATTEMPTS_LABEL, attempts, chanceStr))
            end

            if #extraLines > 0 then
                summaryFS:SetText(table.concat(extraLines, "\n"))
                summaryFS:Show()
            else
                summaryFS:SetText("")
                summaryFS:Hide()
            end
        end)
    end
end
