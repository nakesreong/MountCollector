local _, addon = ...

-- ============================================================================
-- MountCollector — Locales.lua
-- Система локализации (ruRU / enUS) с динамическим переключением в реальном
-- времени без перезагрузки интерфейса (/rl).
--
-- Важно: в кириллическом шрифте WoW (FRIZQT___CYR.TTF) отсутствуют глифы
-- Unicode ✓ и ▶, поэтому для чек-листов шагов используются встроенные
-- текстурные иконки клиента (|TInterface\...:14:14:0:0|t).
-- ============================================================================

local Locales = {
    ruRU = {
        -- Тултипы и категории редкости
        TIER_UNKNOWN = "Неизвестно",
        NO_DATA = "|cff999999Нет данных|r",
        TIER_MYTHIC = "|cffff8000Мифическая (<1%)|r",
        TIER_ULTRA = "|cffff5500Ультра-редкий (<3%)|r",
        TIER_EPIC = "|cffa335eeЭпическая (<10%)|r",
        TIER_RARE = "|cff0070ddРедкая (<25%)|r",
        TIER_UNCOMMON = "|cff1eff00Необычная|r",
        TIER_COMMON = "|cffffffffОбычная|r",

        STATUS_COLLECTED = "|cff00ff96В коллекции|r",
        STATUS_NOT_COLLECTED = "|cffff5555Ещё не собран|r",
        TAG_COLLECTED = "|cff00ff96[Собран]|r",
        TAG_NOT_COLLECTED = "|cffff5555[Нет в коллекции]|r",
        TAG_LOCKED_SHORT = " |cffff5555[КД]|r",
        TAG_LOCKED_TODAY = " |cffff5555[КД сегодня]|r",

        TT_GLOBAL_RARITY = "|cffddddddРарность по миру (Armory):|r",
        TT_SERVER_RARITY = "|cffddddddНа сервере «%s»:|r",
        TT_SERVER_OWNERS = "|cffffd100~%d игр.|r из ~%d%s",
        TT_SERVER_SEEN_INLINE = " |cff00ff96(встречено: %d)|r",
        TT_SERVER_SEEN_ONLY = "|cff00ff96Встречено вживую: %d игр.|r",
        TT_DROP_CHANCE = "|cffddddddШанс выпадения:|r",
        TT_DROP_CHANCE_VAL = "|cffffffff1 из %d|r (|cff00ccff%.2f%%|r)",
        TT_ACCOUNT_ATTEMPTS = "|cffddddddТраев на аккаунте:|r",
        TT_LUCK_INLINE = " |cffaaaaaa(шанс выбить: %.1f%%)|r",
        TT_BY_CHARACTERS = "|cff999999  По персонажам:|r",
        TT_STATUS_TODAY = "|cffddddddСтатус сегодня:|r",
        TT_LOCKED_TODAY = "|cffff5555Уже убит этим персонажем (КД)|r",
        TT_SPAWN_COORDS = "|cffddddddКоординаты спавна:|r",
        TT_NPC_DROPS_HEADER = "|cff00ccff[MountCollector]|r Дроп маунтов / предметов для маунтов:",
        TT_NPC_ATTEMPTS_FMT = "|cffffd100Траев: %d|r (%s%s)",
        TT_WORLD_PCT_SHORT = "%.1f%% мира",
        TT_RARE_SHORT = "редкий",
        TT_ITEM_FOR_MOUNT = "|cff00ccff[MountCollector]|r Предмет для получения маунта:",

        -- Правая 3D панель в MountJournal
        MD_RARITY_LABEL = "|cff00ccffРарность:|r",
        MD_SERVER_PART = " | На «%s»: |cffffd100~%d игр.|r",
        MD_SEEN_PART = " |cff00ff96(вживую: %d)|r",
        MD_ATTEMPTS_LABEL = "|cff00ccffТраев на аккаунте:|r |cffffd100%d|r%s",
        MD_CHANCE_PART = " (Шанс: 1/%d)",

        -- Чат, точки на карте и алерты
        CHAT_ATTEMPT_RECORDED = "|cff00ccff[MountCollector]|r Засчитан трай |cffffd100#%d|r на |cffa335ee[%s]|r (%s) — Шанс: 1/%d (Вероятность уже выбить за %d траев: |cff00ff96%.1f%%|r)",
        CHAT_WAYPOINT_SET = "|cff00ccff[MountCollector]|r Поставлена метка на карте: |cffffd100%s|r (|cff00ccff%.1f, %.1f|r) -> |cffa335ee[%s]|r",
        ALERT_HEADER_NEARBY = "|cff00ccff[MountCollector]|r Рядом рарник/босс: |cffffd100%s|r",
        ALERT_NOT_COLLECTED = "|cffa335ee[%s]|r |cffff5555(Не собран)|r",
        ALERT_STATS_LINE = "|cffddddddТраев: |cffffd100%d|r | %sМир: %s | |cff00ff96[ЛКМ: Метка + Коллекция]|r",
        ALERT_TEST_NPC = "Король-лич (Тест радара)",

        -- Окно радара, Пины на карте мира и LDB
        RADAR_WINDOW_TITLE = "|cff00ccffMount|r|cffffaa00Collector|r — Радар маунтов, траев и цепочек",
        TAB_CURRENT_ZONE = "В текущей зоне",
        TAB_ALL_ATTEMPTS = "Все траи аккаунта",
        TAB_QUEST_CHAINS = "Цепочки и Квесты",
        BTN_SETTINGS = "Настройки",
        BTN_PIN_ALL_ZONE = "Отметить всех на карте",
        SUBHEADER_ZONE = "Локация: |cffffd100%s|r — Несобранных маунтов/рарников: |cff00ccff%d|r (ЛКМ: Коллекция | ПКМ: Точка на карте)",
        SUBHEADER_ALL = "Несобранные маунты с активными траями на аккаунте: |cff00ccff%d|r (ЛКМ: Коллекция | ПКМ: Точка на карте)",
        SUBHEADER_QUESTS = "Квестовые цепочки, инкубация яиц и многодневные маунты: |cff00ccff%d|r (ЛКМ: Открыть шаги | ПКМ: Вести в TomTom)",
        QUEST_BACK_BTN = "< К списку цепочек",
        QUEST_NAV_BTN = "Маршрут: Текущий шаг (TomTom)",
        QUEST_START_BTN = "Маршрут: К старту цепочки",
        QUEST_WOWHEAD_BTN = "Ссылка на Wowhead (Ctrl+C)",
        QUEST_JOURNAL_BTN = "Открыть 3D в Коллекции",
        QUEST_OPEN_MC_BTN = "Все цепочки маунтов (/mc)",
        QUEST_STEP_DONE = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14:0:0|t |cff00ff96СДЕЛАНО|r",
        QUEST_STEP_ACTIVE = "|TInterface\\COMMON\\Indicator-Yellow:14:14:0:0|t |cffffd100НАДО СДЕЛАТЬ (ТЕКУЩИЙ ШАГ)|r",
        QUEST_STEP_IN_LOG = " |cff00ccff[В журнале заданий]|r",
        QUEST_STEP_SUBPROGRESS = " |cff00ff96[Квестов главы: %d/%d]|r",
        QUEST_STEP_LOCKED = "|TInterface\\COMMON\\Indicator-Gray:14:14:0:0|t |cff888888НАДО СДЕЛАТЬ|r",
        QUEST_CHAIN_PROGRESS_FMT = "|cffffd100Шаг %d/%d|r",
        QUEST_CHAIN_STATUS_IN_PROGRESS = "|cff00ff96В процессе: %d/%d|r",
        QUEST_CHAIN_STATUS_AVAILABLE = "|cffffd100Доступно: 0/%d|r",
        QUEST_CHAIN_RIGHT_OPEN = "|cff00ccffОткрыть маршрут ->|r",
        QUEST_STEP_CLICK_HINT = "|cff00ff96ЛКМ: Проложить маршрут TomTom к этому шагу | ПКМ: Ссылка Wowhead на квест|r",
        CHAT_QUEST_NAV_SET = "|cff00ccff[MountCollector]|r Навигатор цепочки |cffa335ee[%s]|r -> |cffffd100%s|r (%s |cff00ccff%.1f, %.1f|r — %s)",
        CHAT_QUEST_STEP_ADVANCED = "|cff00ccff[MountCollector]|r Шаг цепочки на |cffa335ee[%s]|r выполнен! Обновляю маршрут TomTom -> |cffffd100%s|r",
        TT_QUEST_CHAIN_LABEL = "|cffddddddЦепочка получения:|r",
        MD_BTN_QUEST_GUIDE = "Маршрут цепочки (TomTom)",
        MD_CHAIN_LINE = "|cff00ccffЦепочка:|r |cff00ff96%d/%d|r — |cffffd100%s|r",
        SEARCH_PLACEHOLDER = "Поиск маунта...",
        TOTAL_LABEL = "Всего: |cffffffff%d|r",
        SECTION_CHECKLIST = "ПОШАГОВЫЙ ПЛАН (СДЕЛАНО / НАДО СДЕЛАТЬ):",
        WOWHEAD_POPUP_TITLE = "Скопируйте ссылку на Wowhead (Ctrl+C):",
        DOCK_TOGGLE_BTN = "Цепочка / Навигатор",
        DOCK_WINDOW_TITLE = "|cff00ccffMount|r|cffffaa00Collector|r — Цепочка и Навигатор",
        META_CHAIN_TYPE_ZONE = "|cffffd100Тип:|r |cffffffff%s|r   |cffffd100Зона:|r |cffffffff%s|r",
        META_CHAIN_PROGRESS = "|cffffd100Прогресс цепочки:|r |cff00ff96Выполнено %d из %d этапов|r",
        META_DROP_SOURCE_ZONE = "|cffffd100Источник:|r |cffffffff%s|r   |cffffd100Зона:|r |cffffffff%s|r",
        META_DROP_ATTEMPTS = "|cffffd100Траев на аккаунте:|r |cffffffff%d|r%s",
        STEP_NPC_PREFIX = "|cffffd100NPC / Объект:|r |cffffffff",
        STEP_TARGET_PREFIX = "|cffffd100Цель:|r |cffffffff",
        STEP_DROP_TITLE_PREFIX = "Добыча: ",
        ROW_BOSS_PREFIX = "NPC: ",
        ROW_WORLD_PREFIX = "Мир: ",
        ROW_ATTEMPTS_FMT = "|cffffd100Траев: %d|r",
        ROW_CHANCE_FMT = "|cff00ccffШанс: 1/%d|r",
        ROW_DROP_MOUNT_FMT = "|cff00ccffДроп/Квест|r",

        MAP_PIN_HINT = "|cff00ff96ЛКМ: Поставить 3D-стрелку (Waypoint) | ПКМ: Открыть в Коллекции|r",

        LDB_TEXT_ZONE = "|cff00ccffМаунты:|r |cffffd100%d в зоне|r",
        LDB_TEXT_CLEAN = "|cff00ccffМаунты:|r |cff888888чисто|r",
        LDB_TT_TITLE = "|cff00ccffMount|r|cffffaa00Collector|r — Радар маунтов и рарности",
        LDB_TT_HINT = "|cffaaaaaaЛКМ: Радар зоны и траев | ПКМ: Коллекция | СКМ: Настройки|r",
        LDB_TT_ZONE_HEADER = "|cffffd100Несобранные дроп-маунты (%s):|r",
        LDB_TT_ZONE_EMPTY = "|cff888888  В этой зоне нет несобранных дроп-маунтов (или все уже в коллекции!)|r",
        LDB_TT_ROW_RIGHT = "|cffffd100Траев: %d|r (%sМир: %s)",

        -- Меню настроек
        CFG_TITLE = "|cff00ccffMount|r|cffffaa00Collector|r — Настройки",
        CFG_SUBTITLE = "Трекинг рарности маунтов (Data for Azeroth / Armory + Сервер), траев по аккаунту, меток на карте и рарников.",
        CFG_LANG_LABEL = "Язык интерфейса (Language):",
        CFG_LANG_AUTO = "Авто (по клиенту)",
        CFG_LANG_RU = "Русский (ruRU)",
        CFG_LANG_EN = "English (enUS)",

        CFG_SEC_TOOLTIPS = "Коллекция маунтов и Тултипы",
        CFG_SHOW_TOOLTIPS = "Показывать блок MountCollector в тултипах маунтов и предметов для маунтов",
        CFG_SHOW_ROW_HOVER = "Открывать тултип при наведении на саму строчку маунта в списке Коллекции",
        CFG_SHOW_MOUNT_DISPLAY = "Показывать сводку рарности и траев на 3D-превью маунта справа",
        CFG_SHOW_GLOBAL_RARITY = "Показывать глобальную рарность по миру (Data for Azeroth / Armory)",
        CFG_SHOW_SERVER_RARITY = "Показывать оценку владельцев на сервере и живые встречи",
        CFG_SHOW_ATTEMPTS = "Показывать количество траев на аккаунте и разбивку по персонажам",

        CFG_SEC_RADAR = "Радар рарников, Карта мира и Миникарта",
        CFG_ALERT_RARES = "Вопить и показывать баннер при обнаружении рарника/босса с маунтом или предметом для маунта",
        CFG_ALERT_SOUND = "Проигрывать звуковой сигнал тревоги при обнаружении рарника",
        CFG_AUTO_WAYPOINT = "Автоматически ставить 3D-стрелку и точку на карте (Blizzard + TomTom) при обнаружении рарника",
        CFG_WORLD_MAP_PINS = "Отмечать иконками на Карте Мира (M) всех рарников/боссов зоны, с которых ещё не выбит маунт",
        CFG_SHOW_NPC_TT = "Показывать дроп маунтов и траи в тултипе боссов/NPC при наведении",
        CFG_ANNOUNCE_ATTEMPTS = "Выводить сообщение в чат при засчитывании нового трая",
        CFG_SHOW_MINIMAP = "Показывать иконку MountCollector у миникарты",

        CFG_BTN_OPEN_RADAR = "Открыть Радар (/mc)",
        CFG_BTN_TEST_ALERT = "Тест баннера рарника",
    },

    enUS = {
        -- Tooltips & Rarity Tiers
        TIER_UNKNOWN = "Unknown",
        NO_DATA = "|cff999999No data|r",
        TIER_MYTHIC = "|cffff8000Mythic (<1%)|r",
        TIER_ULTRA = "|cffff5500Ultra Rare (<3%)|r",
        TIER_EPIC = "|cffa335eeEpic (<10%)|r",
        TIER_RARE = "|cff0070ddRare (<25%)|r",
        TIER_UNCOMMON = "|cff1eff00Uncommon|r",
        TIER_COMMON = "|cffffffffCommon|r",

        STATUS_COLLECTED = "|cff00ff96Collected|r",
        STATUS_NOT_COLLECTED = "|cffff5555Not Collected|r",
        TAG_COLLECTED = "|cff00ff96[Collected]|r",
        TAG_NOT_COLLECTED = "|cffff5555[Missing]|r",
        TAG_LOCKED_SHORT = " |cffff5555[Locked]|r",
        TAG_LOCKED_TODAY = " |cffff5555[Locked Today]|r",

        TT_GLOBAL_RARITY = "|cffddddddWorld Rarity (Armory):|r",
        TT_SERVER_RARITY = "|cffddddddOn Realm '%s':|r",
        TT_SERVER_OWNERS = "|cffffd100~%d players|r of ~%d%s",
        TT_SERVER_SEEN_INLINE = " |cff00ff96(seen: %d)|r",
        TT_SERVER_SEEN_ONLY = "|cff00ff96Seen live on realm: %d|r",
        TT_DROP_CHANCE = "|cffddddddDrop Chance:|r",
        TT_DROP_CHANCE_VAL = "|cffffffff1 in %d|r (|cff00ccff%.2f%%|r)",
        TT_ACCOUNT_ATTEMPTS = "|cffddddddAccount Attempts:|r",
        TT_LUCK_INLINE = " |cffaaaaaa(cumulative odds: %.1f%%)|r",
        TT_BY_CHARACTERS = "|cff999999  By Character:|r",
        TT_STATUS_TODAY = "|cffddddddStatus Today:|r",
        TT_LOCKED_TODAY = "|cffff5555Already killed on this character (Locked)|r",
        TT_SPAWN_COORDS = "|cffddddddSpawn Coordinates:|r",
        TT_NPC_DROPS_HEADER = "|cff00ccff[MountCollector]|r Mount / Mount Item Drops:",
        TT_NPC_ATTEMPTS_FMT = "|cffffd100Attempts: %d|r (%s%s)",
        TT_WORLD_PCT_SHORT = "%.1f%% world",
        TT_RARE_SHORT = "rare",
        TT_ITEM_FOR_MOUNT = "|cff00ccff[MountCollector]|r Item required for mount:",

        -- MountJournal 3D Display Pane
        MD_RARITY_LABEL = "|cff00ccffRarity:|r",
        MD_SERVER_PART = " | On '%s': |cffffd100~%d players|r",
        MD_SEEN_PART = " |cff00ff96(seen: %d)|r",
        MD_ATTEMPTS_LABEL = "|cff00ccffAccount Attempts:|r |cffffd100%d|r%s",
        MD_CHANCE_PART = " (Chance: 1/%d)",

        -- Chat, Waypoints & Alerts
        CHAT_ATTEMPT_RECORDED = "|cff00ccff[MountCollector]|r Recorded attempt |cffffd100#%d|r for |cffa335ee[%s]|r (%s) — Chance: 1/%d (Cumulative luck after %d tries: |cff00ff96%.1f%%|r)",
        CHAT_WAYPOINT_SET = "|cff00ccff[MountCollector]|r Map waypoint set: |cffffd100%s|r (|cff00ccff%.1f, %.1f|r) -> |cffa335ee[%s]|r",
        ALERT_HEADER_NEARBY = "|cff00ccff[MountCollector]|r Nearby Rare/Boss: |cffffd100%s|r",
        ALERT_NOT_COLLECTED = "|cffa335ee[%s]|r |cffff5555(Missing)|r",
        ALERT_STATS_LINE = "|cffddddddTries: |cffffd100%d|r | %sWorld: %s | |cff00ff96[Click: Pin + Journal]|r",
        ALERT_TEST_NPC = "The Lich King (Radar Test)",

        -- Radar Window, World Map Pins & LDB
        RADAR_WINDOW_TITLE = "|cff00ccffMount|r|cffffaa00Collector|r — Mount, Attempt & Quest Chain Radar",
        TAB_CURRENT_ZONE = "In Current Zone",
        TAB_ALL_ATTEMPTS = "All Account Attempts",
        TAB_QUEST_CHAINS = "Quest Chains",
        BTN_SETTINGS = "Settings",
        BTN_PIN_ALL_ZONE = "Pin All on Map",
        SUBHEADER_ZONE = "Zone: |cffffd100%s|r — Missing Mounts/Rares: |cff00ccff%d|r (L-Click: Journal | R-Click: Map Pin)",
        SUBHEADER_ALL = "Uncollected mounts with recorded account attempts: |cff00ccff%d|r (L-Click: Journal | R-Click: Map Pin)",
        SUBHEADER_QUESTS = "Questline, Egg Incubation & Multi-Day Mounts: |cff00ccff%d|r (L-Click: Open Steps | R-Click: TomTom Guide)",
        QUEST_BACK_BTN = "< Back to Chains",
        QUEST_NAV_BTN = "Route: Current Step (TomTom)",
        QUEST_START_BTN = "Route: Chain Start",
        QUEST_WOWHEAD_BTN = "Copy Wowhead Link (Ctrl+C)",
        QUEST_JOURNAL_BTN = "Open 3D in Mount Journal",
        QUEST_OPEN_MC_BTN = "All Mount Chains (/mc)",
        QUEST_STEP_DONE = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14:0:0|t |cff00ff96DONE|r",
        QUEST_STEP_ACTIVE = "|TInterface\\COMMON\\Indicator-Yellow:14:14:0:0|t |cffffd100TO DO (CURRENT STEP)|r",
        QUEST_STEP_IN_LOG = " |cff00ccff[In Quest Log]|r",
        QUEST_STEP_SUBPROGRESS = " |cff00ff96[Chapter Quests: %d/%d]|r",
        QUEST_STEP_LOCKED = "|TInterface\\COMMON\\Indicator-Gray:14:14:0:0|t |cff888888TO DO|r",
        QUEST_CHAIN_PROGRESS_FMT = "|cffffd100Step %d/%d|r",
        QUEST_CHAIN_STATUS_IN_PROGRESS = "|cff00ff96In Progress: %d/%d|r",
        QUEST_CHAIN_STATUS_AVAILABLE = "|cffffd100Available: 0/%d|r",
        QUEST_CHAIN_RIGHT_OPEN = "|cff00ccffOpen Route ->|r",
        QUEST_STEP_CLICK_HINT = "|cff00ff96L-Click: Set TomTom Route to Step | R-Click: Copy Wowhead Quest Link|r",
        CHAT_QUEST_NAV_SET = "|cff00ccff[MountCollector]|r Chain Navigator for |cffa335ee[%s]|r -> |cffffd100%s|r (%s |cff00ccff%.1f, %.1f|r — %s)",
        CHAT_QUEST_STEP_ADVANCED = "|cff00ccff[MountCollector]|r Quest step for |cffa335ee[%s]|r completed! Advancing TomTom waypoint -> |cffffd100%s|r",
        TT_QUEST_CHAIN_LABEL = "|cffddddddQuest Chain:|r",
        MD_BTN_QUEST_GUIDE = "Quest Chain Guide (TomTom)",
        MD_CHAIN_LINE = "|cff00ccffChain:|r |cff00ff96%d/%d|r — |cffffd100%s|r",
        SEARCH_PLACEHOLDER = "Search mount...",
        TOTAL_LABEL = "Total: |cffffffff%d|r",
        SECTION_CHECKLIST = "STEP-BY-STEP PLAN (DONE / TO DO):",
        WOWHEAD_POPUP_TITLE = "Copy Wowhead Link (Ctrl+C):",
        DOCK_TOGGLE_BTN = "Chain / Navigator",
        DOCK_WINDOW_TITLE = "|cff00ccffMount|r|cffffaa00Collector|r — Chain & Navigator",
        META_CHAIN_TYPE_ZONE = "|cffffd100Type:|r |cffffffff%s|r   |cffffd100Zone:|r |cffffffff%s|r",
        META_CHAIN_PROGRESS = "|cffffd100Chain Progress:|r |cff00ff96Completed %d of %d steps|r",
        META_DROP_SOURCE_ZONE = "|cffffd100Source:|r |cffffffff%s|r   |cffffd100Zone:|r |cffffffff%s|r",
        META_DROP_ATTEMPTS = "|cffffd100Account Attempts:|r |cffffffff%d|r%s",
        STEP_NPC_PREFIX = "|cffffd100NPC / Object:|r |cffffffff",
        STEP_TARGET_PREFIX = "|cffffd100Target:|r |cffffffff",
        STEP_DROP_TITLE_PREFIX = "Drop: ",
        ROW_BOSS_PREFIX = "NPC: ",
        ROW_WORLD_PREFIX = "World: ",
        ROW_ATTEMPTS_FMT = "|cffffd100Tries: %d|r",
        ROW_CHANCE_FMT = "|cff00ccffOdds: 1/%d|r",
        ROW_DROP_MOUNT_FMT = "|cff00ccffDrop/Quest|r",

        MAP_PIN_HINT = "|cff00ff96Left-Click: Set 3D Waypoint | Right-Click: Open in Mount Journal|r",

        LDB_TEXT_ZONE = "|cff00ccffMounts:|r |cffffd100%d in zone|r",
        LDB_TEXT_CLEAN = "|cff00ccffMounts:|r |cff888888clear|r",
        LDB_TT_TITLE = "|cff00ccffMount|r|cffffaa00Collector|r — Mount & Rarity Radar",
        LDB_TT_HINT = "|cffaaaaaaLeft-Click: Zone Radar | Right-Click: Mount Journal | Middle-Click: Settings|r",
        LDB_TT_ZONE_HEADER = "|cffffd100Uncollected Drop Mounts (%s):|r",
        LDB_TT_ZONE_EMPTY = "|cff888888  No uncollected drop mounts in this zone (or all collected!)|r",
        LDB_TT_ROW_RIGHT = "|cffffd100Tries: %d|r (%sWorld: %s)",

        -- Settings Menu
        CFG_TITLE = "|cff00ccffMount|r|cffffaa00Collector|r — Settings",
        CFG_SUBTITLE = "Track mount rarity (Data for Azeroth / Armory + Realm), account-wide attempts, map pins, and rare NPC drops.",
        CFG_LANG_LABEL = "Interface Language (Язык):",
        CFG_LANG_AUTO = "Auto (Client Locale)",
        CFG_LANG_RU = "Русский (ruRU)",
        CFG_LANG_EN = "English (enUS)",

        CFG_SEC_TOOLTIPS = "Mount Journal & Tooltips",
        CFG_SHOW_TOOLTIPS = "Show MountCollector block in mount & mount-item tooltips",
        CFG_SHOW_ROW_HOVER = "Show full mount tooltip when hovering mount rows in the Mount Journal list",
        CFG_SHOW_MOUNT_DISPLAY = "Show rarity & attempt summary on the 3D preview pane in Mount Journal",
        CFG_SHOW_GLOBAL_RARITY = "Show Global Rarity % (Data for Azeroth / Armory)",
        CFG_SHOW_SERVER_RARITY = "Show Realm owners estimate and live realm sightings",
        CFG_SHOW_ATTEMPTS = "Show account-wide attempts and per-character breakdown",

        CFG_SEC_RADAR = "Boss / Rare Radar, World Map Pins & Minimap Icon",
        CFG_ALERT_RARES = "Scream & show radar banner when a boss/rare dropping a missing mount (or mount item) is nearby",
        CFG_ALERT_SOUND = "Play alert sound when a rare/boss with a missing mount is detected",
        CFG_AUTO_WAYPOINT = "Automatically set 3D arrow & map pin (Blizzard + TomTom) when a rare is detected",
        CFG_WORLD_MAP_PINS = "Show icons on the World Map (M) for all zone rares/bosses dropping missing mounts",
        CFG_SHOW_NPC_TT = "Show mount drop & attempts info on NPC/boss tooltips",
        CFG_ANNOUNCE_ATTEMPTS = "Print chat message when a new attempt is recorded",
        CFG_SHOW_MINIMAP = "Show MountCollector minimap button",

        CFG_BTN_OPEN_RADAR = "Open Radar (/mc)",
        CFG_BTN_TEST_ALERT = "Test Rare Alert Banner",
    },
}

function addon:GetActiveLocaleCode()
    local pref = (self.db and self.db.settings and self.db.settings.language) or "auto"
    if pref == "ruRU" or pref == "enUS" then
        return pref
    end
    local clientLocale = GetLocale and GetLocale() or "enUS"
    if clientLocale == "ruRU" then
        return "ruRU"
    end
    return "enUS"
end

addon.L = setmetatable({}, {
    __index = function(_, key)
        local code = addon:GetActiveLocaleCode()
        local tbl = Locales[code] or Locales.enUS
        return tbl[key] or Locales.enUS[key] or key
    end,
})
