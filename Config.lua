local _, addon = ...

local L = addon.L
local LibStub = _G.LibStub
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local function BuildSettingsControls(parent)
    local controls = {}

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
    controls.title = title

    local subtitle = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    controls.subtitle = subtitle

    local langLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    langLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
    controls.langLabel = langLabel

    local langButtons = {}
    local langModes = {
        { key = "auto", labelKey = "CFG_LANG_AUTO", width = 140 },
        { key = "ruRU", labelKey = "CFG_LANG_RU", width = 120 },
        { key = "enUS", labelKey = "CFG_LANG_EN", width = 120 },
    }

    for i, mode in ipairs(langModes) do
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetSize(mode.width, 22)
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

    local secTooltips = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secTooltips:SetPoint("TOPLEFT", langLabel, "BOTTOMLEFT", 0, -14)
    controls.secTooltips = secTooltips

    local checkboxes = {}
    local function CreateOptionCheckbox(settingKey, labelKey, anchorTo, offsetY, onToggle)
        local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY or -2)
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

    local cb1 = CreateOptionCheckbox("showInTooltips", "CFG_SHOW_TOOLTIPS", secTooltips, -4)
    local cb2 = CreateOptionCheckbox("showInJournalRowHover", "CFG_SHOW_ROW_HOVER", cb1, 0)
    local cb3 = CreateOptionCheckbox("showInMountDisplay", "CFG_SHOW_MOUNT_DISPLAY", cb2, 0)
    local cb4 = CreateOptionCheckbox("showGlobalRarity", "CFG_SHOW_GLOBAL_RARITY", cb3, 0)
    local cb5 = CreateOptionCheckbox("showServerRarity", "CFG_SHOW_SERVER_RARITY", cb4, 0)
    local cb6 = CreateOptionCheckbox("showAttempts", "CFG_SHOW_ATTEMPTS", cb5, 0)

    local secRadar = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secRadar:SetPoint("TOPLEFT", cb6, "BOTTOMLEFT", 0, -10)
    controls.secRadar = secRadar

    local cb7 = CreateOptionCheckbox("alertRares", "CFG_ALERT_RARES", secRadar, -4)
    local cb8 = CreateOptionCheckbox("alertSound", "CFG_ALERT_SOUND", cb7, 0)
    local cb9 = CreateOptionCheckbox("autoWaypoint", "CFG_AUTO_WAYPOINT", cb8, 0)
    local cb10 = CreateOptionCheckbox("showWorldMapPins", "CFG_WORLD_MAP_PINS", cb9, 0)
    local cb11 = CreateOptionCheckbox("showNpcTooltip", "CFG_SHOW_NPC_TT", cb10, 0)
    local cb12 = CreateOptionCheckbox("announceAttempts", "CFG_ANNOUNCE_ATTEMPTS", cb11, 0)
    local cb13 = CreateOptionCheckbox("_minimap", "CFG_SHOW_MINIMAP", cb12, 0, function(checked)
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

    local btnOpenRadar = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btnOpenRadar:SetSize(180, 26)
    btnOpenRadar:SetPoint("TOPLEFT", cb13, "BOTTOMLEFT", 4, -10)
    btnOpenRadar:SetScript("OnClick", function()
        if addon.ToggleRadarWindow then
            addon:ToggleRadarWindow()
        end
    end)
    controls.btnOpenRadar = btnOpenRadar

    local btnTestAlert = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btnTestAlert:SetSize(190, 26)
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
        btnOpenRadar:SetText(L.CFG_BTN_OPEN_RADAR)
        btnTestAlert:SetText(L.CFG_BTN_TEST_ALERT)

        local curLang = (addon.db and addon.db.settings and addon.db.settings.language) or "auto"
        for _, btn in ipairs(langButtons) do
            local txt = L[btn.labelKey]
            if btn.modeKey == curLang then
                btn:SetText("|cff00ff96• " .. txt .. "|r")
            else
                btn:SetText(txt)
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

    return controls
end

local blizzPanel = CreateFrame("Frame", "MountCollectorOptionsPanel", UIParent)
blizzPanel.name = "MountCollector"
local blizzControls = BuildSettingsControls(blizzPanel)

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(blizzPanel, "MountCollector")
    Settings.RegisterAddOnCategory(category)
    addon.settingsCategoryID = category:GetID()
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(blizzPanel)
end

local standaloneCfg = CreateFrame("Frame", "MountCollectorConfigWindow", UIParent, "BackdropTemplate")
standaloneCfg:SetSize(620, 500)
standaloneCfg:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
standaloneCfg:SetFrameStrata("DIALOG")
standaloneCfg:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
standaloneCfg:SetBackdropColor(0.05, 0.06, 0.09, 0.96)
standaloneCfg:SetBackdropBorderColor(0.0, 0.8, 1.0, 0.9)
standaloneCfg:EnableMouse(true)
standaloneCfg:SetMovable(true)
standaloneCfg:RegisterForDrag("LeftButton")
standaloneCfg:SetScript("OnDragStart", standaloneCfg.StartMoving)
standaloneCfg:SetScript("OnDragStop", standaloneCfg.StopMovingOrSizing)
standaloneCfg:Hide()

local closeBtn = CreateFrame("Button", nil, standaloneCfg, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", standaloneCfg, "TOPRIGHT", -4, -4)

local standaloneControls = BuildSettingsControls(standaloneCfg)

function addon:ToggleConfigFrame()
    if standaloneCfg:IsShown() then
        standaloneCfg:Hide()
    else
        standaloneCfg:Show()
        standaloneControls:Refresh()
    end
end

function addon:RefreshAllLocalizedUI()
    blizzControls:Refresh()
    standaloneControls:Refresh()
    if self.UpdateLDBText then
        self:UpdateLDBText()
    end
    if self.RefreshRadarUI then
        self:RefreshRadarUI()
    end
    if self.RefreshWorldMapPins then
        self:RefreshWorldMapPins()
    end
    if MountJournal and MountJournal:IsShown() and MountJournal_UpdateMountDisplay then
        MountJournal_UpdateMountDisplay()
    end
end
