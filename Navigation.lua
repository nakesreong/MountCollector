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

    -- 3. Если у маунта только 1 точка (босс данжа/рейда без многих спавнов), возвращаем её
    if #info.coords == 1 then
        return info.coords[1]
    end
    return nil
end

-- Поставить метку на карте и 3D-стрелку (Blizzard UserWaypoint + SuperTrack + TomTom)
function addon:SetMountWaypoint(mountID, preferredMapID, liveX, liveY, customLabel, silent, customMountNames)
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

    -- 1. Стандартная метка и 3D-ромбик Blizzard (с авто-проекцией на родительскую карту для городов/подзон вроде Даларана или Дорногала)
    local wpMapID, wpNormX, wpNormY = mapID, normX, normY
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pcall(function()
            local canSet = true
            if C_Map.CanSetUserWaypointOnMap then
                local ok, res = pcall(C_Map.CanSetUserWaypointOnMap, wpMapID)
                if ok then canSet = res end
            end
            if not canSet and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and C_Map.GetMapInfo and CreateVector2D then
                local instID, worldPos = C_Map.GetWorldPosFromMapPos(wpMapID, CreateVector2D(wpNormX, wpNormY))
                local curMap = wpMapID
                for _ = 1, 5 do
                    local mInfo = C_Map.GetMapInfo(curMap)
                    local parentID = mInfo and mInfo.parentMapID
                    if not parentID or parentID <= 0 or parentID == curMap then break end
                    curMap = parentID
                    if C_Map.CanSetUserWaypointOnMap(curMap) and instID and worldPos then
                        local _, parentVec = C_Map.GetMapPosFromWorldPos(instID, worldPos, curMap)
                        if parentVec and parentVec.GetXY then
                            local px, py = parentVec:GetXY()
                            if px and py and px > 0 and px < 1 and py > 0 and py < 1 then
                                wpMapID, wpNormX, wpNormY = curMap, px, py
                                canSet = true
                                break
                            end
                        end
                    end
                end
            end
            local pt = UiMapPoint.CreateFromCoordinates(wpMapID, wpNormX, wpNormY)
            C_Map.SetUserWaypoint(pt)
            self.lastAddonWaypoint = {
                mapID = wpMapID,
                x = wpNormX,
                y = wpNormY,
                setAt = GetTime(),
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

    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local availCoords = {}
    for _, c in ipairs(coords) do
        if not (c.npcID and self:IsNpcLockedToday(c.npcID)) then
            table.insert(availCoords, c)
        end
    end

    if #availCoords == 0 then
        self.activeSpawnTour = nil
        if self.RefreshWorldMapPins then
            self:RefreshWorldMapPins()
        end
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
        self:SetMountWaypoint(mountID, primaryCoord.m, primaryCoord.x, primaryCoord.y, string.format("[1/%d] %s", #routeCoords, pLabel), true)
        print(string.format(L.CHAT_TOUR_STARTED, name, #routeCoords, pLabel, primaryCoord.x, primaryCoord.y))
    else
        self.activeSpawnTour = nil
        self:SetMountWaypoint(mountID, primaryCoord.m, primaryCoord.x, primaryCoord.y, self:GetNpcDisplayName(primaryCoord.npcID, primaryCoord.n) or (info and info.boss), false)
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
    if not self.activeSpawnTour then return true end
    local lastWP = self.lastAddonWaypoint
    if not lastWP or (GetTime() - (lastWP.setAt or 0)) <= 1.0 then
        return false
    end

    -- 1. Игрок вручную удалил метку с карты
    if C_Map and C_Map.HasUserWaypoint and not C_Map.HasUserWaypoint() then
        self.activeSpawnTour = nil
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
        if self.RefreshWorldMapPins then self:RefreshWorldMapPins() end
        return true
    end

    -- 3. Игрок кликнул по квесту в трекере заданий (или снял SuperTrack с метки): выходим из тура и убираем нашу старую метку
    local stAPI = _G.C_SuperTrack or _G.C_SuperTracked
    if stAPI and stAPI.IsSuperTrackingUserWaypoint and not stAPI.IsSuperTrackingUserWaypoint() then
        self.activeSpawnTour = nil
        if isStillAddonPin and C_Map and C_Map.ClearUserWaypoint then
            pcall(C_Map.ClearUserWaypoint)
        end
        if self.RefreshWorldMapPins then self:RefreshWorldMapPins() end
        return true
    end

    return false
end

-- Авто-переключение 3D-ромбика Blizzard по мере облёта точек спавна (без TomTom)
function addon:StartSpawnTourTicker()
    if self.spawnTourTicker then return end
    self.spawnTourTicker = C_Timer.NewTicker(0.75, function()
        if self:CheckAndCancelTourIfUserOverrode() then
            if self.spawnTourTicker then
                self.spawnTourTicker:Cancel()
                self.spawnTourTicker = nil
            end
            return
        end
        local tour = self.activeSpawnTour
        if not tour or not tour.points or tour.index > tour.total then
            if self.spawnTourTicker then
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
        self:SetMountWaypoint(tour.mountID, nextPt.m, nextPt.x, nextPt.y, string.format("[%d/%d] %s", tour.index, tour.total, nLabel), true)
        print(string.format(L.CHAT_TOUR_NEXT, tour.index, tour.total, nLabel, nextPt.x, nextPt.y))
        if self.RefreshWorldMapPins then
            self:RefreshWorldMapPins()
        end
        return true
    else
        -- Проверяем, остались ли ещё НЕ убитые нами сегодня рарники (которых в первом круге убили другие игроки):
        -- если остались, автоматически начинаем новый круг только по живым (не убитым нами сегодня)!
        local remaining = {}
        for _, c in ipairs(tour.points) do
            if not (c.npcID and self:IsNpcLockedToday(c.npcID)) then
                table.insert(remaining, c)
            end
        end
        if #remaining > 0 then
            tour.points = remaining
            tour.index = 1
            tour.total = #remaining
            tour.stepSetAt = GetTime()
            local firstPt = remaining[1]
            local dispNpc = self:GetNpcDisplayName(firstPt.npcID, firstPt.n)
            local nLabel = (IsValidNpcName(dispNpc) and dispNpc) or ((firstPt.n and firstPt.n ~= "") and firstPt.n) or tour.name
            self:SetMountWaypoint(tour.mountID, firstPt.m, firstPt.x, firstPt.y, string.format("[1/%d] %s", tour.total, nLabel), true)
            print(string.format(L.CHAT_TOUR_NEXT, 1, tour.total, nLabel, firstPt.x, firstPt.y))
            if self.RefreshWorldMapPins then
                self:RefreshWorldMapPins()
            end
            return true
        end
        print(string.format(L.CHAT_TOUR_FINISHED, tour.name, tour.total))
        self.activeSpawnTour = nil
        if self.RefreshWorldMapPins then
            self:RefreshWorldMapPins()
        end
        return false
    end
end

function addon:SyncActiveTourAfterKillOrAlert()
    if _G.MountCollectorAlertFrame and _G.MountCollectorAlertFrame:IsShown() then
        local aNpc = _G.MountCollectorAlertFrame.alertNpcID
        if aNpc and self:IsNpcLockedToday(aNpc) then
            _G.MountCollectorAlertFrame:Hide()
            return
        end
    end
    if self:CheckAndCancelTourIfUserOverrode() then return end
    local tour = self.activeSpawnTour
    if not tour or not tour.points then return end
    local curPt = tour.points[tour.index]
    if curPt and curPt.npcID and self:IsNpcLockedToday(curPt.npcID) then
        self:AdvanceSpawnTourStep(true)
    elseif curPt and not (_G.MountCollectorAlertFrame and _G.MountCollectorAlertFrame:IsShown()) then
        local dispNpc = self:GetNpcDisplayName(curPt.npcID, curPt.n)
        local nLabel = (IsValidNpcName(dispNpc) and dispNpc) or ((curPt.n and curPt.n ~= "") and curPt.n) or tour.name
        self:SetMountWaypoint(tour.mountID, curPt.m, curPt.x, curPt.y, string.format("[%d/%d] %s", tour.index, tour.total, nLabel), true)
        if self.RefreshWorldMapPins then
            self:RefreshWorldMapPins()
        end
    end
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
