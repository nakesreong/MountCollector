# MountCollector — Quest Chain Navigator, Rarity Census, Attempt Tracker & Rare Boss Radar

**Version:** 1.4.0  
**Authors:** Gemini (Tiger) & Anya (5cr3am1ng5oul)  
**Compatibility:** World of Warcraft: Retail / Midnight (`12.1.7`, `12.1.5`) & The War Within (`11.2.7`)  
**Source Repository:** [https://github.com/nakesreong/MountCollector](https://github.com/nakesreong/MountCollector)  
**License:** MIT

---

## Overview

**MountCollector** is a modular mount collection, progression, and radar suite for World of Warcraft. It unifies multi-step questline tracking, egg incubation checklists, global and realm rarity statistics, account-wide boss/rare attempt counters, and open-world rare navigation into a cohesive dark flat UI modeled after ElvUI.

* **Step-by-Step Quest Chain & Egg Incubation Navigator:** Tracks progress across 54 complex multi-day questlines, secret mounts, all 11 Legion Class Order Hall campaigns, and hatchling incubation chains (`MountQuestsDB`), with live Lua quest/item evaluation and automated **TomTom** + Blizzard 3D waypoint routing.
* **Built-In Lua Quest & Condition Debugger (`/mc debug`):** Inspects every quest flag (`IsQuestFlaggedCompleted`, `IsQuestFlaggedCompletedOnAccount`, `IsOnQuest`, `GetQuestObjectives`), achievement criteria, bag item count, and daily rare lockout in a copyable diagnostic window.
* **Two-Column Control Center (`/mc`) & Mount Journal Side-Dock:** Features a standalone two-column browser (`/mc`) alongside a synchronized side-column docked directly to the right edge of the standard **Mount Journal (`CollectionsJournal`)** and a one-click **Source (MountCollector)** button on every mount's 3D preview.
* **Global & Realm Rarity Census:** Integrates **Data for Azeroth** global ownership percentages (`MountsRarity-2.0`) with realm population ownership estimates and a live out-of-instance player mount scanner.
* **Account-Wide Attempt Counter & Probability Engine:** Tracks boss and rare NPC kills across all characters on your account (`MountCollectorDB`), bridges with **Rarity** and Blizzard's internal kill statistics (`GetStatistic`), and calculates cumulative drop odds (`1 - (1 - 1/N)^K`).
* **World of Warcraft 12.x (Midnight) Taint-Safe Architecture:** Engineered with `C_Secrets.ShouldAurasBeSecret()`, `C_Secrets.ShouldUnitAuraIndexBeSecret()`, and `issecretvalue()` guards, avoiding protected minimap vignette events (`VIGNETTE_MINIMAP_UPDATED`) to guarantee zero taint in modern combat and instance environments.
* **Multi-Language Client Support:** Localized across all 11 World of Warcraft client locales (`enUS`/`enGB`, `ruRU`, `deDE`, `frFR`, `esES`/`esMX`, `itIT`, `ptBR`, `koKR`, `zhCN`, `zhTW`) with instant live language switching without reloading the UI.

---

## Architecture & Core Subsystems

### 1. Quest Chain & Multi-Day Incubation Tracker (`MountQuestsDB.lua`)
Tracks 20 major multi-step questline, secret, and incubation mounts (including *High Priest's Lightsworn Seeker*, *Shadowbarb Drone*, *Siesbarg*, *Springfur Alpaca*, *Ochre Dreamtalon*, *Sinrunner Blanchy*, *Loyal Gorger*, *Lizi's Reins*, *Otto*, *Child of Torcali*, *Kua'fon*, *Honeyback Harvester*, *Long-Forgotten Hippogryph*, all four *Legion Falcosaurs*, *Jade Cloud Serpent*, *Venomhide Ravasaur*, and *Winterspring Frostsaber*):
* **Live Step Evaluation:** Queries `C_QuestLog.IsQuestFlaggedCompleted`, `C_QuestLog.IsOnQuest`, and `GetAchievementInfo` in real time to classify every stage as `DONE`, `TO DO (CURRENT STEP)`, or `TO DO`.
* **Automated TomTom & SuperTrack Routing:** Clicking any step or pressing **Route: Current Step (TomTom)** places both a **TomTom** navigation arrow and a native Blizzard 3D `UiMapPoint` (`C_SuperTracked`). When a step's completion quest is turned in (`QUEST_TURNED_IN`), MountCollector automatically advances the waypoint to the next step in the chain.
* **In-Game Wowhead Link Generator:** Right-clicking any quest step or clicking **Copy Wowhead Link (Ctrl+C)** opens a pre-highlighted copy box with the exact locale-aware Wowhead URL for that quest or mount.

### 2. Two-Column Radar Window (`/mc`) & Integrated Settings
A standalone dark flat interface (`MountCollectorRadarFrame`) organized into three data views and an integrated configuration tab:
* **Quest Chains Tab:** Prioritizes uncollected class-specific and started quest chains at the top of the list, with live search filtering by mount name or category.
* **In Current Zone Tab:** Lists all uncollected drop and rare mounts available in the player's current zone (`C_Map.GetBestMapForUnit("player")`), sorted by daily lockout status and attempt count, with a one-click **Pin All on Map** action.
* **All Account Attempts Tab:** Displays all uncollected mounts with recorded attempts across your account, sorted by total tries.
* **Integrated Settings Tab:** Opens directly inside `/mc` without spawning separate floating popup windows, alongside full registration in Blizzard's standard `ESC -> Options -> AddOns -> MountCollector` menu.

### 3. Mount Journal (`CollectionsJournal`) Integration & Side-Dock
Enhances Blizzard's native Mount Journal without replacing it:
* **Docked Inspector Column (`MountCollectorJournalDock`):** Attaches a collapsible checklist and navigation panel to the right side of `CollectionsJournal` that updates automatically as you select mounts in the journal.
* **Full Row-Hover Tooltips:** Hovering anywhere over a mount row in the journal list displays its full tooltip (Mount Name, Collection Status, Drop Source, Lore, Rarity, Account Attempts, and Quest Chain Step) without requiring you to hover the small spell icon.
* **3D Preview Pane Summary:** Appends rarity, attempt statistics, and a direct **Quest Chain Guide (TomTom)** button inside the 3D model preview panel.

### 4. World Map Pins, Open-World Rare Radar & Source Item Tooltips
Built on a database of 264 drop mounts, 353 rare NPCs, and 200+ mount-related items (`MountDropsDB.lua`):
* **World Map Pins (`WorldMapFrame`):** Renders interactive mount icons at exact spawn coordinates on the World Map (`M`) for uncollected zone rares and bosses. Icons automatically desaturate when the rare is already killed on the active character today (`[Locked]`).
* **Proximity Rare Alert Banner:** Monitors `NAME_PLATE_UNIT_ADDED`, `PLAYER_TARGET_CHANGED`, and `UPDATE_MOUSEOVER_UNIT` for uncollected mount-dropping NPCs, triggering a movable alert banner with audio notification and optional automatic waypoint placement.
* **Mount Source Item Tooltips:** Appends target mount ownership and rarity information directly onto tooltips of eggs, keys, fragments, and quest items required to obtain mounts.

---

## Module Reference

| File | Responsibility |
| :--- | :--- |
| `Locales.lua` | Dynamic localization table (`addon.L`) supporting `enUS` and `ruRU` with live language switching and native WoW inline texture status icons. |
| `MountDropsDB.lua` | Database of drop mounts (`MountDropsBySpell`), 200+ mount source items (`RareScannerMountItems`), and rare NPC spawn coordinates/lockout quests (`RareScannerNpcToMounts`). |
| `MountQuestsDB.lua` | Structured step-by-step database of questline, secret, and multi-day incubation mounts (`MountQuestsDB`). |
| `Core.lua` | SavedVariables initialization (`MountCollectorDB`), unified index builder (`BuildMountIndex`), quest chain evaluator (`GetMountQuestChainStatus`), TomTom/Blizzard waypoint router (`SetMountWaypoint`), attempt tracker (`RecordAttempt`), and taint-safe event dispatcher. |
| `Tooltips.lua` | `TooltipDataProcessor` post-calls for Mounts, Spells, Items, and Units, plus `MountJournal` row-hover hooks and 3D preview summary injection. |
| `RadarUI.lua` | Flat UI component library (`ApplyFlatBackdrop`, `CreateFlatButton`), two-column `/mc` window, `CollectionsJournal` side-dock, alert banner, World Map pins, and `LibDataBroker-1.1` / `LibDBIcon-1.0` minimap icon. |
| `Config.lua` | Shared settings builder (`BuildSettingsControls`) powering both the integrated Settings tab inside `/mc` and the Blizzard AddOn Options canvas. |

---

## Quest Chain Data Schema (`MountQuestsDB.lua`)

```lua
{
    mountID = 1320,                                    -- Exact C_MountJournal mountID
    spellID = 316339,                                  -- Mount summon spellID
    itemID = 174771,                                   -- Mount itemID (optional)
    wowheadUrl = "https://www.wowhead.com/item=174771",
    classRestriction = nil,                            -- Optional class token (e.g., "PRIEST")
    categoryRU = "Инкубация яйца (30 дней, BfA)",
    categoryEN = "30-Day Egg Incubation (BfA)",
    summaryRU = "Вырастите маунта в Ульдуме за 30 дней ежедневных заданий.",
    summaryEN = "Raise the Aqir hatchling in Uldum across 30 days of daily quests.",
    steps = {
        {
            titleRU = "Шаг 1: Найти Яйцо в Бездне (Ульдум)",
            titleEN = "Step 1: Find Voidtouched Egg (Uldum)",
            descRU = "Осмотрите яйцо акира в Ульдуме [20.8, 61.9] и отнесите его Х'партосу [54.9, 32.9].",
            descEN = "Loot the Voidtouched Egg in Uldum [20.8, 61.9] and deliver it to H'partho [54.9, 32.9].",
            npcRU = "Яйцо в Бездне / Х'партос",
            npcEN = "Voidtouched Egg / H'partho Ardoros",
            zoneRU = "Ульдум",
            zoneEN = "Uldum",
            mapID = 1527, x = 20.8, y = 61.9,          -- UiMapID and coordinates for TomTom
            quests = { 58615 },                        -- Step questIDs
            doneQuest = 58615,                         -- Completion questID for this stage
            achievementID = nil,                       -- Optional completion achievementID
        },
    },
}
```

---

## Slash Commands & Controls

* `/mc` or `/mountcollector` — Toggle the main **MountCollector** window.
* `/mc config` or `/mc settings` — Open **MountCollector** directly on the **Settings** tab.
* **Left-Click (Minimap Button):** Toggle the **MountCollector** window.
* **Right-Click (Minimap Button):** Open the **Mount Journal (`CollectionsJournal`)**.
* **Middle-Click (Minimap Button):** Open the **Settings** tab.
* **Left-Click (Quest Step / Map Pin):** Set a **TomTom** and Blizzard 3D waypoint to the target coordinates.
* **Right-Click (Quest Step):** Open the **Copy Wowhead Link (`Ctrl+C`)** dialog for that quest.

---

## License

Released under the [MIT License](LICENSE).
