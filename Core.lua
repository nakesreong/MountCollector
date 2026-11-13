local addonName, addon = ...
_G.MountCollector = addon

-- ============================================================================
-- MountCollector — Core.lua
-- Ядро аддона (подготовлено к модульному разделению в v1.7+):
--   [Module A: Index & Rarity] Индексация маунтов, боссов, рарников, предметов
--      и квестовых цепочек (MountDropsDB + RareScanner + Rarity + MountQuestsDB + MountsRarity-2.0),
--      оценка глобальной рарности (Data for Azeroth) и серверной популяции.
--   [Module B: Navigation & Spawn Tour] Трекинг прогресса многошаговых квестовых цепочек,
--      3D-навигация Blizzard UserWaypoint/SuperTrack + TomTom, авто-облёт спавнов с выходом по действию игрока.
--   [Module C: Attempts & Lockouts] Учёт попыток (траев) по аккаунту и персонажам,
--      суточные/недельные КД рарников, данжей, рейдов и мировых боссов.
--   [Module D: Open-World Rare Radar] Детектор живых рарников и ворлдбоссов в открытом мире
--      (с жесткой блокировкой спама внутри подземелий и рейдов!).
--   [Module E: Midnight 12.x Guard] Защита от Secret Aura / Secret Value Taint и диагностика.
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
    db.minimap = db.minimap or { hide = false, minimapPos = 195, showInCompartment = true }
    if db.minimap.minimapPos == nil then
        db.minimap.minimapPos = 195
    end
    if db.minimap.showInCompartment == nil then
        db.minimap.showInCompartment = true
    end
    db.settings = db.settings or {}

    for k, v in pairs(db.knownNpcNames) do
        if not IsValidNpcName(v) then
            db.knownNpcNames[k] = nil
        end
    end
    for _, rData in pairs(db.realmCensus) do
        if type(rData) == "table" then
            for _, mEntry in pairs(rData) do
                if type(mEntry) == "table" and type(mEntry.players) == "table" then
                    for pName in pairs(mEntry.players) do
                        if not IsValidNpcName(pName) then
                            mEntry.players[pName] = nil
                            mEntry.count = math.max(0, (mEntry.count or 1) - 1)
                        end
                    end
                end
            end
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
        showAlertBanner = true,
        autoTargetOnApproach = true,
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

local RuRealmToEnglish = {
    ["Пиратская Бухта"] = "Booty Bay",
    ["Свежеватель Душ"] = "Soulflayer",
    ["Ревущий фьорд"] = "Howling Fjord",
    ["Гордунни"] = "Gordunni",
    ["Дракономор"] = "Fordragon",
    ["Ясеневый лес"] = "Ashenvale",
    ["Страж Смерти"] = "Deathguard",
    ["Черный Шрам"] = "Blackscar",
    ["Борейская тундра"] = "Borean Tundra",
    ["Вечная Песня"] = "Eversong",
    ["Галакронд"] = "Galakrond",
    ["Голдринн"] = "Goldrinn",
    ["Ткач Смерти"] = "Deathweaver",
    ["Король-лич"] = "Lich King",
    ["Подземье"] = "Deepholm",
    ["Разувий"] = "Razuvious",
    ["Седогрив"] = "Greymane",
    ["Термоштепсель"] = "Thermaplugg",
    ["Гром"] = "Grom",
    ["Азурегос"] = "Azuregos",
}

local CyrillicToLatin = {
    ["А"]="A", ["Б"]="B", ["В"]="V", ["Г"]="G", ["Д"]="D", ["Е"]="E", ["Ё"]="Yo", ["Ж"]="Zh",
    ["З"]="Z", ["И"]="I", ["Й"]="Y", ["К"]="K", ["Л"]="L", ["М"]="M", ["Н"]="N", ["О"]="O",
    ["П"]="P", ["Р"]="R", ["С"]="S", ["Т"]="T", ["У"]="U", ["Ф"]="F", ["Х"]="Kh", ["Ц"]="Ts",
    ["Ч"]="Ch", ["Ш"]="Sh", ["Щ"]="Shch", ["Ъ"]="", ["Ы"]="Y", ["Ь"]="", ["Э"]="E", ["Ю"]="Yu", ["Я"]="Ya",
    ["а"]="a", ["б"]="b", ["в"]="v", ["г"]="g", ["д"]="d", ["е"]="e", ["ё"]="yo", ["ж"]="zh",
    ["з"]="z", ["и"]="i", ["й"]="y", ["к"]="k", ["л"]="l", ["м"]="m", ["н"]="n", ["о"]="o",
    ["п"]="p", ["р"]="r", ["с"]="s", ["т"]="t", ["у"]="u", ["ф"]="f", ["х"]="kh", ["ц"]="ts",
    ["ч"]="ch", ["ш"]="sh", ["щ"]="shch", ["ъ"]="", ["ы"]="y", ["ь"]="", ["э"]="e", ["ю"]="yu", ["я"]="ya",
}

local KnownCharNameOverrides = {
    ["Ньярлатхотеп"] = "Nyarlathotep",
    ["Ньарлатхотеп"] = "Nyarlathotep",
    ["Гитпулл"] = "Gitpull",
    ["Морвара"] = "Morvara",
    ["Моржовый"] = "Morzhovy",
}

local EnglishItemNames = {
    [39878] = "Mysterious Egg",
    [39883] = "Cracked Egg",
    [94288] = "Giant Dinosaur Bone",
    [94295] = "Primal Egg",
    [94296] = "Cracked Primal Egg",
    [140495] = "Torn Invitation",
    [174858] = "Gersahl Greens",
    [174927] = "Zan-Tien Lasso",
    [180445] = "Wildseed Cradle",
    [180753] = "Twinklestar's Gardening Toolkit",
    [182651] = "Unusually Large Mushroom",
    [186599] = "Darkmaul Mushroom",
    [186603] = "Tasty Mawshroom",
    [187923] = "Aurelid Lure",
    [200879] = "Tattered Seeker's Notes",
    [201420] = "Highland Mustang",
    [201883] = "Ohn'ir Windsage's Totem",
    [202042] = "Aquatic Shades",
    [202096] = "Empty Fish Barrel",
    [224024] = "Crackling Shard",
    [224025] = "Storm Vessel",
    [225557] = "Vial of Tainteditha",
}

local RussianItemNames = {
    [39878] = "Таинственное яйцо",
    [39883] = "Треснувшее яйцо",
    [94288] = "Исполинская кость динозавра",
    [94295] = "Древнее яйцо",
    [94296] = "Треснувшее древнее яйцо",
}

function addon:GetItemDisplayName(itemID)
    if not itemID or itemID <= 0 then return nil end
    if self:GetActiveLocaleCode() == "enUS" and EnglishItemNames[itemID] then
        return EnglishItemNames[itemID]
    end
    local clientName = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if clientName and clientName ~= "" then
        return clientName
    end
    if self:GetActiveLocaleCode() == "ruRU" and RussianItemNames[itemID] then
        return RussianItemNames[itemID]
    end
    return EnglishItemNames[itemID] or ("Item #" .. tostring(itemID))
end

function addon:LocalizeRealmName(realm)
    if not realm or type(realm) ~= "string" then return "Realm" end
    if self:GetActiveLocaleCode() == "enUS" then
        return RuRealmToEnglish[realm] or self:LocalizeCharName(realm)
    end
    return realm
end

function addon:LocalizeCharName(name)
    if not name or type(name) ~= "string" then return "" end
    if self:GetActiveLocaleCode() ~= "enUS" then
        return name
    end
    if KnownCharNameOverrides[name] then
        return KnownCharNameOverrides[name]
    end
    local out = name
    for cyr, lat in pairs(CyrillicToLatin) do
        out = string.gsub(out, cyr, lat)
    end
    return out
end

function addon:GetMountInfoByID(mountID)
    if not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoByID then return nil end
    local name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction, shouldHideOnChar, isCollected, mID, isSteadyFlight = C_MountJournal.GetMountInfoByID(mountID)
    local en = self.EnglishMountDB and self.EnglishMountDB[mountID]
    if en then
        if (not spellID or not SafeNotSecret(spellID) or spellID == 0) and en.sp then
            spellID = en.sp
        end
        if name and self:GetActiveLocaleCode() == "enUS" and en.n then
            name = en.n
        end
    end
    return name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction, shouldHideOnChar, isCollected, mID, isSteadyFlight
end

function addon:GetMountInfoExtraByID(mountID)
    if not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoExtraByID then return nil end
    local creatureDisplayInfoID, description, sourceText, isSelfMount, mountTypeID, uiModelSceneID, animID, spellVisualKitID, disablePlayerMountPreview = C_MountJournal.GetMountInfoExtraByID(mountID)
    if self:GetActiveLocaleCode() == "enUS" and self.EnglishMountDB and self.EnglishMountDB[mountID] then
        local en = self.EnglishMountDB[mountID]
        if en.d and en.d ~= "" then description = en.d end
        if en.s and en.s ~= "" then sourceText = en.s end
    end
    return creatureDisplayInfoID, description, sourceText, isSelfMount, mountTypeID, uiModelSceneID, animID, spellVisualKitID, disablePlayerMountPreview
end

function addon:GetMapName(mapID)
    if not mapID then return "" end
    if self:GetActiveLocaleCode() == "enUS" and self.EnglishMapNames and self.EnglishMapNames[mapID] then
        return self.EnglishMapNames[mapID]
    end
    if C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then
            return info.name
        end
    end
    return "Map #" .. tostring(mapID)
end

function addon:GetNpcDisplayName(npcID, fallbackName)
    local isEN = (self:GetActiveLocaleCode() == "enUS")
    local rsName = (npcID and self.RareScannerNpcToMounts and self.RareScannerNpcToMounts[npcID] and self.RareScannerNpcToMounts[npcID].name) or nil
    local knName = (npcID and self.KnownNpcNames and self.KnownNpcNames[npcID]) or nil
    if isEN then
        if rsName and rsName ~= "" then return rsName end
        if fallbackName and fallbackName ~= "" then return fallbackName end
        return knName
    else
        if knName and knName ~= "" then return knName end
        if fallbackName and fallbackName ~= "" then return fallbackName end
        return rsName
    end
end

function addon:GetServerRarityInfo(mountID)
    local rawRealm = GetRealmName() or "Realm"
    local realmPop = self.RealmPopulations[rawRealm] or self.DefaultRealmPopulation
    local globalPct = self:GetGlobalRarity(mountID)

    local seenCount = 0
    if self.db and self.db.realmCensus and self.db.realmCensus[rawRealm] and self.db.realmCensus[rawRealm][mountID] then
        seenCount = self.db.realmCensus[rawRealm][mountID].count or 0
    end

    local estOwners = nil
    if type(globalPct) == "number" then
        estOwners = math.max(seenCount, math.floor((globalPct / 100.0) * realmPop + 0.5))
    end

    local displayRealm = self:LocalizeRealmName(rawRealm)
    return displayRealm, realmPop, estOwners, seenCount, globalPct
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
    self.NpcByRareName = self.NpcByRareName or {}
    wipe(self.NpcByRareName)

    local mountIDs = C_MountJournal.GetMountIDs()
    if not mountIDs then return end

    for _, mountID in ipairs(mountIDs) do
        local name, spellID = self:GetMountInfoByID(mountID)
        if spellID and SafeNotSecret(spellID) and spellID > 0 then
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
                local name, spellID = self:GetMountInfoByID(mountID)
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
                    if rsData.name and IsValidNpcName(rsData.name) then
                        self.NpcByRareName[string.lower(rsData.name)] = npcID
                    end

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
                        local name = self:GetMountInfoByID(mountID)
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
            local mID = (qChain.mountID and C_MountJournal.GetMountInfoByID(qChain.mountID) and qChain.mountID)
                or (qChain.spellID and self.MountBySpell[qChain.spellID])
                or (qChain.spellID and C_MountJournal.GetMountFromSpell and C_MountJournal.GetMountFromSpell(qChain.spellID))
                or (qChain.itemID and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(qChain.itemID))
                or (qChain.itemID and self.MountByItem[qChain.itemID])
                or qChain.mountID
            if mID and C_MountJournal.GetMountInfoByID(mID) then
                self.MountQuestsByMountID[mID] = qChain
                if type(qChain.altMountIDs) == "table" then
                    for _, altID in ipairs(qChain.altMountIDs) do
                        if altID and C_MountJournal.GetMountInfoByID(altID) then
                            self.MountQuestsByMountID[altID] = qChain
                        end
                    end
                    local _, _, _, _, _, _, _, _, _, _, primaryCol = C_MountJournal.GetMountInfoByID(mID)
                    if primaryCol then
                        for _, altID in ipairs(qChain.altMountIDs) do
                            local altName, _, _, _, _, _, _, _, _, _, altCol = C_MountJournal.GetMountInfoByID(altID)
                            if altName and not altCol then
                                mID = altID
                                break
                            end
                        end
                    end
                end
                qChain.resolvedMountID = mID
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
                    local name, spellID = self:GetMountInfoByID(mID)
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
                local isWB = (dEntry.sourceKind == "WORLD_BOSS" or dEntry.isWorldBoss == true)
                if dEntry.npcID and dEntry.npcID > 0 and isWB then
                    info.npcs[dEntry.npcID] = true
                    self.MountsByNpc[dEntry.npcID] = self.MountsByNpc[dEntry.npcID] or {}
                    AddUniqueToList(self.MountsByNpc[dEntry.npcID], mID)
                    if dEntry.bossRU and IsValidNpcName(dEntry.bossRU) then
                        self.NpcByRareName[string.lower(dEntry.bossRU)] = dEntry.npcID
                    end
                    if dEntry.bossEN and IsValidNpcName(dEntry.bossEN) then
                        self.NpcByRareName[string.lower(dEntry.bossEN)] = dEntry.npcID
                    end
                end
                if isWB and type(dEntry.questIDs) == "table" then
                    for _, qid in ipairs(dEntry.questIDs) do
                        AddUniqueToList(info.quests, qid)
                    end
                end
                if dEntry.mapID and dEntry.x and dEntry.y then
                    AddUniqueToList(info.maps, dEntry.mapID)
                    if isWB then
                        self.MountsByMap[dEntry.mapID] = self.MountsByMap[dEntry.mapID] or {}
                        AddUniqueToList(self.MountsByMap[dEntry.mapID], mID)
                    end
                    if #info.coords == 0 then
                        table.insert(info.coords, {
                            m = dEntry.mapID,
                            x = dEntry.x,
                            y = dEntry.y,
                            n = dEntry.bossRU or dEntry.bossEN or dEntry.instanceRU or dEntry.instanceEN or info.boss or info.name,
                            npcID = dEntry.npcID,
                        })
                    end
                end
            end
        end
    end

    if self.KnownNpcNames then
        for nid, kName in pairs(self.KnownNpcNames) do
            if IsValidNpcName(kName) then
                self.NpcByRareName[string.lower(kName)] = nid
            end
        end
    end
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
    if not IsValidNpcName(unitName) then return end
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



-- ============================================================================
-- ОБЩЕЕ СОСТОЯНИЕ UI И БАЗОВЫЕ ХЕЛПЕРЫ СТИЛЯ (ДОСТУПНЫ ВСЕМ МОДУЛЯМ)
-- ============================================================================
addon.UIState = addon.UIState or {
    currentTab = "ZONE",
    previousTab = "ZONE",
    selectedMountID = nil,
    searchText = "",
    rowPool = {},
    stepRowPool = {},
    dockStepPool = {},
    mapPinPool = {},
    worldMapHooked = false,
    dockHiddenByUser = false,
}

-- ============================================================================
-- БАЗОВЫЕ ХЕЛПЕРЫ СТИЛЯ (ТЁМНЫЙ ПЛОСКИЙ ELVUI / COLLECTIONS JOURNAL ДИЗАЙН)
-- ============================================================================
local function ApplyFlatBackdrop(frame, bgR, bgG, bgB, bgA, brR, brG, brB, brA)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(bgR or 0.06, bgG or 0.06, bgB or 0.07, bgA or 0.96)
    frame:SetBackdropBorderColor(brR or 0.20, brG or 0.20, brB or 0.22, brA or 1.0)
end

local function CreateFlatButton(parent, width, height, text, isGoldAccent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    if isGoldAccent then
        ApplyFlatBackdrop(btn, 0.16, 0.13, 0.05, 0.96, 0.85, 0.68, 0.15, 1.0)
        btn.defaultBg = { 0.16, 0.13, 0.05, 0.96 }
        btn.defaultBorder = { 0.85, 0.68, 0.15, 1.0 }
    else
        ApplyFlatBackdrop(btn, 0.10, 0.10, 0.12, 0.96, 0.24, 0.24, 0.28, 1.0)
        btn.defaultBg = { 0.10, 0.10, 0.12, 0.96 }
        btn.defaultBorder = { 0.24, 0.24, 0.28, 1.0 }
    end

    local padX = (width and width <= 28) and 1 or 6
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("LEFT", btn, "LEFT", padX, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -padX, 0)
    btn.label:SetJustifyH("CENTER")
    btn.label:SetWordWrap(false)
    btn.label:SetText(text or "")
    if isGoldAccent then
        btn.label:SetTextColor(1.0, 0.85, 0.2, 1.0)
    else
        btn.label:SetTextColor(0.92, 0.92, 0.95, 1.0)
    end

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.18, 0.10, 0.98)
        self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
        self.label:SetTextColor(1.0, 0.90, 0.35, 1.0)
    end)
    btn:SetScript("OnLeave", function(self)
        if self.isActiveTab then
            self:SetBackdropColor(0.18, 0.15, 0.06, 0.98)
            self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
            self.label:SetTextColor(1.0, 0.86, 0.20, 1.0)
        else
            self:SetBackdropColor(unpack(self.defaultBg))
            self:SetBackdropBorderColor(unpack(self.defaultBorder))
            if isGoldAccent then
                self.label:SetTextColor(1.0, 0.85, 0.2, 1.0)
            else
                self.label:SetTextColor(0.92, 0.92, 0.95, 1.0)
            end
        end
    end)

    function btn:SetText(str)
        self.label:SetText(str or "")
    end

    function btn:AutoSizeWidth(minW, maxW, padX)
        local textW = (self.label and self.label.GetStringWidth and self.label:GetStringWidth()) or 0
        local calcW = math.ceil(textW) + (padX or 18)
        if minW then calcW = math.max(minW, calcW) end
        if maxW then calcW = math.min(maxW, calcW) end
        self:SetWidth(calcW)
        return calcW
    end

    function btn:SetActiveTab(active)
        self.isActiveTab = active
        if active then
            self:SetBackdropColor(0.18, 0.15, 0.06, 0.98)
            self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
            self.label:SetTextColor(1.0, 0.86, 0.20, 1.0)
        else
            self:SetBackdropColor(unpack(self.defaultBg))
            self:SetBackdropBorderColor(unpack(self.defaultBorder))
            self.label:SetTextColor(0.88, 0.88, 0.92, 1.0)
        end
    end

    return btn
end

addon.ApplyFlatBackdrop = ApplyFlatBackdrop
addon.CreateFlatButton = CreateFlatButton


-- ============================================================================
-- ДИАГНОСТИКА ЦЕЛОСТНОСТИ МОДУЛЕЙ И БАЗ ДАННЫХ (MODULE INTEGRITY CHECK)
-- Выбрасывает наглядные предупреждения и ошибки при нарушении контрактов модулей
-- ============================================================================
function addon:ValidateModuleIntegrity(silentIfOk)
    local warnings = {}
    local requiredTables = {
        "L", "MountDropsBySpell", "RareScannerMountItems", "RareScannerNpcToMounts",
        "MountQuestsDB", "MountDungeonsDB", "MountBySpell", "DropInfoByMount",
    }
    for _, tblName in ipairs(requiredTables) do
        if type(self[tblName]) ~= "table" then
            table.insert(warnings, "Отсутствует таблица БД/индекса: addon." .. tblName)
        end
    end

    local requiredMethods = {
        -- Core.lua
        "InitDB", "BuildMountIndex", "GetGlobalRarity", "FormatRarityTier", "GetServerRarityInfo",
        -- Navigation.lua
        "GetMountWowheadURL", "NavigateMountQuestStep", "GetBestMountCoords", "SetMountWaypoint",
        "PinAllMountSpawns", "CheckAndCancelTourIfUserOverrode", "StartSpawnTourTicker",
        "AdvanceSpawnTourStep", "SyncActiveTourAfterKillOrAlert", "NavigateMountTarget",
        -- Lockouts.lua
        "GetMountQuestChainStatus", "GetMountSpecialConditions", "BuildMountDebugReport",
        "ScanAllCharacterStatistics", "GetMountAttempts", "SetManualMountAttempts", "RecordAttempt",
        "IsNpcLockedToday", "IsMountRareLockedToday", "GetZoneUncollectedMounts",
        "ScanCurrentCharacterLockouts", "GetDungeonMountStatus",
        -- RareRadar.lua
        "IsPlayerInInstancedContent", "IsOpenWorldRareOrWorldBossMount", "CheckUnitForMountDrop",
        "CheckVignetteForMountDrop", "ScanAllActiveVignettes", "CheckMonsterChatForMountDrop",
        "TriggerRareMountAlert", "ClearAutoTargetOverrideBinding", "EnableAutoTargetOverrideBinding",
        -- MapPins.lua
        "RefreshWorldMapPins", "InitWorldMapPins", "UpdateLDBText", "EnsureRoundMinimapButton", "InitLDB",
        -- Tooltips.lua & RadarUI.lua & Config.lua
        "AppendMountCollectorLines", "HookMountJournal", "RefreshRadarUI", "ToggleRadarWindow", "ToggleConfigFrame",
    }
    for _, fnName in ipairs(requiredMethods) do
        if type(self[fnName]) ~= "function" then
            table.insert(warnings, "Отсутствует функция модуля: addon:" .. fnName .. "()")
        end
    end

    -- Сверка mountID и spellID в MountDungeonsDB и MountQuestsDB с живой клиентской БД C_MountJournal
    if C_MountJournal and C_MountJournal.GetMountInfoByID then
        if type(self.MountDungeonsDB) == "table" then
            for idx, dEntry in ipairs(self.MountDungeonsDB) do
                if dEntry.mountID then
                    local mName, mSpell = self:GetMountInfoByID(dEntry.mountID)
                    if not mName then
                        table.insert(warnings, string.format("MountDungeonsDB[%d]: несуществующий mountID=%s (%s)", idx, tostring(dEntry.mountID), tostring(dEntry.bossEN or "?")))
                    elseif dEntry.spellID and mSpell and SafeNotSecret(mSpell) and mSpell > 0 and mSpell ~= dEntry.spellID then
                        table.insert(warnings, string.format("MountDungeonsDB[%d] (%s): spellID=%d не совпадает с клиентским spellID=%d", idx, mName, dEntry.spellID, mSpell))
                    end
                end
            end
        end
        if type(self.MountQuestsDB) == "table" then
            for idx, qChain in ipairs(self.MountQuestsDB) do
                if qChain.mountID then
                    local mName, mSpell = self:GetMountInfoByID(qChain.mountID)
                    if not mName then
                        table.insert(warnings, string.format("MountQuestsDB[%d]: несуществующий mountID=%s", idx, tostring(qChain.mountID)))
                    elseif qChain.spellID and mSpell and SafeNotSecret(mSpell) and mSpell > 0 and mSpell ~= qChain.spellID then
                        table.insert(warnings, string.format("MountQuestsDB[%d] (%s): spellID=%d не совпадает с клиентским spellID=%d", idx, mName, qChain.spellID, mSpell))
                    end
                end
            end
        end
    end

    if #warnings > 0 then
        for _, w in ipairs(warnings) do
            print("|cffff4444[MountCollector WARNING]|r " .. w)
        end
        if not silentIfOk and geterrorhandler then
            geterrorhandler()("MountCollector Module Integrity Warning: " .. table.concat(warnings, "; "))
        end
        return false, warnings
    end

    if not silentIfOk then
        local dropCount = 0
        for _ in pairs(self.DropInfoByMount or {}) do dropCount = dropCount + 1 end
        local dungeonCount = (self.MountDungeonsDB and #self.MountDungeonsDB) or 0
        local questCount = (self.MountQuestsDB and #self.MountQuestsDB) or 0
        print(string.format(
            "|cff00ccff[MountCollector]|r |cff33ff88Проверка модулей OK!|r Индекс: %d дроп/рар-маунтов, %d данжей/рейдов/ворлдбоссов, %d квестовых цепочек.",
            dropCount, dungeonCount, questCount
        ))
    end
    return true, warnings
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
eventFrame:RegisterEvent("UNIT_TARGET")
eventFrame:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
eventFrame:RegisterEvent("VIGNETTES_UPDATED")
eventFrame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
eventFrame:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
eventFrame:RegisterEvent("CHAT_MSG_MONSTER_SAY")
eventFrame:RegisterEvent("CHAT_MSG_MONSTER_WHISPER")
eventFrame:RegisterEvent("LOOT_READY")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")


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
            if addon.CheckPortalRouteProgress then
                addon:CheckPortalRouteProgress()
            end
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
            if addon.EnsureRoundMinimapButton then
                addon:EnsureRoundMinimapButton()
            end
            if addon.RefreshRadarUI then
                addon:RefreshRadarUI()
            end
            addon:ScanAllActiveVignettes()
            if addon.ValidateModuleIntegrity then addon:ValidateModuleIntegrity(true) end
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
        addon:ScanAllActiveVignettes()
        if addon.CheckPortalRouteProgress then
            addon:CheckPortalRouteProgress()
        end
        if addon.UpdateLDBText then
            addon:UpdateLDBText()
        end
        if addon.RefreshRadarUI then
            addon:RefreshRadarUI()
        end
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        if addon.CheckPortalRouteProgress then
            addon:CheckPortalRouteProgress()
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if _G.MountCollectorRadarFrame and _G.MountCollectorRadarFrame:IsShown() and addon.RefreshRadarUI then
            addon:RefreshRadarUI()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if addon.ClearAutoTargetOverrideBinding then
            addon:ClearAutoTargetOverrideBinding()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if addon.FlushPendingAlertTarget then
            addon:FlushPendingAlertTarget()
        end
        C_Timer.After(2.0, function()
            addon:CheckRecentlyKilledRares()
        end)
    elseif event == "PLAYER_TARGET_CHANGED" then
        if addon.ClearAutoTargetOverrideBinding and UnitExists("target") then
            local tGuid = UnitGUID("target")
            local tNpcID = addon:GetNPCIDFromGUID(tGuid)
            if tNpcID and addon.MountsByNpc and addon.MountsByNpc[tNpcID] then
                addon:ClearAutoTargetOverrideBinding()
            end
        end
        addon:CheckUnitForMountDrop("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        addon:CheckUnitForMountDrop("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        addon:CheckUnitForMountDrop(unit)
    elseif event == "UNIT_TARGET" then
        local unit = ...
        if unit and SafeNotSecret(unit) and unit ~= "player" then
            addon:CheckUnitForMountDrop(unit .. "target")
        end
    elseif event == "VIGNETTE_MINIMAP_UPDATED" then
        local vignetteGUID = ...
        addon:CheckVignetteForMountDrop(vignetteGUID, false)
    elseif event == "VIGNETTES_UPDATED" then
        addon:ScanAllActiveVignettes()
            if addon.ValidateModuleIntegrity then addon:ValidateModuleIntegrity(true) end
    elseif event == "CHAT_MSG_MONSTER_YELL" or event == "CHAT_MSG_MONSTER_EMOTE" or event == "CHAT_MSG_MONSTER_SAY" or event == "CHAT_MSG_MONSTER_WHISPER" then
        local _, senderName = ...
        addon:CheckMonsterChatForMountDrop(senderName)
    elseif event == "LOOT_READY" then
        if GetNumLootItems and GetLootSourceInfo then
            local seenGuids = {}
            addon.LootedCorpseGUIDs = addon.LootedCorpseGUIDs or {}
            local now = GetTime()
            local numItems = GetNumLootItems() or 0
            for slot = 1, numItems do
                local okSrc, srcInfo = pcall(function() return { GetLootSourceInfo(slot) } end)
                if okSrc and type(srcInfo) == "table" then
                    for i = 1, #srcInfo, 2 do
                        local srcGuid = srcInfo[i]
                        if srcGuid and SafeNotSecret(srcGuid) and not seenGuids[srcGuid] then
                            seenGuids[srcGuid] = true
                            local alreadyLootedCorpse = addon.LootedCorpseGUIDs[srcGuid] and ((now - addon.LootedCorpseGUIDs[srcGuid]) < 300)
                            if not alreadyLootedCorpse then
                                addon.LootedCorpseGUIDs[srcGuid] = now
                                local npcID = addon:GetNPCIDFromGUID(srcGuid)
                                if npcID and addon.MountsByNpc[npcID] then
                                    local rs = addon.RareScannerNpcToMounts and addon.RareScannerNpcToMounts[npcID]
                                    local srcName = (addon.KnownNpcNames and addon.KnownNpcNames[npcID])
                                        or (rs and rs.name and rs.name ~= "" and rs.name)
                                        or ("NPC #" .. tostring(npcID))
                                    local isLocked, lockQid = addon:IsNpcLockedToday(npcID)
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
                                            local hasEgg, _, _, eggName = addon:HasUniqueIncubationEggOnChar(mountID)
                                            if hasEgg then
                                                addon.SkipEggLockoutNoticeAt = addon.SkipEggLockoutNoticeAt or {}
                                                if not addon.SkipEggLockoutNoticeAt[mountID] or (now - addon.SkipEggLockoutNoticeAt[mountID]) > 90 then
                                                    addon.SkipEggLockoutNoticeAt[mountID] = now
                                                    if addon.db and addon.db.settings and addon.db.settings.announceAttempts then
                                                        local isRU = (addon:GetActiveLocaleCode() == "ruRU")
                                                        if isRU then
                                                            print(string.format("|cff00ccff[MountCollector]|r Килл (%s) не засчитан в траи ящеров из яйца: у вас уже есть Уникальное |cffffd100[%s]|r (новое яйцо не упадёт, пока это не вылупится!).", srcName, tostring(eggName)))
                                                        else
                                                            print(string.format("|cff00ccff[MountCollector]|r Kill (%s) not counted toward egg mounts: you already hold a Unique |cffffd100[%s]|r (another cannot drop until it hatches!).", srcName, tostring(eggName)))
                                                        end
                                                    end
                                                end
                                            else
                                                addon:RecordAttempt(mountID, srcName, not lockQid)
                                            end
                                        end
                                        if addon.RefreshWorldMapPins then
                                            addon:RefreshWorldMapPins()
                                        end
                                        addon:SyncActiveTourAfterKillOrAlert()
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
            addon:SyncActiveTourAfterKillOrAlert()
        end
        C_Timer.After(0.5, function() if addon.CheckActiveQuestChainProgress then addon:CheckActiveQuestChainProgress() end end)
    elseif event == "QUEST_ACCEPTED" then
        C_Timer.After(0.5, function() if addon.CheckActiveQuestChainProgress then addon:CheckActiveQuestChainProgress() end end)
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
