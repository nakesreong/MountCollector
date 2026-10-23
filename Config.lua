local _, addon = ...

-- ============================================================================
-- MountCollector — Config.lua
-- Модуль конфигурации и настроек аддона:
--   1. Встроенная вкладка «Настройки» прямо внутри главного окна /mc
--      (addon.radarSettingsPanel) — без отдельных всплывающих окон!
--   2. Интеграция со стандартным меню Blizzard (ESC -> Параметры -> Модификации)
--   3. Мгновенная горячая смена языка (Авто / ruRU / enUS) без /reload
-- ============================================================================

local L = addon.L
local LibStub = _G.LibStub
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local function CreateStyledButton(parent, width, height, text, isGoldAccent)
    if addon.CreateFlatButton then
        return addon.CreateFlatButton(parent, width, height, text, isGoldAccent)
    end
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, height)
    btn:SetText(text or "")
    return btn
end

function addon:BuildSettingsControls(parent, isEmbeddedInRadar)
    local controls = {}

    -- Верхний блок заголовка и выбора языка
    local headerCard = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    headerCard:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -10)
    headerCard:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -10)
    headerCard:SetHeight(82)
    if addon.ApplyFlatBackdrop then
        addon.ApplyFlatBackdrop(headerCard, 0.07, 0.07, 0.09, 0.96, 0.22, 0.22, 0.25, 1.0)
    end

    local title = headerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", headerCard, "TOPLEFT", 12, -10)
    controls.title = title

    local subtitle = headerCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("RIGHT", headerCard, "RIGHT", -12, 0)
    subtitle:SetJustifyH("LEFT")
    controls.subtitle = subtitle

    local langLabel = headerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    langLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
    langLabel:SetTextColor(1.0, 0.82, 0.0, 1.0)
    controls.langLabel = langLabel

    local langButtons = {}
    local langModes = {
        { key = "auto", labelKey = "CFG_LANG_AUTO", width = 145 },
        { key = "ruRU", labelKey = "CFG_LANG_RU", width = 125 },
        { key = "enUS", labelKey = "CFG_LANG_EN", width = 125 },
    }

    for i, mode in ipairs(langModes) do
        local btn = CreateStyledButton(headerCard, mode.width, 22, "", false)
        if i == 1 then
            btn:SetPoint("LEFT", langLabel, "RIGHT", 10, 0)
        else
            btn:SetPoint("LEFT", langButtons[i - 1], "RIGHT", 6, 0)
        end
        btn.modeKey = mode.key
        btn.labelKey = mode.labelKey
        btn:SetScript("OnClick", function()
            if addon.db and addon.db.settings then
                addon.db.settings.language = mode.key
                addon:RefreshAllLocalizedUI()
            end
        end)
        langButtons[i] = btn
    end
    controls.langButtons = langButtons

    -- Секция 1: Коллекция маунтов и Тултипы
    local secTooltips = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secTooltips:SetPoint("TOPLEFT", headerCard, "BOTTOMLEFT", 4, -10)
    controls.secTooltips = secTooltips

    local checkboxes = {}
    local function CreateOptionCheckbox(settingKey, labelKey, anchorTo, offsetY, onToggle)
        local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY or 2)
        cb.settingKey = settingKey
        cb.labelKey = labelKey
        cb:SetScript("OnClick", function(self)
            if not addon.db or not addon.db.settings then return end
            local val = self:GetChecked() and true or false
            if onToggle then
                onToggle(val)
            else
                addon.db.settings[settingKey] = val
            end
            if MountJournal and MountJournal:IsShown() and MountJournal_UpdateMountDisplay then
                MountJournal_UpdateMountDisplay()
            end
            if addon.RefreshWorldMapPins then
                addon:RefreshWorldMapPins()
            end
        end)
        table.insert(checkboxes, cb)
        return cb
    end

    local cb1 = CreateOptionCheckbox("showInTooltips", "CFG_SHOW_TOOLTIPS", secTooltips, -2)
    local cb2 = CreateOptionCheckbox("showInJournalRowHover", "CFG_SHOW_ROW_HOVER", cb1, 2)
    local cb3 = CreateOptionCheckbox("showInMountDisplay", "CFG_SHOW_MOUNT_DISPLAY", cb2, 2)
    local cb4 = CreateOptionCheckbox("showGlobalRarity", "CFG_SHOW_GLOBAL_RARITY", cb3, 2)
    local cb5 = CreateOptionCheckbox("showServerRarity", "CFG_SHOW_SERVER_RARITY", cb4, 2)
    local cb6 = CreateOptionCheckbox("showAttempts", "CFG_SHOW_ATTEMPTS", cb5, 2)

    -- Секция 2: Радар рарников, Карта мира и Миникарта
    local secRadar = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secRadar:SetPoint("TOPLEFT", cb6, "BOTTOMLEFT", 0, -6)
    controls.secRadar = secRadar

    local cb7 = CreateOptionCheckbox("alertRares", "CFG_ALERT_RARES", secRadar, -2)
    local cb8 = CreateOptionCheckbox("alertSound", "CFG_ALERT_SOUND", cb7, 2)
    local cb9 = CreateOptionCheckbox("autoWaypoint", "CFG_AUTO_WAYPOINT", cb8, 2)
    local cb10 = CreateOptionCheckbox("showWorldMapPins", "CFG_WORLD_MAP_PINS", cb9, 2)
    local cb11 = CreateOptionCheckbox("showNpcTooltip", "CFG_SHOW_NPC_TT", cb10, 2)
    local cb12 = CreateOptionCheckbox("announceAttempts", "CFG_ANNOUNCE_ATTEMPTS", cb11, 2)
    local cb13 = CreateOptionCheckbox("_minimap", "CFG_SHOW_MINIMAP", cb12, 2, function(checked)
        if not addon.db or not addon.db.minimap then return end
        addon.db.minimap.hide = not checked
        if not LDBIcon and LibStub then
            LDBIcon = LibStub("LibDBIcon-1.0", true)
        end
        if LDBIcon then
            if checked then
                LDBIcon:Show("MountCollector")
            else
                LDBIcon:Hide("MountCollector")
            end
        end
    end)

    controls.checkboxes = checkboxes

    -- Нижние кнопки действий
    local btnOpenRadar = CreateStyledButton(parent, 195, 24, "", false)
    btnOpenRadar:SetPoint("TOPLEFT", cb13, "BOTTOMLEFT", 4, -6)
    btnOpenRadar:SetScript("OnClick", function()
        if isEmbeddedInRadar then
            -- Если мы уже внутри окна /mc на вкладке Настройки — возвращаемся к списку цепочек
            if addon.ToggleConfigFrame then
                addon:ToggleConfigFrame()
            end
        elseif addon.ToggleRadarWindow then
            addon:ToggleRadarWindow()
        end
    end)
    controls.btnOpenRadar = btnOpenRadar

    local btnTestAlert = CreateStyledButton(parent, 205, 24, "", true)
    btnTestAlert:SetPoint("LEFT", btnOpenRadar, "RIGHT", 10, 0)
    btnTestAlert:SetScript("OnClick", function()
        local testMountID = addon.MountBySpell[72286] or 363
        addon.RecentAlertLock["99999:" .. tostring(testMountID)] = nil
        addon:TriggerRareMountAlert(testMountID, 99999, L.ALERT_TEST_NPC, true)
    end)
    controls.btnTestAlert = btnTestAlert

    function controls:Refresh()
        title:SetText(L.CFG_TITLE)
        subtitle:SetText(L.CFG_SUBTITLE)
        langLabel:SetText(L.CFG_LANG_LABEL)
        secTooltips:SetText("|cffffd100" .. L.CFG_SEC_TOOLTIPS .. "|r")
        secRadar:SetText("|cffffd100" .. L.CFG_SEC_RADAR .. "|r")
        btnOpenRadar:SetText(isEmbeddedInRadar and L.QUEST_BACK_BTN or L.CFG_BTN_OPEN_RADAR)
        btnTestAlert:SetText(L.CFG_BTN_TEST_ALERT)

        local curLang = (addon.db and addon.db.settings and addon.db.settings.language) or "auto"
        for _, btn in ipairs(langButtons) do
            local txt = L[btn.labelKey]
            local isActive = (btn.modeKey == curLang)
            if btn.SetActiveTab then
                btn:SetText(txt)
                btn:SetActiveTab(isActive)
            else
                btn:SetText(isActive and ("|cff00ff96• " .. txt .. "|r") or txt)
            end
        end

        for _, cb in ipairs(checkboxes) do
            if cb.Text then
                cb.Text:SetText(L[cb.labelKey])
            end
            if addon.db then
                if cb.settingKey == "_minimap" then
                    cb:SetChecked(not (addon.db.minimap and addon.db.minimap.hide))
                elseif addon.db.settings then
                    cb:SetChecked(addon.db.settings[cb.settingKey] ~= false)
                end
            end
        end
    end

    parent:SetScript("OnShow", function()
        controls:Refresh()
    end)

    parent.controls = controls
    return controls
end

-- 1. Встраиваем настройки во вкладку «Настройки» внутри главного окна /mc
local radarControls = nil
if addon.radarSettingsPanel then
    radarControls = addon:BuildSettingsControls(addon.radarSettingsPanel, true)
end

-- 2. Регистрируем панель в стандартных настройках Blizzard (ESC -> Параметры -> Модификации)
local blizzPanel = CreateFrame("Frame", "MountCollectorOptionsPanel", UIParent)
blizzPanel.name = "MountCollector"
local blizzControls = addon:BuildSettingsControls(blizzPanel, false)

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(blizzPanel, "MountCollector")
    Settings.RegisterAddOnCategory(category)
    addon.settingsCategoryID = category:GetID()
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(blizzPanel)
end

function addon:RefreshAllLocalizedUI()
    if blizzControls then
        blizzControls:Refresh()
    end
    if radarControls then
        radarControls:Refresh()
    end
    if self.UpdateLDBText then
        self:UpdateLDBText()
    end
    if self.RefreshRadarUI then
        self:RefreshRadarUI()
    end
    if self.RefreshMountJournalSideColumn then
        self:RefreshMountJournalSideColumn()
    end
    if self.RefreshWorldMapPins then
        self:RefreshWorldMapPins()
    end
    if MountJournal and MountJournal:IsShown() and MountJournal_UpdateMountDisplay then
        MountJournal_UpdateMountDisplay()
    end
end
