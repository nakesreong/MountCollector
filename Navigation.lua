local _, addon = ...

-- ============================================================================
-- MountCollector — Navigation.lua
-- Модуль 3D-навигации, маршрутов облёта точек спавна и ссылок Wowhead:
--   * Генерация локализованных ссылок на Wowhead (ru.wowhead.com / wowhead.com)
--   * Навигация по шагам квестовых цепочек (NavigateMountQuestStep)
--   * Выбор оптимальной живой точки спавна рарника (GetBestMountCoords)
--   * Установка 3D-ромбика Blizzard UserWaypoint + SuperTrack + TomTom (SetMountWaypoint)
--   * Построение кольцевого маршрута Nearest-Neighbor по живым спавнам (PinAllMountSpawns)
--   * Фоновый тикер авто-переключения точек на подлёте и авто-выход из режима тура,
--     если игрок вручную поставил свою булавку или начал отслеживать квест
--   * Универсальная точка входа навигации для UI-кнопок (NavigateMountTarget)
-- ============================================================================

local L = addon.L
local SafeNotSecret = addon.SafeNotSecret
local IsValidNpcName = addon.IsValidNpcName

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
    local _, spellID = self:GetMountInfoByID(mountID)
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

    -- 3. Если у маунта только 1 точка (босс данжа/рейда без многих спавнов), возвращаем её
    if #info.coords == 1 then
        return info.coords[1]
    end
    return nil
end

-- ============================================================================
-- МНОГОШАГОВЫЙ НАВИГАТОР ПО ПОРТАЛАМ И ВЫХОДАМ ИЗ ЗОН (Minimap Arrow + TomTom)
-- Ведёт стрелочкой на миникарте к выходу из текущей зоны -> через портал в столицу
-- -> через портал в целевой континент -> к маунту, рарнику или квестовому NPC!
-- ============================================================================
addon.activePortalRoute = nil
addon.portalTomTomUids = {}

local function GetMapAncestry(mapID)
    local chain = {}
    local visited = {}
    local cur = mapID
    while cur and cur > 0 and not visited[cur] do
        visited[cur] = true
        table.insert(chain, cur)
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(cur)
        cur = info and info.parentMapID or nil
    end
    return chain, visited
end

local function GetMapInstanceID(mapID)
    if not mapID or not C_Map or not C_Map.GetWorldPosFromMapPos or not _G.CreateVector2D then
        return nil
    end
    local ok, instID = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0.5, 0.5))
    if ok and instID then
        return instID
    end
    return nil
end

local function GetMapMacroRegion(mapID)
    if not mapID then return "UNKNOWN" end
    local _, ancestors = GetMapAncestry(mapID)

    -- Изолированные подзоны, требующие отдельного выхода:
    if mapID == 2413 or mapID == 2576 or ancestors[2413] then return "HARANDAR" end
    if mapID == 2405 or ancestors[2405] then return "VOIDSTORM" end
    if mapID == 2200 or ancestors[2200] then return "EMERALD_DREAM" end
    if mapID == 2133 or ancestors[2133] then return "ZARALEK" end

    -- Midnight (Кель'Талас 2537 / Луносвет 2393, 2605 / Леса Вечной Песни 2395, 2594 / Зул'Аман 2437)
    if mapID == 2393 or mapID == 2605 or mapID == 2395 or mapID == 2594 or mapID == 2437 or mapID == 2537
        or ancestors[2393] or ancestors[2395] or ancestors[2437] or ancestors[2537] or ancestors[2424]
    then
        return "MIDNIGHT_QUELTHALAS"
    end
    -- Каз Алгар (TWW)
    if mapID == 2339 or ancestors[2274] or ancestors[2248] or ancestors[2214] or ancestors[2215] or ancestors[2255] then
        return "KHAZ_ALGAR"
    end
    -- Драконьи острова (Dragonflight)
    if mapID == 2112 or ancestors[1978] or ancestors[2022] or ancestors[2023] or ancestors[2024] or ancestors[2025] or ancestors[2151] then
        return "DRAGON_ISLES"
    end
    -- Темные Земли (Shadowlands)
    if mapID == 1670 or ancestors[1550] or ancestors[1525] or ancestors[1533] or ancestors[1536] or ancestors[1565] or ancestors[1543] or ancestors[1961] or ancestors[1970] then
        return "SHADOWLANDS"
    end
    -- Зандалар и Кул-Тирас (BfA)
    if mapID == 1165 or ancestors[875] or ancestors[862] or ancestors[863] or ancestors[864] then
        return "ZANDALAR"
    end
    if mapID == 1161 or ancestors[876] or ancestors[895] or ancestors[896] or ancestors[942] then
        return "KUL_TIRAS"
    end
    -- Расколотые острова и Аргус (Legion)
    if mapID == 627 or ancestors[619] or ancestors[630] or ancestors[641] or ancestors[650] or ancestors[634] or ancestors[680] or ancestors[646] then
        return "BROKEN_ISLES"
    end
    if ancestors[905] or mapID == 830 or mapID == 882 or mapID == 885 then
        return "ARGUS"
    end
    -- Дренор (WoD)
    if ancestors[572] or mapID == 525 or mapID == 534 or mapID == 535 or mapID == 539 or mapID == 542 or mapID == 543 or mapID == 550 then
        return "DRAENOR"
    end
    -- Пандария (MoP — включая Остров Великанов 507, Остров Грома 504, Вневременный остров 554, Нефритовый лес 371 и др.)
    if ancestors[424] or mapID == 371 or mapID == 507 or mapID == 504 or mapID == 554 or mapID == 376 or mapID == 379 or mapID == 388 or mapID == 390 or mapID == 418 or mapID == 422 then
        return "PANDARIA"
    end
    -- Запределье (TBC)
    if ancestors[101] or mapID == 111 then
        return "OUTLAND"
    end
    -- Нордскол (WotLK)
    if ancestors[113] or mapID == 125 then
        return "NORTHREND"
    end
    -- Калимдор и Восточные королевства
    if ancestors[12] or mapID == 85 then
        return "KALIMDOR"
    end
    if ancestors[13] or mapID == 84 then
        return "EASTERN_KINGDOMS"
    end
    return "OTHER_" .. tostring(mapID)
end

local function FindDynamicExitOrPortalOnMap(mapID, preferredKeywords, isRU)
    if not mapID then return nil end
    if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap and C_AreaPoiInfo.GetAreaPOIInfo then
        local ok, poiIDs = pcall(C_AreaPoiInfo.GetAreaPOIForMap, mapID)
        if ok and type(poiIDs) == "table" then
            local bestMatch = nil
            for _, poiID in ipairs(poiIDs) do
                local okInfo, info = pcall(C_AreaPoiInfo.GetAreaPOIInfo, mapID, poiID)
                if okInfo and info and info.position then
                    local nameLow = string.lower((SafeNotSecret(info.name) and info.name) or "")
                    local descLow = string.lower((SafeNotSecret(info.description) and info.description) or "")
                    local atlasLow = string.lower((SafeNotSecret(info.atlasName) and info.atlasName) or "")
                    local combined = nameLow .. " " .. descLow .. " " .. atlasLow
                    local x, y = info.position:GetXY()
                    if x and y and x > 0 and y > 0 then
                        if preferredKeywords then
                            for _, kw in ipairs(preferredKeywords) do
                                if string.find(combined, kw, 1, true) then
                                    return x * 100, y * 100, (SafeNotSecret(info.name) and info.name) or (isRU and "Портал / Выход" or "Portal / Exit")
                                end
                            end
                        end
                        if string.find(combined, "portal", 1, true)
                            or string.find(combined, "портал", 1, true)
                            or string.find(combined, "teleporter", 1, true)
                            or string.find(combined, "телепорт", 1, true)
                            or string.find(combined, "waygate", 1, true)
                            or string.find(combined, "оргриммар", 1, true)
                            or string.find(combined, "штормград", 1, true)
                            or string.find(combined, "луносвет", 1, true)
                            or string.find(combined, "silvermoon", 1, true)
                        then
                            bestMatch = { x = x * 100, y = y * 100, note = (SafeNotSecret(info.name) and info.name) or (isRU and "Портал" or "Portal") }
                        end
                    end
                end
            end
            if bestMatch then
                return bestMatch.x, bestMatch.y, bestMatch.note
            end
        end
    end

    if C_Map and C_Map.GetMapLinksForMap then
        local ok, links = pcall(C_Map.GetMapLinksForMap, mapID)
        if ok and type(links) == "table" and #links > 0 then
            for _, link in ipairs(links) do
                if link.position then
                    local x, y = link.position:GetXY()
                    local linkName = (SafeNotSecret(link.name) and link.name) or (isRU and "Выход из зоны" or "Zone Exit")
                    if x and y and x > 0 and y > 0 then
                        return x * 100, y * 100, (isRU and "Выход: " or "Exit: ") .. linkName
                    end
                end
            end
        end
    end
    return nil
end

local function ResolvePinnableMapCoords(mapID, normX, normY)
    if not mapID or not C_Map or not C_Map.CanSetUserWaypointOnMap then
        return mapID, normX, normY
    end
    local ok, canSet = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
    if ok and canSet then
        return mapID, normX, normY
    end
    if not C_Map.GetMapInfo or not C_Map.GetWorldPosFromMapPos or not C_Map.GetMapPosFromWorldPos or not _G.CreateVector2D then
        return mapID, normX, normY
    end
    local curMap = mapID
    for _ = 1, 5 do
        local info = C_Map.GetMapInfo(curMap)
        if not info or not info.parentMapID or info.parentMapID == 0 or info.parentMapID == curMap then break end
        local parentID = info.parentMapID
        local okP, canParent = pcall(C_Map.CanSetUserWaypointOnMap, parentID)
        if okP and canParent then
            local okW, instID, worldPos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(normX, normY))
            if okW and instID and worldPos then
                local okM, _, parentPos = pcall(C_Map.GetMapPosFromWorldPos, instID, worldPos, parentID)
                if okM and parentPos then
                    local px, py = parentPos:GetXY()
                    if px and py and px > 0 and px < 1 and py > 0 and py < 1 then
                        return parentID, px, py
                    end
                end
            end
        end
        curMap = parentID
    end
    return mapID, normX, normY
end

function addon:BuildMultiHopRoute(targetMapID, targetX, targetY, targetName, targetZone, targetNote)
    local isRU = (self:GetActiveLocaleCode() == "ruRU")
    local steps = {}
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not playerMapID or playerMapID == targetMapID then
        table.insert(steps, {
            mapID = targetMapID,
            x = targetX,
            y = targetY,
            zone = targetZone,
            note = targetNote or targetName,
        })
        return steps
    end

    local playerRegion = GetMapMacroRegion(playerMapID)
    local targetRegion = GetMapMacroRegion(targetMapID)
    local playerInstID = GetMapInstanceID(playerMapID)
    local targetInstID = GetMapInstanceID(targetMapID)

    if (playerRegion == targetRegion or (playerInstID and targetInstID and playerInstID == targetInstID and playerRegion == targetRegion))
        and playerRegion ~= "HARANDAR" and targetRegion ~= "HARANDAR"
        and playerRegion ~= "VOIDSTORM" and targetRegion ~= "VOIDSTORM"
        and playerRegion ~= "EMERALD_DREAM" and targetRegion ~= "EMERALD_DREAM"
    then
        table.insert(steps, {
            mapID = targetMapID,
            x = targetX,
            y = targetY,
            zone = targetZone,
            note = targetNote or targetName,
        })
        return steps
    end

    local isAlliance = (UnitFactionGroup("player") == "Alliance")
    local capMapID   = isAlliance and 84 or 85
    local capName    = isRU
        and (isAlliance and "Зал порталов Штормграда" or "Зал порталов Оргриммара")
        or (isAlliance and "Stormwind Portal Room" or "Orgrimmar Portal Room")
    local capX       = isAlliance and 48.7 or 57.3
    local capY       = isAlliance and 88.1 or 89.7
    local capRegion  = isAlliance and "EASTERN_KINGDOMS" or "KALIMDOR"

    -- ЭТАП А: ВЫХОД ИЗ ТЕКУЩЕЙ ЗОНЫ / ЭКСПАНШЕНА В ЗАЛ ПОРТАЛОВ СТОЛИЦЫ
    if playerRegion == "HARANDAR" then
        table.insert(steps, {
            mapID = 2413,
            x = 53.3,
            y = 55.5,
            subMapID = 2576,
            subX = 64.5,
            subY = 71.4,
            zone = isRU and "Харандар (Логово)" or "Harandar (The Den)",
            note = isRU and "Корнистый путь в леса Вечной Песни / Луносвет (Логово, нижний ярус)" or "Rootway to Eversong Woods / Silvermoon (The Den, lower tier)",
        })
        if targetRegion ~= "MIDNIGHT_QUELTHALAS" then
            table.insert(steps, {
                mapID = 2395,
                x = isAlliance and 52.6 or 52.5,
                y = isAlliance and 25.5 or 25.7,
                subMapID = 2393,
                subX = isAlliance and 52.6 or 52.2,
                subY = isAlliance and 64.5 or 65.2,
                zone = isRU and "Луносвет" or "Silvermoon City",
                note = isRU
                    and (isAlliance and "Зал с порталами Луносвета: Портал в Штормград (52.6, 64.5)" or "Зал с порталами Луносвета: Портал в Оргриммар (52.2, 65.2)")
                    or (isAlliance and "Silvermoon Portal Room: Portal to Stormwind (52.6, 64.5)" or "Silvermoon Portal Room: Portal to Orgrimmar (52.2, 65.2)"),
            })
        end
    elseif playerRegion == "VOIDSTORM" then
        local dx, dy, dnote = FindDynamicExitOrPortalOnMap(playerMapID, { "луносвет", "silvermoon", "portal", "портал", "выход" }, isRU)
        table.insert(steps, {
            mapID = playerMapID,
            x = dx or 50.0,
            y = dy or 50.0,
            zone = isRU and "Буря Бездны" or "Voidstorm",
            note = dnote or (isRU and "Портал из Бури Бездны в Луносвет" or "Portal from Voidstorm to Silvermoon"),
        })
        if targetRegion ~= "MIDNIGHT_QUELTHALAS" then
            table.insert(steps, {
                mapID = 2395,
                x = isAlliance and 52.6 or 52.5,
                y = isAlliance and 25.5 or 25.7,
                subMapID = 2393,
                subX = isAlliance and 52.6 or 52.2,
                subY = isAlliance and 64.5 or 65.2,
                zone = isRU and "Луносвет" or "Silvermoon City",
                note = isRU
                    and (isAlliance and "Зал с порталами Луносвета: Портал в Штормград (52.6, 64.5)" or "Зал с порталами Луносвета: Портал в Оргриммар (52.2, 65.2)")
                    or (isAlliance and "Silvermoon Portal Room: Portal to Stormwind (52.6, 64.5)" or "Silvermoon Portal Room: Portal to Orgrimmar (52.2, 65.2)"),
            })
        end
    elseif playerRegion == "MIDNIGHT_QUELTHALAS" then
        table.insert(steps, {
            mapID = 2395,
            x = isAlliance and 52.6 or 52.5,
            y = isAlliance and 25.5 or 25.7,
            subMapID = 2393,
            subX = isAlliance and 52.6 or 52.2,
            subY = isAlliance and 64.5 or 65.2,
            zone = isRU and "Луносвет" or "Silvermoon City",
            note = isRU
                and (isAlliance and "Зал с порталами Луносвета: Портал в Штормград (52.6, 64.5)" or "Зал с порталами Луносвета: Портал в Оргриммар (52.2, 65.2)")
                or (isAlliance and "Silvermoon Portal Room: Portal to Stormwind (52.6, 64.5)" or "Silvermoon Portal Room: Portal to Orgrimmar (52.2, 65.2)"),
        })
    elseif playerRegion == "KHAZ_ALGAR" then
        table.insert(steps, {
            mapID = 2339,
            x = 41.9,
            y = 28.3,
            zone = isRU and "Дорногал" or "Dornogal",
            note = isRU
                and (isAlliance and "Комната порталов Дорногала: Портал в Штормград" or "Комната порталов Дорногала: Портал в Оргриммар")
                or (isAlliance and "Dornogal Portal Room: Portal to Stormwind" or "Dornogal Portal Room: Portal to Orgrimmar"),
        })
    elseif playerRegion == "EMERALD_DREAM" then
        table.insert(steps, {
            mapID = 2200,
            x = 62.7,
            y = 57.6,
            zone = isRU and "Изумрудный Сон" or "Emerald Dream",
            note = isRU and "Портал выхода из Изумрудного Сна (Древняя Ветвь)" or "Emerald Dream Exit Portal (Ancient Bough)",
        })
        if targetRegion ~= "DRAGON_ISLES" then
            table.insert(steps, {
                mapID = 2112,
                x = 57.9,
                y = 35.3,
                zone = isRU and "Вальдраккен" or "Valdrakken",
                note = isRU and "Престол Аспектов (Вальдраккен): Портал в столицу" or "The Seat of the Aspects (Valdrakken): Capital Portal",
            })
        end
    elseif playerRegion == "DRAGON_ISLES" then
        table.insert(steps, {
            mapID = 2112,
            x = 57.9,
            y = 35.3,
            zone = isRU and "Вальдраккен" or "Valdrakken",
            note = isRU and "Престол Аспектов (Вальдраккен): Портал в столицу" or "The Seat of the Aspects (Valdrakken): Capital Portal",
        })
    elseif playerRegion == "SHADOWLANDS" then
        table.insert(steps, {
            mapID = 1670,
            x = 22.4,
            y = 50.2,
            zone = isRU and "Орибос" or "Oribos",
            note = isRU and "Портал в столицу (Кольцо Судеб, Орибос)" or "Capital Portal (Ring of Fates, Oribos)",
        })
    elseif playerRegion == "ZANDALAR" then
        table.insert(steps, {
            mapID = 1165,
            x = 49.9,
            y = 85.0,
            zone = isRU and "Дазар'алор" or "Dazar'alor",
            note = isRU and "Комната порталов в Оргриммар (Великая Печать)" or "Portal Room to Orgrimmar (The Great Seal)",
        })
    elseif playerRegion == "KUL_TIRAS" then
        table.insert(steps, {
            mapID = 1161,
            x = 70.4,
            y = 16.8,
            zone = isRU and "Боралус" or "Boralus",
            note = isRU and "Комната порталов в Штормград (Боралус)" or "Portal Room to Stormwind (Boralus)",
        })
    elseif playerRegion == "BROKEN_ISLES" then
        table.insert(steps, {
            mapID = 627,
            x = isAlliance and 39.5 or 55.3,
            y = isAlliance and 63.2 or 24.0,
            zone = isRU and "Даларан" or "Dalaran",
            note = isRU
                and (isAlliance and "Портал в Штормград (Даларан)" or "Портал в Оргриммар (Даларан)")
                or (isAlliance and "Portal to Stormwind (Dalaran)" or "Portal to Orgrimmar (Dalaran)"),
        })
    elseif playerRegion == "PANDARIA" then
        table.insert(steps, {
            mapID = 371,
            x = isAlliance and 46.2 or 28.5,
            y = isAlliance and 85.2 or 14.0,
            zone = isRU and "Нефритовый лес" or "The Jade Forest",
            note = isRU
                and (isAlliance and "Портал в Штормград (Деревня Лап'дон)" or "Портал в Оргриммар (Деревня Медовой Росы)")
                or (isAlliance and "Portal to Stormwind (Paw'don Village)" or "Portal to Orgrimmar (Honeydew Village)"),
        })
    elseif playerRegion ~= capRegion then
        local dx, dy, dnote = FindDynamicExitOrPortalOnMap(playerMapID, { "оргриммар", "штормград", "портал", "portal", "выход" }, isRU)
        if dx and dy then
            table.insert(steps, {
                mapID = playerMapID,
                x = dx,
                y = dy,
                note = dnote or ((isRU and "Выход / Портал в " or "Exit / Portal to ") .. capName),
            })
        end
    end

    -- ЭТАП Б: СТОЛИЦА (Штормград #84 / Оргриммар #85) -> ПОРТАЛ В КОНТИНЕНТ ЦЕЛИ
    local DEST_PORTAL_NAMES = isRU and {
        PANDARIA            = isAlliance and "Портал в Деревню Лап'дон (Нефритовый лес, Пандария)" or "Портал в Деревню Медовой Росы (Нефритовый лес, Пандария)",
        BROKEN_ISLES        = "Портал в Азсуну / Даларан (Расколотые острова)",
        ARGUS               = "Портал в Азсуну -> Даларан -> Аргус",
        ZANDALAR            = "Портал в Зулдазар (Зандалар)",
        KUL_TIRAS           = "Портал в Боралус (Кул-Тирас)",
        SHADOWLANDS         = "Портал в Орибос (Темные Земли)",
        DRAGON_ISLES        = "Портал в Вальдраккен (Драконьи острова)",
        EMERALD_DREAM       = "Портал в Вальдраккен -> Изумрудный Сон",
        KHAZ_ALGAR          = "Портал в Дорногал (Каз Алгар)",
        MIDNIGHT_QUELTHALAS = "Портал в Луносвет (Midnight)",
        HARANDAR            = "Портал в Луносвет -> Харандар",
        VOIDSTORM           = "Портал в Луносвет -> Буря Бездны",
        NORTHREND           = "Портал в Даларан (Нордскол)",
        OUTLAND             = "Портал в Шаттрат (Запределье)",
        DRAENOR             = "Портал в Ашран (Дренор)",
    } or {
        PANDARIA            = isAlliance and "Portal to Paw'don Village (The Jade Forest, Pandaria)" or "Portal to Honeydew Village (The Jade Forest, Pandaria)",
        BROKEN_ISLES        = "Portal to Azsuna / Dalaran (Broken Isles)",
        ARGUS               = "Portal to Azsuna -> Dalaran -> Argus",
        ZANDALAR            = "Portal to Zuldazar (Zandalar)",
        KUL_TIRAS           = "Portal to Boralus (Kul Tiras)",
        SHADOWLANDS         = "Portal to Oribos (Shadowlands)",
        DRAGON_ISLES        = "Portal to Valdrakken (Dragon Isles)",
        EMERALD_DREAM       = "Portal to Valdrakken -> Emerald Dream",
        KHAZ_ALGAR          = "Portal to Dornogal (Khaz Algar)",
        MIDNIGHT_QUELTHALAS = "Portal to Silvermoon City (Midnight)",
        HARANDAR            = "Portal to Silvermoon -> Harandar",
        VOIDSTORM           = "Portal to Silvermoon -> Voidstorm",
        NORTHREND           = "Portal to Dalaran (Northrend)",
        OUTLAND             = "Portal to Shattrath (Outland)",
        DRAENOR             = "Portal to Ashran (Draenor)",
    }

    if targetRegion ~= capRegion then
        local portalAction = DEST_PORTAL_NAMES[targetRegion] or ((isRU and "Портал в " or "Portal to ") .. (targetZone or "target continent"))
        if not (playerRegion == "HARANDAR" and targetRegion == "MIDNIGHT_QUELTHALAS") then
            local stepX, stepY = capX, capY
            local stepNote = string.format("%s: %s", capName, portalAction)
            if targetRegion == "PANDARIA" then
                stepX = isAlliance and 68.7 or 68.6
                stepY = isAlliance and 17.2 or 40.7
                stepNote = isRU
                    and (isAlliance
                        and "Портал в Деревню Лап'дон (Нефритовый лес) — у шара пандаренов (68.7, 17.2) или в Зале порталов"
                        or "Портал в Деревню Медовой Росы (Нефритовый лес) — Аллея Чести (68.6, 40.7) или в Зале порталов")
                    or (isAlliance
                        and "Portal to Paw'don Village (Jade Forest) — Pandaren Hot Air Balloon (68.7, 17.2) or Portal Room"
                        or "Portal to Honeydew Village (Jade Forest) — Valley of Honor (68.6, 40.7) or Portal Room")
            end
            table.insert(steps, {
                mapID = capMapID,
                x = stepX,
                y = stepY,
                zone = isRU and (isAlliance and "Штормград" or "Оргриммар") or (isAlliance and "Stormwind City" or "Orgrimmar"),
                note = stepNote,
            })
        end
    end

    -- ЭТАП В: ПРОМЕЖУТОЧНЫЙ ПОРТАЛ ХАБА (если цель в Харандаре или Изумрудном Сне)
    if targetRegion == "HARANDAR" and playerRegion ~= "HARANDAR" then
        table.insert(steps, {
            mapID = 2395,
            x = 47.9,
            y = 26.6,
            subMapID = 2393,
            subX = 36.7,
            subY = 68.2,
            zone = isRU and "Луносвет (Сады Памяти)" or "Silvermoon City (Memorial Garden)",
            note = isRU and "Корнистый путь в Харандар (Луносвет 36.7, 68.2)" or "Rootway to Harandar (Silvermoon 36.7, 68.2)",
        })
    elseif targetRegion == "EMERALD_DREAM" and playerRegion ~= "EMERALD_DREAM" then
        table.insert(steps, {
            mapID = 2023,
            x = 18.6,
            y = 52.2,
            zone = isRU and "Равнины Он'ары" or "Ohn'ahran Plains",
            note = isRU and "Портал в Изумрудный Сон (Древняя Ветвь, Равнины Он'ары)" or "Portal to Emerald Dream (Ancient Bough, Ohn'ahran Plains)",
        })
    end

    -- ЭТАП Г: ФИНАЛЬНАЯ ТОЧКА (Маунт / Рарник / Квест)
    table.insert(steps, {
        mapID = targetMapID,
        x = targetX,
        y = targetY,
        zone = targetZone,
        note = targetNote or targetName,
    })

    return steps
end

function addon:ActivateCurrentRouteStep(silent)
    local route = self.activePortalRoute
    if not route or not route.steps or #route.steps == 0 then return end

    local step = route.steps[route.currentStep] or route.steps[#route.steps]
    if not step then return end

    local isRU = (self:GetActiveLocaleCode() == "ruRU")

    if _G.TomTom and _G.TomTom.RemoveWaypoint and self.portalTomTomUids then
        for _, uid in ipairs(self.portalTomTomUids) do
            pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid)
        end
        wipe(self.portalTomTomUids)
    end
    self.portalTomTomUids = self.portalTomTomUids or {}

    local totalSteps = #route.steps
    local stepPrefix = isRU and "Шаг" or "Step"
    local stepLabel = totalSteps > 1
        and string.format("[%s %d/%d] %s", stepPrefix, route.currentStep, totalSteps, step.note or route.targetLabel or route.targetName)
        or string.format("[MountCollector] %s (%s)", route.targetLabel or route.targetName, route.targetName)

    if _G.TomTom and _G.TomTom.AddWaypoint then
        local ok, uid = pcall(_G.TomTom.AddWaypoint, _G.TomTom, step.mapID, step.x / 100.0, step.y / 100.0, {
            title = stepLabel,
            persistent = false,
            minimap = true,
            world = true,
            crazy = true,
        })
        if ok and uid then
            table.insert(self.portalTomTomUids, uid)
            if _G.TomTom.SetCrazyArrow then
                pcall(_G.TomTom.SetCrazyArrow, _G.TomTom, uid, 15, stepLabel)
            end
        end
        if step.subMapID and step.subX and step.subY then
            local okSub, uidSub = pcall(_G.TomTom.AddWaypoint, _G.TomTom, step.subMapID, step.subX / 100.0, step.subY / 100.0, {
                title = stepLabel,
                persistent = false,
                minimap = true,
                world = true,
                crazy = true,
            })
            if okSub and uidSub then
                table.insert(self.portalTomTomUids, uidSub)
            end
        end
    end

    local pinMapID, pinX, pinY = ResolvePinnableMapCoords(step.mapID, step.x / 100.0, step.y / 100.0)
    if C_Map and C_Map.SetUserWaypoint and _G.UiMapPoint and _G.UiMapPoint.CreateFromCoordinates then
        local okCan, canSet = pcall(C_Map.CanSetUserWaypointOnMap, pinMapID)
        if not okCan or canSet then
            local uiPt = UiMapPoint.CreateFromCoordinates(pinMapID, pinX, pinY)
            pcall(C_Map.SetUserWaypoint, uiPt)
            self.lastAddonWaypoint = {
                mapID = pinMapID,
                x = pinX,
                y = pinY,
                setAt = GetTime(),
                mountID = route.mountID,
                npcID = route.npcID,
            }
            local superTrackAPI = _G.C_SuperTrack or _G.C_SuperTracked
            if superTrackAPI and superTrackAPI.SetSuperTrackedUserWaypoint then
                pcall(superTrackAPI.SetSuperTrackedUserWaypoint, true)
                C_Timer.After(0.08, function()
                    local stAPI = _G.C_SuperTrack or _G.C_SuperTracked
                    if stAPI and stAPI.SetSuperTrackedUserWaypoint and C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
                        pcall(stAPI.SetSuperTrackedUserWaypoint, true)
                    end
                end)
            end
        end
    end

    if not silent then
        local zoneName = step.zone or self:GetMapName(step.mapID) or "Zone"
        local x10000 = math.max(0, math.min(10000, math.floor(pinX * 10000 + 0.5)))
        local y10000 = math.max(0, math.min(10000, math.floor(pinY * 10000 + 0.5)))
        local pinLink = string.format("|cffffff00|Hworldmap:%d:%d:%d|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a %s (%.1f, %.1f)]|h|r", pinMapID, x10000, y10000, step.note or zoneName, step.x, step.y)
        if totalSteps > 1 then
            local hdr = isRU and "Маршрут" or "Route"
            print(string.format("|cff00ccff[MountCollector %s %d/%d]|r %s -> |cffa335ee[%s]|r", hdr, route.currentStep, totalSteps, pinLink, route.targetName))
        else
            local pinPrefix = isRU and "3D-метка:" or "3D Pin:"
            print(string.format("|cff00ccff[MountCollector]|r %s %s -> |cffa335ee[%s]|r", pinPrefix, pinLink, route.targetName))
        end
    end
end

function addon:CheckPortalRouteProgress()
    local route = self.activePortalRoute
    if not route or not route.steps or #route.steps <= 1 then return end

    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not playerMapID then return end

    local playerRegion = GetMapMacroRegion(playerMapID)
    local playerInstID = GetMapInstanceID(playerMapID)
    local finalStep = route.steps[#route.steps]
    local finalRegion = GetMapMacroRegion(finalStep.mapID)
    local finalInstID = GetMapInstanceID(finalStep.mapID)

    if playerMapID == finalStep.mapID
        or (playerRegion == finalRegion and finalRegion ~= "HARANDAR" and finalRegion ~= "VOIDSTORM" and finalRegion ~= "EMERALD_DREAM")
        or (playerInstID and finalInstID and playerInstID == finalInstID and playerRegion == finalRegion)
    then
        if route.currentStep ~= #route.steps then
            route.currentStep = #route.steps
            self:ActivateCurrentRouteStep(false)
        elseif C_Map and C_Map.HasUserWaypoint and not C_Map.HasUserWaypoint() then
            self:ActivateCurrentRouteStep(true)
        end
        return
    end

    for i = #route.steps, 1, -1 do
        local st = route.steps[i]
        local stRegion = GetMapMacroRegion(st.mapID)
        if playerMapID == st.mapID or playerMapID == st.subMapID or playerRegion == stRegion then
            if i > route.currentStep then
                route.currentStep = i
                self:ActivateCurrentRouteStep(false)
            elseif i == route.currentStep then
                if C_Map and C_Map.HasUserWaypoint and not C_Map.HasUserWaypoint() then
                    self:ActivateCurrentRouteStep(true)
                else
                    local stAPI = _G.C_SuperTrack or _G.C_SuperTracked
                    if stAPI and stAPI.IsSuperTrackingUserWaypoint and not stAPI.IsSuperTrackingUserWaypoint() then
                        pcall(stAPI.SetSuperTrackedUserWaypoint, true)
                    end
                end
            end
            return
        end
    end
end

-- Очистить все активные метки аддона (Blizzard UserWaypoint, TomTom, межконтинентальный маршрут и подсветку на карте)
function addon:ClearAddonWaypoints()
    local lastWP = self.lastAddonWaypoint
    if lastWP and C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint then
        local isStillAddonPin = true
        local ok, wp = pcall(C_Map.GetUserWaypoint)
        if ok and wp and wp.uiMapID and wp.position and wp.position.GetXY then
            local wx, wy = wp.position:GetXY()
            if SafeNotSecret(wx) and SafeNotSecret(wy) and wx and wy then
                if wp.uiMapID ~= lastWP.mapID or math.abs(wx - lastWP.x) > 0.015 or math.abs(wy - lastWP.y) > 0.015 then
                    isStillAddonPin = false
                end
            end
        end
        if isStillAddonPin and C_Map.ClearUserWaypoint then
            pcall(C_Map.ClearUserWaypoint)
        end
    end
    self.lastAddonWaypoint = nil
    self.activePortalRoute = nil
    self.highlightedMapMountID = nil

    if _G.TomTom and _G.TomTom.RemoveWaypoint then
        if self.lastTomTomUid then
            pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, self.lastTomTomUid)
            self.lastTomTomUid = nil
        end
        if self.multiTomTomUids then
            for _, uid in ipairs(self.multiTomTomUids) do
                pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid)
            end
            wipe(self.multiTomTomUids)
        end
        if self.portalTomTomUids then
            for _, uid in ipairs(self.portalTomTomUids) do
                pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid)
            end
            wipe(self.portalTomTomUids)
        end
    end
    if self.multiTomTomByNpc then
        wipe(self.multiTomTomByNpc)
    end
    if self.RefreshWorldMapPins then
        self:RefreshWorldMapPins()
    end
end

-- Поставить метку на карте и 3D-стрелку (Blizzard UserWaypoint + SuperTrack + TomTom + межконтинентальный маршрут по порталам)
function addon:SetMountWaypoint(mountID, preferredMapID, liveX, liveY, customLabel, silent, customMountNames, explicitNpcID)
    local name = customMountNames or self:GetMountInfoByID(mountID) or "Mount"
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
    local resolvedNpcID = explicitNpcID or (c and c.npcID) or nil
    if not resolvedNpcID and info and info.npcs then
        local onlyNpc = nil
        local countNpcs = 0
        for nid in pairs(info.npcs) do
            onlyNpc = nid
            countNpcs = countNpcs + 1
        end
        if countNpcs == 1 then
            resolvedNpcID = onlyNpc
        end
    end
    if not validCustomLabel and c then
        local dispNpc = self:GetNpcDisplayName(c.npcID, c.n)
        if IsValidNpcName(dispNpc) then
            npcLabel = dispNpc
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

    -- Проверяем, нужен ли многошаговый маршрут через порталы на другой континент
    local targetZoneName = self:GetMapName(mapID)
    local steps = self:BuildMultiHopRoute(mapID, dispX, dispY, name, targetZoneName, npcLabel)
    if #steps > 1 then
        self.activePortalRoute = {
            mountID = mountID,
            npcID = resolvedNpcID,
            targetName = name,
            targetLabel = npcLabel,
            targetMapID = mapID,
            steps = steps,
            currentStep = 1,
        }
        self:ActivateCurrentRouteStep(silent)
        self:StartSpawnTourTicker()
        if not silent then
            local chainParts = {}
            for idx, st in ipairs(steps) do
                table.insert(chainParts, string.format("%d) %s", idx, st.note or st.zone or ""))
            end
            local isRU = (self:GetActiveLocaleCode() == "ruRU")
            local routeHdr = isRU and "|cff00ccff[MountCollector Навигатор]|r Маршрут по порталам: |cffffffff" or "|cff00ccff[MountCollector Navigator]|r Portal route: |cffffffff"
            print(routeHdr .. table.concat(chainParts, " -> ") .. "|r")
        end
        return true
    else
        self.activePortalRoute = nil
        if _G.TomTom and _G.TomTom.RemoveWaypoint and self.portalTomTomUids then
            for _, uid in ipairs(self.portalTomTomUids) do
                pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid)
            end
            wipe(self.portalTomTomUids)
        end
    end

    -- 1. Стандартная метка и 3D-ромбик Blizzard (с авто-проекцией на родительскую карту для городов/подзон вроде Даларана или Дорногала)
    local wpMapID, wpNormX, wpNormY = ResolvePinnableMapCoords(mapID, normX, normY)
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pcall(function()
            local pt = UiMapPoint.CreateFromCoordinates(wpMapID, wpNormX, wpNormY)
            C_Map.SetUserWaypoint(pt)
            self.lastAddonWaypoint = {
                mapID = wpMapID,
                rawMapID = mapID,
                x = wpNormX,
                y = wpNormY,
                setAt = GetTime(),
                mountID = mountID,
                npcID = resolvedNpcID,
            }
            local superTrackAPI = _G.C_SuperTrack or _G.C_SuperTracked
            if superTrackAPI and superTrackAPI.SetSuperTrackedUserWaypoint then
                superTrackAPI.SetSuperTrackedUserWaypoint(true)
                C_Timer.After(0.05, function()
                    local stAPI = _G.C_SuperTrack or _G.C_SuperTracked
                    if stAPI and stAPI.SetSuperTrackedUserWaypoint and C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
                        pcall(stAPI.SetSuperTrackedUserWaypoint, true)
                    end
                end)
            end
        end)
    end

    -- 2. Стрелка TomTom (опционально, если установлен TomTom)
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
            local x10000 = math.max(0, math.min(10000, math.floor(wpNormX * 10000 + 0.5)))
            local y10000 = math.max(0, math.min(10000, math.floor(wpNormY * 10000 + 0.5)))
            local pinLink = string.format("|cffffff00|Hworldmap:%d:%d:%d|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a %s (%.1f, %.1f)]|h|r", wpMapID, x10000, y10000, npcLabel, dispX, dispY)
            local pinPrefix = (self:GetActiveLocaleCode() == "ruRU") and "3D-метка:" or "3D Pin:"
            print(string.format("|cff00ccff[MountCollector]|r %s %s -> |cffa335ee[%s]|r", pinPrefix, pinLink, name))
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
    local name = self:GetMountInfoByID(mountID) or "Mount"
    local coords = {}
    local seen = {}

    if info and type(info.coords) == "table" then
        for _, c in ipairs(info.coords) do
            if c.m and c.m > 0 and c.m < 5000 and c.x and c.x > 0 and c.y and c.y > 0 then
                local key = string.format("%d:%.1f:%.1f", c.m, c.x, c.y)
                local existingIdx = seen[key]
                if not existingIdx then
                    table.insert(coords, c)
                    seen[key] = #coords
                elseif c.npcID and not coords[existingIdx].npcID then
                    coords[existingIdx] = c
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
    self.multiTomTomByNpc = {}

    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local availCoords = {}
    for _, c in ipairs(coords) do
        if not (c.npcID and self:IsNpcLockedToday(c.npcID)) then
            table.insert(availCoords, c)
        end
    end

    if #availCoords == 0 then
        self.activeSpawnTour = nil
        self:ClearAddonWaypoints()
        return false
    end
    local routeCoords = availCoords

    -- Сортируем маршрут облёта по ближайшему соседу (Nearest-Neighbor) от текущей позиции игрока
    local px, py = nil, nil
    if playerMapID and C_Map and C_Map.GetPlayerMapPosition then
        local okPos, pos = pcall(C_Map.GetPlayerMapPosition, playerMapID, "player")
        if okPos and pos and pos.GetXY then
            local rx, ry = pos:GetXY()
            if SafeNotSecret(rx) and SafeNotSecret(ry) and rx and ry and rx > 0 and ry > 0 then
                px, py = rx * 100.0, ry * 100.0
            end
        end
    end

    if #routeCoords > 1 and px and py then
        local pool = {}
        for _, c in ipairs(routeCoords) do
            table.insert(pool, c)
        end
        local sorted = {}
        local curX, curY, curMap = px, py, playerMapID
        while #pool > 0 do
            local bestIdx = 1
            local bestScore = math.huge
            for i, cand in ipairs(pool) do
                local mapPenalty = (cand.m == curMap) and 0 or 100000
                local dx = (cand.x or 50) - curX
                local dy = (cand.y or 50) - curY
                local score = mapPenalty + (dx * dx + dy * dy)
                if score < bestScore then
                    bestScore = score
                    bestIdx = i
                end
            end
            local chosen = table.remove(pool, bestIdx)
            table.insert(sorted, chosen)
            curX = chosen.x or curX
            curY = chosen.y or curY
            curMap = chosen.m or curMap
        end
        routeCoords = sorted
    end

    local primaryCoord = routeCoords[1] or self:GetBestMountCoords(mountID, playerMapID)

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
                    if c.npcID then
                        self.multiTomTomByNpc[c.npcID] = self.multiTomTomByNpc[c.npcID] or {}
                        table.insert(self.multiTomTomByNpc[c.npcID], uid)
                    end
                end
            end)
        end
    end

    if #routeCoords > 1 then
        self.activeSpawnTour = {
            mountID = mountID,
            name = name,
            points = routeCoords,
            index = 1,
            total = #routeCoords,
            stepSetAt = GetTime(),
        }
        self:StartSpawnTourTicker()
        local dispNpc = self:GetNpcDisplayName(primaryCoord.npcID, primaryCoord.n)
        local pLabel = (IsValidNpcName(dispNpc) and dispNpc) or ((primaryCoord.n and primaryCoord.n ~= "") and primaryCoord.n) or (info and info.boss) or name
        self:SetMountWaypoint(mountID, primaryCoord.m, primaryCoord.x, primaryCoord.y, string.format("[1/%d] %s", #routeCoords, pLabel), true, nil, primaryCoord.npcID)
        print(string.format(L.CHAT_TOUR_STARTED, name, #routeCoords, pLabel, primaryCoord.x, primaryCoord.y))
    else
        self.activeSpawnTour = nil
        self:SetMountWaypoint(mountID, primaryCoord.m, primaryCoord.x, primaryCoord.y, self:GetNpcDisplayName(primaryCoord.npcID, primaryCoord.n) or (info and info.boss), false, nil, primaryCoord.npcID)
    end

    if openWorldMap and primaryCoord.m and OpenWorldMap then
        pcall(OpenWorldMap, primaryCoord.m)
    end
    if self.RefreshWorldMapPins then
        self:RefreshWorldMapPins()
    end

    return true
end

-- Проверить, не переключился ли игрок вручную на свою метку на карте или на отслеживание квеста
function addon:CheckAndCancelTourIfUserOverrode()
    if not self.activeSpawnTour and not self.activePortalRoute then return true end
    local lastWP = self.lastAddonWaypoint
    if not lastWP or (GetTime() - (lastWP.setAt or 0)) <= 1.5 then
        return false
    end

    -- 1. Игрок вручную удалил метку с карты
    if C_Map and C_Map.HasUserWaypoint and not C_Map.HasUserWaypoint() then
        self.activeSpawnTour = nil
        self.activePortalRoute = nil
        if self.RefreshWorldMapPins then self:RefreshWorldMapPins() end
        return true
    end

    -- 2. Игрок поставил СВОЮ точку на карте (координаты или карта отличаются от точки нашего тура)
    local isStillAddonPin = true
    if C_Map and C_Map.GetUserWaypoint then
        local ok, wp = pcall(C_Map.GetUserWaypoint)
        if ok and wp and wp.uiMapID and wp.position and wp.position.GetXY then
            local wx, wy = wp.position:GetXY()
            if SafeNotSecret(wx) and SafeNotSecret(wy) and wx and wy then
                if wp.uiMapID ~= lastWP.mapID or math.abs(wx - lastWP.x) > 0.008 or math.abs(wy - lastWP.y) > 0.008 then
                    isStillAddonPin = false
                end
            end
        end
    end
    if not isStillAddonPin then
        -- Не трогаем новую пользовательскую метку, просто тихо выходим из режима облёта рарников!
        self.activeSpawnTour = nil
        self.activePortalRoute = nil
        if self.RefreshWorldMapPins then self:RefreshWorldMapPins() end
        return true
    end

    -- 3. Игрок кликнул по квесту в трекере заданий (или снял SuperTrack с метки): выходим из тура и убираем нашу старую метку
    local stAPI = _G.C_SuperTrack or _G.C_SuperTracked
    if stAPI and stAPI.IsSuperTrackingUserWaypoint and not stAPI.IsSuperTrackingUserWaypoint() then
        self.activeSpawnTour = nil
        self.activePortalRoute = nil
        if isStillAddonPin and C_Map and C_Map.ClearUserWaypoint then
            pcall(C_Map.ClearUserWaypoint)
        end
        if self.RefreshWorldMapPins then self:RefreshWorldMapPins() end
        return true
    end

    return false
end

-- Авто-переключение 3D-ромбика Blizzard по мере облёта точек спавна и переходов по порталам (без TomTom)
function addon:StartSpawnTourTicker()
    if self.spawnTourTicker then return end
    self.spawnTourTicker = C_Timer.NewTicker(0.75, function()
        if self.activePortalRoute then
            self:CheckPortalRouteProgress()
        end
        if self:CheckAndCancelTourIfUserOverrode() then
            if self.spawnTourTicker then
                self.spawnTourTicker:Cancel()
                self.spawnTourTicker = nil
            end
            return
        end
        if self.activePortalRoute and self.activePortalRoute.steps and self.activePortalRoute.currentStep < #self.activePortalRoute.steps then
            return
        end
        local tour = self.activeSpawnTour
        if not tour or not tour.points or tour.index > tour.total then
            if not self.activePortalRoute and self.spawnTourTicker then
                self.spawnTourTicker:Cancel()
                self.spawnTourTicker = nil
            end
            return
        end
        local pt = tour.points[tour.index]
        if not pt then return end

        local reached = false
        if pt.npcID and self:IsNpcLockedToday(pt.npcID) then
            reached = true
        end

        -- Если прямо сейчас на экране горит баннер живого рарника (мы с ним дерёмся или летим к нему),
        -- не переключаем маршрут дальше, пока рарник не будет убит или баннер не закроется!
        local alertActive = _G.MountCollectorAlertFrame and _G.MountCollectorAlertFrame:IsShown()
        if alertActive and not reached then
            return
        end

        -- 1. Проверка реальной 3D-дистанции до активного ромбика через C_Navigation.GetDistance() (в ярдах, с запасом под полёт на драконе ~65 ярдов!)
        if not reached and _G.C_Navigation and _G.C_Navigation.GetDistance then
            local okDist, navDist = pcall(_G.C_Navigation.GetDistance)
            if okDist and SafeNotSecret(navDist) and type(navDist) == "number" and navDist > 0 and navDist <= 65 then
                local now = GetTime()
                if not tour.stepSetAt or (now - tour.stepSetAt) > 1.2 then
                    reached = true
                end
            end
        end

        -- 2. Проверка по 2D-координатам карты (работает на любой высоте полёта!)
        if not reached and C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
            local pMap = C_Map.GetBestMapForUnit("player")
            local checkMap = pt.m or pMap
            if checkMap then
                local okPos, pos = pcall(C_Map.GetPlayerMapPosition, checkMap, "player")
                if okPos and pos and pos.GetXY then
                    local rx, ry = pos:GetXY()
                    if SafeNotSecret(rx) and SafeNotSecret(ry) and rx and ry and rx > 0 and ry > 0 then
                        local dx = (rx * 100.0) - pt.x
                        local dy = (ry * 100.0) - pt.y
                        if (dx * dx + dy * dy) <= 20.25 then -- ~4.5 единицы карты (~48 ярдов по земле на любой высоте!)
                            local now = GetTime()
                            if not tour.stepSetAt or (now - tour.stepSetAt) > 1.2 then
                                reached = true
                            end
                        end
                    end
                end
            end
        end

        if reached then
            self:AdvanceSpawnTourStep(true)
        end
    end)
end

function addon:AdvanceSpawnTourStep(fromAutoProximity)
    local tour = self.activeSpawnTour
    if not tour or not tour.points then return false end
    tour.index = (tour.index or 1) + 1
    while tour.index <= tour.total do
        local nextCand = tour.points[tour.index]
        if nextCand and nextCand.npcID and self:IsNpcLockedToday(nextCand.npcID) then
            tour.index = tour.index + 1
        else
            break
        end
    end
    if tour.index <= tour.total then
        local nextPt = tour.points[tour.index]
        tour.stepSetAt = GetTime()
        local dispNpc = self:GetNpcDisplayName(nextPt.npcID, nextPt.n)
        local nLabel = (IsValidNpcName(dispNpc) and dispNpc) or ((nextPt.n and nextPt.n ~= "") and nextPt.n) or tour.name
        self:SetMountWaypoint(tour.mountID, nextPt.m, nextPt.x, nextPt.y, string.format("[%d/%d] %s", tour.index, tour.total, nLabel), true, nil, nextPt.npcID)
        print(string.format(L.CHAT_TOUR_NEXT, tour.index, tour.total, nLabel, nextPt.x, nextPt.y))
        if self.RefreshWorldMapPins then
            self:RefreshWorldMapPins()
        end
        return true
    else
        -- Проверяем, остались ли ещё НЕ убитые нами сегодня рарники (которых в первом круге убили другие игроки):
        -- если остались и их больше 1 (или мы убили хотя бы часть тура), автоматически начинаем новый круг только по живым!
        local remaining = {}
        for _, c in ipairs(tour.points) do
            if c.npcID and not self:IsNpcLockedToday(c.npcID) then
                table.insert(remaining, c)
            end
        end
        if #remaining > 1 or (#remaining == 1 and tour.total > 1) then
            tour.points = remaining
            tour.index = 1
            tour.total = #remaining
            tour.stepSetAt = GetTime()
            local firstPt = remaining[1]
            local dispNpc = self:GetNpcDisplayName(firstPt.npcID, firstPt.n)
            local nLabel = (IsValidNpcName(dispNpc) and dispNpc) or ((firstPt.n and firstPt.n ~= "") and firstPt.n) or tour.name
            self:SetMountWaypoint(tour.mountID, firstPt.m, firstPt.x, firstPt.y, string.format("[1/%d] %s", tour.total, nLabel), true, nil, firstPt.npcID)
            print(string.format(L.CHAT_TOUR_NEXT, 1, tour.total, nLabel, firstPt.x, firstPt.y))
            if self.RefreshWorldMapPins then
                self:RefreshWorldMapPins()
            end
            return true
        end
        print(string.format(L.CHAT_TOUR_FINISHED, tour.name, tour.total))
        self.activeSpawnTour = nil
        self:ClearAddonWaypoints()
        return false
    end
end

function addon:SyncActiveTourAfterKillOrAlert(killedNpcID, killedMountID)
    if self.inSyncAfterKill then return end
    self.inSyncAfterKill = true

    -- 1. Скрываем радар-баннер, если он относится к убитому или закрытому на сегодня рарнику
    if _G.MountCollectorAlertFrame and _G.MountCollectorAlertFrame:IsShown() then
        local aNpc = _G.MountCollectorAlertFrame.alertNpcID
        local aMount = _G.MountCollectorAlertFrame.currentMountID
        if (killedNpcID and aNpc == killedNpcID)
            or (aNpc and self:IsNpcLockedToday(aNpc))
            or (killedMountID and aMount == killedMountID and self:IsMountRareLockedToday(aMount))
        then
            _G.MountCollectorAlertFrame:Hide()
        end
    end

    -- 2. Удаляем одиночные пины TomTom для убитого/закрытого рарника из мульти-списка тура
    if _G.TomTom and _G.TomTom.RemoveWaypoint and self.multiTomTomByNpc then
        if killedNpcID and self.multiTomTomByNpc[killedNpcID] then
            for _, uid in ipairs(self.multiTomTomByNpc[killedNpcID]) do
                pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid)
            end
            self.multiTomTomByNpc[killedNpcID] = nil
        end
        for nid, uidList in pairs(self.multiTomTomByNpc) do
            if self:IsNpcLockedToday(nid) then
                for _, uid in ipairs(uidList) do
                    pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid)
                end
                self.multiTomTomByNpc[nid] = nil
            end
        end
    end

    local tour = self.activeSpawnTour
    if tour and tour.points then
        if self:CheckAndCancelTourIfUserOverrode() then
            self.inSyncAfterKill = false
            return
        end
        local curPt = tour.points[tour.index]
        if curPt and ((killedNpcID and curPt.npcID == killedNpcID) or (curPt.npcID and self:IsNpcLockedToday(curPt.npcID))) then
            self:AdvanceSpawnTourStep(true)
        elseif curPt and not (_G.MountCollectorAlertFrame and _G.MountCollectorAlertFrame:IsShown()) then
            local dispNpc = self:GetNpcDisplayName(curPt.npcID, curPt.n)
            local nLabel = (IsValidNpcName(dispNpc) and dispNpc) or ((curPt.n and curPt.n ~= "") and curPt.n) or tour.name
            self:SetMountWaypoint(tour.mountID, curPt.m, curPt.x, curPt.y, string.format("[%d/%d] %s", tour.index, tour.total, nLabel), true, nil, curPt.npcID)
            if self.RefreshWorldMapPins then
                self:RefreshWorldMapPins()
            end
        end
        self.inSyncAfterKill = false
        return
    end

    -- 3. Если активного многоточечного тура нет, но стоит одиночная метка нашего аддона (с баннера, карты или /mc):
    -- проверяем, не относится ли она к только что убитому рарнику (или уже закрытому на сегодня маунту), и сразу убираем её с карты!
    local lastWP = self.lastAddonWaypoint
    if lastWP then
        local shouldClear = false
        if killedNpcID and lastWP.npcID and lastWP.npcID == killedNpcID then
            shouldClear = true
        elseif lastWP.npcID and self:IsNpcLockedToday(lastWP.npcID) then
            shouldClear = true
        elseif killedMountID and lastWP.mountID and lastWP.mountID == killedMountID and self:IsMountRareLockedToday(killedMountID) then
            shouldClear = true
        elseif lastWP.mountID and self:IsMountRareLockedToday(lastWP.mountID) then
            shouldClear = true
        elseif killedNpcID and lastWP.mountID and self.MountsByNpc and self.MountsByNpc[killedNpcID] then
            for _, mID in ipairs(self.MountsByNpc[killedNpcID]) do
                if mID == lastWP.mountID then
                    shouldClear = true
                    break
                end
            end
        end
        if shouldClear then
            self:ClearAddonWaypoints()
            self.inSyncAfterKill = false
            return
        end
    end

    if self.RefreshWorldMapPins then
        self:RefreshWorldMapPins()
    end
    self.inSyncAfterKill = false
end


-- Универсальная навигация для любого маунта (квестового, данжевого, ворлдбосса или дропового рарника)
-- ВАЖНО: Никогда не открывает принудительно Карту Мира (WorldMapFrame), чтобы не перекрывать экран игрока в полёте!
function addon:NavigateMountTarget(mountID, forceFirstStep)
    if not mountID then return end
    local qStatus = self:GetMountQuestChainStatus(mountID)
    if qStatus then
        local stepIdx = forceFirstStep and 1 or qStatus.currentStepIndex or 1
        self:NavigateMountQuestStep(mountID, stepIdx, false)
        return
    end
    local dStatus = self:GetDungeonMountStatus(mountID)
    if dStatus and dStatus.mapID and dStatus.x and dStatus.y then
        if dStatus.sourceKind == "WORLD_BOSS" then
            self:SetMountWaypoint(mountID, dStatus.mapID, dStatus.x, dStatus.y, dStatus.bossTitle, false)
        else
            self:SetMountWaypoint(mountID, dStatus.mapID, dStatus.x, dStatus.y, dStatus.instanceTitle .. " (" .. dStatus.bossTitle .. ")", false)
        end
        return
    end
    local info = self.DropInfoByMount and self.DropInfoByMount[mountID]
    if forceFirstStep then
        self:PinAllMountSpawns(mountID, false)
        return
    end
    if self.activeSpawnTour and self.activeSpawnTour.mountID == mountID and self.AdvanceSpawnTourStep then
        self:AdvanceSpawnTourStep(false)
        return
    end
    if info and type(info.coords) == "table" and #info.coords > 1 then
        self:PinAllMountSpawns(mountID, false)
        return
    end
    local c = self:GetBestMountCoords(mountID)
    if c then
        self:SetMountWaypoint(mountID, c.m, c.x, c.y, c.n or (info and info.boss), false)
    else
        self:SetMountWaypoint(mountID, nil, nil, nil, info and info.boss, false)
    end
end
