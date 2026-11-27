# MountCollector — Open-World Rare Radar, Alt Lockout Matrix, Quest & Glory Navigator & Rarity Census

**Authors:** Gemini (Tiger) & Anya (5cr3am1ng5oul)  
**Compatibility:** World of Warcraft: Retail / Midnight (`12.1.7`, `12.1.5`, `12.0.1`) & The War Within (`11.2.7`)  
**Source Repository:** [https://github.com/nakesreong/MountCollector](https://github.com/nakesreong/MountCollector)  
**License:** Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)

***

## Overview

**MountCollector** is a modular mount collection, account-wide lockout matrix, live progression roadmap, real rarity encyclopedia, and open-world rare radar suite for World of Warcraft. It unifies automated rare spawn tours, multi-hop intercontinental portal routing, World Boss and Dungeon/Raid alt lockout tracking, multi-day questline and egg incubation checklists, *Glory* meta-achievement trackers, and cumulative attempt counters into a sleek dark-gold flat UI shared with our companion collection suites, **TitleCollector** and **BeastCollector**.

*   **Open-World Rare Radar & Smart 3D Spawn Tour:** Detects uncollected mount-dropping rares in your current zone, filters out rares already killed today, and builds an automated Nearest-Neighbor 3D waypoint tour (`C_Map.SetUserWaypoint` + `C_SuperTrack` + optional **TomTom**) that clears visited pins on fly-in (`<= 48` yds) or kill and yields cleanly whenever you manually place a map pin or track a quest.
*   **World Bosses & Dungeon/Raid Alt Lockout Matrix:** Dedicated **World Bosses** and **Dungeon & Raid** tabs track **78+ instance, raid, holiday, and open-world boss mounts** across all eligible characters on your account—with automatic same-realm rename merging via `GUID`, 30-day inactive alt filtering, smart realm tags for same-name alts, an interactive **Account Alts Manager (`/mc alts`)** to merge realm-transferred characters or prune deleted alts without losing historical attempts, and a live 3-hour Void Phase countdown for *Beledar's Spawn*.
*   **Step-by-Step Quest Chain & Egg Incubation Navigator:** Tracks live progress across **54 multi-day questlines, secret riddles, Class Order Hall campaigns** (including all alternate class mount tints), and hatchling incubation chains (`MountQuestsDB`), plus Unique 3-day egg lockouts (*Primal Egg* / *Mysterious Egg*) and per-corpse AoE bone counters.
*   **"Almost Done" Glory & Meta-Achievement Roadmap (`MountGloryDB`):** Dedicated **Glory & Achievements** tab tracking **43 _Glory of the Hero_, _Glory of the Raider_, _Glory of the Delver_, and _Guild Glory_ mounts** across **604 verified sub-achievements** (`Achievement.db2` + `CriteriaTree.db2`), sorting your closest completion percentages to the top with `[100% Solo]` vs `[Group N+]` mechanical tags and a one-click `[100% Solo]` filter.
*   **Vendor Mounts, Live Wallet & Reputation / Renown Tracker (`MountVendorsDB`):** Dedicated **Vendors** tab covering **477 purchasable vendor mounts** across *Classic* through *Midnight*—evaluating your live Gold, Currencies (`C_CurrencyInfo`), Warband Bank / Bag tokens, Classic Reputations, Friendship ranks, and Warband Major Faction Renown (`C_MajorFactions`) to highlight mounts that are **`[Ready to Buy!]`** right now and plot multi-hop 3D portal routes straight to the quartermaster.
*   **Global & Realm Rarity Census:** Integrates **Data for Azeroth** global Armory ownership percentages across **1,574+ mounts** (`MountsRarity-2.0`, auto-updated twice weekly on Thursdays and Sundays) with realm population ownership estimates and a passive open-world player mount scanner (`RealmCensus`).
*   **Account-Wide Attempt Counter & Probability Engine:** Tracks boss, rare NPC, and holiday cache/bag attempts across all characters on your account (`MountCollectorDB`), bridges seamlessly with **Rarity** and Blizzard's internal kill statistics (`GetStatistic`), and calculates cumulative drop luck (`1 - (1 - 1/N)^K`).
*   **World of Warcraft 12.x (Midnight) Secret-Value Safe & Instance-Safe Architecture:** Engineered with `issecretvalue()` guards, combat-safe `SecureActionButtonTemplate` targeting, and strict instance suppression (`IsInInstance()`) plus independent toggles for soloable open-world Rares vs Group Rare-Bosses (`Vignette.db2`), paired with instant **`[EN]` / `[RU]`** hot-swapping and a circular golden horseshoe minimap button (`LibDataBroker-1.1` / `LibDBIcon-1.0` + `AddonCompartment`).

***

## Architecture & Core Subsystems

### 1. Two-Column Collector Window (`/mc`) & Eight Integrated Views

A standalone dark-gold flat interface (`MountCollectorRadarFrame`, registered in `UISpecialFrames` for instant `Esc` closing in ActionCam/Combat Mode) organized into seven progression views and an integrated configuration panel:

1.  **In Current Zone Tab:** Dynamically detects your current map (`C_Map.GetBestMapForUnit("player")`) and lists all uncollected rare and World Boss mounts obtainable right where you stand—from *Classic* through *The War Within* and *Midnight* (*Harandar*, *Eversong Woods*, *Zul'Aman*, *Voidstorm*)—with live daily lockout counters (`Rares: X/Y`) and one-click **Pin All on Map** routing.
2.  **World Bosses Tab:** Dedicated tracker for open-world and holiday World Boss mounts (*Sha of Anger*, *Galleon*, *Nalak*, *Oondasta*, *Rukhmar*, *Dunegorger Kraulok / Mollie*, *Beledar's Spawn*, *Doomwalker*, and *Daetan Swiftplume*), cross-linked with the **In Current Zone** tab.
3.  **Dungeon & Raid Tab:** Tracks **70+ dungeon, mega-dungeon, raid, and holiday boss mounts** from *Classic* through *Midnight*, showing required character levels, difficulty modes, cross-linked raid *Glory* achievement progress, and an account-wide readiness roster (`Ready` vs `Locked` per character) with a full-width **Mark Dungeon Entrance** 3D waypoint button.
4.  **Quest Chains Tab:** Covers **54 multi-step questline, secret, reputation, and incubation mounts** (including *Siesbarg*, *Alunira*, *Kah, Legend of the Deep*, *Ochre Dreamtalon*, *Otto*, *Lizi*, *Loyal Magmammoth*, *Pattie*, *Sinrunner Blanchy*, *Loyal Gorger*, *Hand of Nilganihmaht*, *Maelie*, *Kua'fon*, *Honeyback Harvester*, *Shadowbarb Drone*, *Springfur Alpaca*, *Lucid Nightmare*, *Riddler's Mind-Worm*, *Long-Forgotten Hippogryph*, all four *Legion Falcosaurs*, and all 12 *Legion Class Order Hall* mount chains).
5.  **Glory & Achievements Tab:** Unfolds **43 meta-achievement mounts** and **604 boss sub-achievements** from *Wrath of the Lich King* through *Midnight* into a step-by-step boss checklist, sorted by closest completion percentage (`%`) and `[100% Solo]` soloability.
6.  **Vendors Tab:** Tracks **477 purchasable vendor mounts** (filtered automatically for your character's faction and class), displaying exact vendor coordinates, live currency/gold/item wallet balances, Reputation / Warband Renown requirements, a one-click **Ready to Buy Now!** filter, and direct 3D cross-continent routing to the vendor.
7.  **All Account Attempts Tab:** Displays all uncollected mounts with recorded attempts across your account, sorted by total tries, with one-click manual attempt override support (**Set Attempts**).
8.  **Settings Tab:** Fine-grained toggles for soloable Rare alerts vs Boss & Group Rare-Boss alerts, pop-up alert banner, out-of-combat mousewheel auto-targeting, alert sound, World Map pins, Mount Journal tooltips, instant **`ruRU` / `enUS`** language switching, and minimap icon visibility.

### 2. Multi-Hop Portal Navigation, Nearest-Neighbor Spawn Tour & Rare Alert Banner

Connects your mount journal directly to the game world (`Navigation.lua`, `RareRadar.lua` & `MapPins.lua`) across **264+ drop mounts, 353 mount items, and 223+ rare NPCs**:

*   **Intercontinental Portal Routing & Spawn Tour:** Orders all remaining unlocked spawn points for a rare mount into an optimal Nearest-Neighbor loop starting from your player position, and automatically plots step-by-step portal chains through capital portal rooms (*Stormwind*, *Orgrimmar*, *Dornogal*, *Silvermoon City*, *Harandar*) when routing across continents.
*   **Auto-Clear on Touch / Kill & Anti-Zombie Waypoint Yielding:** Automatically clears or advances the 3D diamond pin (`C_SuperTrack`), **TomTom** arrow, and World Map pin as soon as you fly into a spawn coordinate (`<= 48` yds) or kill the rare, and cancels active portal routes cleanly if you manually remove a pin.
*   **Taint-Free Rare Alert Banner & Auto-Target:** Monitors unit targets, mouseovers, nameplates, minimap vignettes, and monster yells exclusively in the open world (`IsPlayerInInstancedContent()` suppresses all alerts inside dungeons, raids, arenas, and battlegrounds). Left-clicking the banner targets the rare via a combat-safe `SecureActionButtonTemplate` overlay and sets a 3D waypoint.
*   **Interactive World Map Pins & Repeatable Rare Respawn Timers:** Renders interactive mount icons on the World Map (`M`) for uncollected rares and World Bosses available today, including live respawn countdowns (`Killed X min ago — respawn ~30–60 min`) for repeatable rares (*Huolon*, *Time-Lost Proto-Drake*, *Zandalari Warbringers*).

### 3. Mount Journal (`CollectionsJournal`) Side-Dock & Tooltip Integration

Enhances Blizzard's native Mount Journal without replacing it (`RadarUI.lua` & `Tooltips.lua`):

*   **Docked Inspector Column (`MountCollectorJournalDock`):** Attaches a collapsible step-by-step checklist, alt lockout roster, and 3D navigation panel to the right side of `CollectionsJournal` that updates automatically as you browse mounts in the journal.
*   **Full Row-Hover, Mount Display & Item Tooltips:** Hovering over any mount row in the journal list, any mount-related item in your bags, or any mount-dropping NPC in the world displays global rarity, realm ownership estimates, account attempts (with per-character breakdown), daily lockout counts, and live quest or *Glory* progress.

***

## Slash Commands & Controls

*   `/mc` or `/mountcollector` — Toggle the main **MountCollector** window (closes cleanly with `Esc`).
*   `/mc config` or `/mc settings` — Open **MountCollector** directly on the **Settings** tab.
*   `/mc alts` or `/mc chars` — Open the **Account Alts & Sync Manager** (merge transferred characters, set inactive auto-hide days, or prune deleted alts).
*   `/mc check` — Run the built-in module and `C_MountJournal` DB2 ID integrity validator.
*   `/mc debug [mountID]` — Open the Lua diagnostic inspector for the selected mount.
*   `/mc set [count]` — Manually set or reset the account attempt counter for the selected mount.
*   **Left-Click (Minimap Horseshoe Icon):** Toggle the **MountCollector** window.
*   **Right-Click (Minimap Horseshoe Icon):** Open Blizzard's **Mount Journal (`CollectionsJournal`)**.
*   **Middle-Click (Minimap Horseshoe Icon):** Open the **Settings** tab.
*   **Left-Click (Checklist Card / Map Pin):** Set a Blizzard 3D waypoint (and **TomTom** arrow if installed) with automatic cross-continent portal routing.
*   **Shift + Left-Click (Glory Achievement Card):** Open that exact achievement directly inside Blizzard's **Achievement UI (`Y`)**.
*   **Right-Click (Checklist Card):** Open the **Copy Wowhead Link (`Ctrl+C`)** dialog for that quest, achievement, item, or mount.

***

## Companion Collector Suite by Gemini & Anya

*   **MountCollector:** Open-World Rare Radar, World Boss & Dungeon Alt Lockout Matrix, Quest Chain & *Glory* Meta-Achievement Navigator, and Data for Azeroth Rarity Census.
*   **TitleCollector:** Live Title Progress Tracker (`688` titles), *"Almost Done"* Completionist Roadmap, 2-Level Meta-Achievement & Renown Engine, Rarity Census, Nameplate Preview, and Smart Auto-Title Switcher.
*   **BeastCollector:** Hunter Pet Encyclopedia (`61` families, `2,635` models from Petopia & Blizzard DB2), Spec & Ability Filters, Taming Tome Tracker, and 3D Multi-Hop Portal Navigator.
