# 🐯 MountCollector — Трекер цепочек маунтов, рарности, траев и радар рарников

**MountCollector (`v1.3.0`)** — комплексный аддон для **World of Warcraft (Retail 11.x / 12.x Midnight)**, объединяющий:
1. **Пошаговый навигатор квестовых цепочек и инкубации маунтов (`MountQuestsDB`)** с автоматическим ведением через **TomTom** и стандартную 3D-стрелку Blizzard.
2. **Двухколоночное окно в стиле ElvUI / «Транспорт» (`/mc`)** + **боковую док-колонку справа от стандартного окна Коллекции (`CollectionsJournal`)**.
3. **Глобальную рарность по миру (`Data for Azeroth` / `MountsRarity-2.0`)** и **оценку владельцев на вашем сервере** с живым сканером встреченных игроков.
4. **Кросс-аккаунтный счётчик траев боссов и рарников** (с синхронизацией `Rarity` и внутриигровой статистики `GetStatistic`).
5. **Радар рарников в открытом мире** и **интерактивные иконки несобранных маунтов на Карте Мира (`M`)**.

---

## ✨ Основные возможности

### 1. Навигатор квестовых цепочек и многодневных маунтов (`Цепочки и Квесты`)
* Отслеживает прогресс длинных квестовых цепочек, секретов, классовых маунтов Оплота и многодневной инкубации яиц (Совогрифон Жреца, Тенеколючий трутень в Ульдуме, Зиесбарг в Аз-Кахете, Грехоход Бланчи, Охряный сноходец, Отто, Лизи, Куа'фон, Дитя Торкалы, Фалькозавры Легиона, Нефритовый облачный змей и др.).
* Проверяет выполненные этапы через `C_QuestLog.IsQuestFlaggedCompleted`, активные квесты в журнале (`C_QuestLog.IsOnQuest`) и достижения (`GetAchievementInfo`), формируя наглядный чек-лист **СДЕЛАНО / НАДО СДЕЛАТЬ (ТЕКУЩИЙ ШАГ)**.
* **Авто-переключение шагов в TomTom:** при сдаче очередного квеста цепочки (`QUEST_TURNED_IN`) аддон автоматически перестраивает стрелку TomTom и 3D-метку Blizzard на следующий шаг маршрута.
* **Копирование ссылок на Wowhead (`Ctrl+C`):** правый клик по любому шагу цепочки (или кнопка «Ссылка на Wowhead») открывает компактное окно с уже выделенной ссылкой на конкретный квест или маунта.

### 2. Двухколоночный интерфейс `/mc` и боковая док-колонка в «Транспорт»
* **Главное окно (`/mc`):** выполнено в тёмном плоском дизайне под ElvUI:
  * **Слева:** живой поиск по названию/категории и список маунтов с цветовой индикацией прогресса.
  * **Справа:** карточка выбранного маунта, чек-лист шагов с координатами и панель быстрых действий (маршрут к текущему шагу, маршрут к старту цепочки, ссылка Wowhead, открытие 3D-модели в Коллекции).
  * **Встроенная вкладка «Настройки»:** открывается прямо внутри главного окна `/mc` без лишних плавающих окон.
* **Боковая док-колонка в `CollectionsJournal` (`Транспорт`):** при открытии стандартной Коллекции маунтов справа автоматически пристыковывается панель чек-листа и навигации для любого выбранного маунта (сворачивается кнопкой **«Цепочка / Навигатор»**).

### 3. Карта Мира, Радар рарников и Предметы-источники
* **Иконки на Карте Мира (`M`):** отображает на карте локации всех рарников и боссов, с которых ещё не выбит маунт (при дневном КД иконка становится полупрозрачной). ЛКМ по иконке ставит 3D-стрелку, ПКМ — открывает маунта в Коллекции.
* **Тултипы предметов для маунтов:** при наведении на яйца, ключи, фрагменты и квестовые предметы (база из 200+ предметов `RareScanner`) в тултипе сразу отображается, для какого маунта нужен предмет и собран ли он.
* **Радар-баннер:** всплывающее уведомление со звуком и авто-меткой при обнаружении живого рарника или босса с несобранным маунтом.

---

## 🏗 Архитектура проекта и структура файлов

Порядок загрузки модулей задаётся в [`MountCollector.toc`](file:///c:/Users/ev3n7/.gemini/antigravity/scratch/Games/MountCollector/MountCollector.toc):

| Файл | Назначение |
| :--- | :--- |
| [`Locales.lua`](file:///c:/Users/ev3n7/.gemini/antigravity/scratch/Games/MountCollector/Locales.lua) | Двуязычный словарь (`ruRU` / `enUS`) с метатаблицей `addon.L` и поддержкой мгновенного переключения языка без `/reload`. Использует встроенные текстурные иконки WoW (`\|TInterface\...\|t`) вместо неподдерживаемых в `FRIZQT___CYR.TTF` символов Unicode. |
| [`MountDropsDB.lua`](file:///c:/Users/ev3n7/.gemini/antigravity/scratch/Games/MountCollector/MountDropsDB.lua) | База дроп-маунтов (`addon.MountDropsBySpell`), привязка 200+ предметов к маунтам (`addon.RareScannerMountItems`) и база координат/квест-локов рарников (`addon.RareScannerNpcToMounts`). |
| [`MountQuestsDB.lua`](file:///c:/Users/ev3n7/.gemini/antigravity/scratch/Games/MountCollector/MountQuestsDB.lua) | Структурированная база многошаговых квестовых цепочек и инкубации маунтов (`addon.MountQuestsDB`). Содержит точные `mountID`, `spellID`, `itemID`, `wowheadUrl` и массив шагов `steps`. |
| [`Core.lua`](file:///c:/Users/ev3n7/.gemini/antigravity/scratch/Games/MountCollector/Core.lua) | Ядро аддона: инициализация `MountCollectorDB`, построение единого индекса (`BuildMountIndex`), расчёт статуса цепочек (`GetMountQuestChainStatus`), постановка точек (`SetMountWaypoint`, `NavigateMountQuestStep`), учёт траев (`GetMountAttempts`, `RecordAttempt`) и обработка событий с защитой от Taint в WoW 12.1.5. |
| [`Tooltips.lua`](file:///c:/Users/ev3n7/.gemini/antigravity/scratch/Games/MountCollector/Tooltips.lua) | Хуки `TooltipDataProcessor` (для маунтов, заклинаний, предметов и NPC), ховер строчек списка в `MountJournal` и сводка на 3D-превью `MountDisplay`. |
| [`RadarUI.lua`](file:///c:/Users/ev3n7/.gemini/antigravity/scratch/Games/MountCollector/RadarUI.lua) | Плоские UI-компоненты (`ApplyFlatBackdrop`, `CreateFlatButton`), главное двухколоночное окно `/mc` (`MountCollectorRadarFrame`), боковая док-колонка `MountCollectorJournalDock`, радар-баннер, пины на Карте Мира и иконка миникарты (`LibDBIcon-1.0`). |
| [`Config.lua`](file:///c:/Users/ev3n7/.gemini/antigravity/scratch/Games/MountCollector/Config.lua) | Конструктор настроек (`addon:BuildSettingsControls`), встраивающий панель настроек как во вкладку «Настройки» внутри `/mc`, так и в системное меню `ESC -> Параметры -> Модификации -> MountCollector`. |

---

## 🧩 Как добавить новую квестовую цепочку в `MountQuestsDB.lua`

Каждая запись в массиве `addon.MountQuestsDB` в [`MountQuestsDB.lua`](file:///c:/Users/ev3n7/.gemini/antigravity/scratch/Games/MountCollector/MountQuestsDB.lua) имеет следующий формат:

```lua
{
    mountID = 1320,                                    -- Точный ID маунта в C_MountJournal
    spellID = 316339,                                  -- ID заклинания маунта
    itemID = 174771,                                   -- ID предмета маунта (опционально)
    wowheadUrl = "https://www.wowhead.com/ru/item=174771",
    classRestriction = nil,                            -- Например "PRIEST", если маунт классовый
    categoryRU = "Инкубация яйца (30 дней, BfA)",
    categoryEN = "Egg Incubation (30 Days, BfA)",
    summaryRU = "Краткое описание цепочки на русском...",
    summaryEN = "Short chain summary in English...",
    steps = {
        {
            titleRU = "Шаг 1: Название этапа",
            titleEN = "Step 1: Stage Title",
            descRU = "Подробное описание, что нужно сделать...",
            descEN = "Detailed instructions for this step...",
            npcRU = "Имя NPC или объекта",
            npcEN = "NPC or Object Name",
            zoneRU = "Ульдум",
            zoneEN = "Uldum",
            mapID = 1527, x = 20.8, y = 61.9,          -- UiMapID и координаты для TomTom
            quests = { 58615 },                        -- Список questID этапа
            doneQuest = 58615,                         -- Финальный questID, закрывающий шаг
            achievementID = nil,                       -- Опционально: ID достижения
        },
    },
}
```

---

## 🛡 Совместимость с WoW 12.1.5 (*Midnight*) и защита от Taint

В патче **12.1.5 (*Midnight*)** Blizzard ввела систему секретных значений (`Secret Values` / `C_Secrets`) и защитила ряд событий миникарты:
1. Аддон **не регистрирует** защищённое событие `VIGNETTE_MINIMAP_UPDATED`, чтобы не вызывать блокировку (`ADDON_ACTION_FORBIDDEN`) при клике по виньеткам на миникарте.
2. Сканер маунтов окружающих игроков (`addon:ScanUnitMount` в [`Core.lua`](file:///c:/Users/ev3n7/.gemini/antigravity/scratch/Games/MountCollector/Core.lua)) работает только вне инстансов и в мирном режиме, предварительно проверяя `C_Secrets.ShouldAurasBeSecret()`, `C_Secrets.ShouldUnitAuraIndexBeSecret()` и `_G.issecretvalue()`.

---

## 💬 Слэш-команды

* `/mc` или `/mountcollector` — открыть / закрыть главное двухколоночное окно **MountCollector**.
* `/mc config` или `/mc settings` — открыть окно **MountCollector** сразу на встроенной вкладке **«Настройки»**.
