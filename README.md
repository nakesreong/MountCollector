# MountCollector — Rare Radar, World Boss & Dungeon Lockouts, Quest Chain Navigator & Rarity Census

**Version:** 1.8.0  
**Authors:** Gemini (Tiger) & Anya (5cr3am1ng5oul)  
**Compatibility:** World of Warcraft: Retail / Midnight (`12.1.7`, `12.1.5`) & The War Within (`11.2.7`)  
**Source Repository:** [https://github.com/nakesreong/MountCollector](https://github.com/nakesreong/MountCollector)  
**License:** Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)

***

## Overview

**MountCollector** is a modular mount collection, lockout matrix, progression, and open-world rare radar suite for World of Warcraft. It unifies open-world rare spawn routing, account-wide World Boss and Dungeon/Raid alt lockout tracking, multi-step questline and egg incubation checklists, global and realm rarity statistics, and cumulative attempt counters into a clean dark flat UI modeled after ElvUI.

*   **Open-World Rare Radar & Smart 3D Spawn Tour:** Detects uncollected mount-dropping rares in your current zone, filters out rares already killed today, and builds an automated Nearest-Neighbor 3D waypoint tour (`C_Map.SetUserWaypoint` + `C_SuperTrack` + optional **TomTom**) that automatically yields control whenever you manually place a map pin or track a quest.
*   **World Bosses & Dungeon/Raid Alt Lockout Matrix:** Dedicated **World Bosses** and **Dungeon & Raid** tabs track 78 instance, raid, holiday, and open-world boss mounts across all eligible characters on your account (filtering out underleveled alts and sorting bosses available on your active character to the top).
*   **Step-by-Step Quest Chain & Egg Incubation Navigator:** Tracks progress across 54 multi-day questlines, secret mounts, Class Order Hall campaigns (including all alternate class mount tints), and hatchling incubation chains (`MountQuestsDB`), verified against official Blizzard `Mount.db2` and `ItemEffect.db2` data.
*   **Glory & Meta-Achievement Tracker (`MountGloryDB`):** Dedicated **Glory & Achievements** tab tracking 43 _Glory of the Hero_, _Glory of the Raider_, _Glory of the Delver_, and _Guild Glory_ mounts across 604 verified sub-achievements (`Achievement.db2` + `CriteriaTree.db2`), displaying live completion percentages, `[100% Solo]` vs `[Group N+]` mechanical indicators, 3D raid entrance routing, and one-click jumping into Blizzard's Achievement window.
*   **Global & Realm Rarity Census:** Integrates **Data for Azeroth** global ownership percentages for 1,574 mounts (`MountsRarity-2.0`) with realm population ownership estimates and a live out-of-instance player mount scanner.
*   **Account-Wide Attempt Counter & Probability Engine:** Tracks boss, rare NPC, and cache/bag attempts across all characters on your account (`MountCollectorDB`), bridges with **Rarity** and Blizzard's internal kill statistics (`GetStatistic`), and calculates cumulative drop odds (`1 - (1 - 1/N)^K`).
*   **World of Warcraft 12.x (Midnight) Taint-Safe & Instance-Safe Architecture:** Engineered with `issecretvalue()` guards, combat-safe `SecureActionButtonTemplate` targeting, and strict instance suppression (`IsInInstance()`) so rare alerts never spam during dungeon or raid encounters.
*   **Dynamic Multi-Locale Layout & Round Minimap Icon:** Automatically adapts tab widths, header boxes, and action buttons to fit any screen resolution or language (**English `enUS`** and **Russian `ruRU`** with live instant switching), paired with a circular horseshoe minimap button (`LibDataBroker-1.1` / `LibDBIcon-1.0` + `AddonCompartment`) compatible with **HidingBar**, **ElvUI**, **Titan Panel**, and **Bazooka**.

***

## Architecture & Core Subsystems

### 1. Two-Column Radar Window (`/mc`) & Seven Integrated Views

A standalone dark flat interface (`MountCollectorRadarFrame`, registered in `UISpecialFrames` for instant `Esc` closing in ActionCam/Combat Mode) organized into six progression views and an integrated configuration tab:

1.  **In Current Zone Tab:** Lists all uncollected rare and World Boss mounts in the player's current zone (`C_Map.GetBestMapForUnit("player")`), displaying live daily rare lockout progress (`Rares: X/Y`) and one-click **Pin All on Map** routing without forcing the World Map open.
2.  **World Bosses Tab:** Dedicated tracker for open-world and holiday World Boss mounts (_Sha of Anger_, _Galleon_, _Nalak_, _Oondasta_, _Rukhmar_, _Dunegorger Kraulok / Mollie_, _Beledar's Spawn_ with a live 3-hour Void Phase countdown timer, _Doomwalker_, and _Daetan Swiftplume_), cross-linked with the **In Current Zone** tab.
3.  **Dungeon & Raid Tab:** Tracks 70+ dungeon, mega-dungeon, raid, and holiday boss mounts from Classic through _The War Within_ and _Midnight_, showing required character levels, difficulty modes, cross-linked raid _Glory_ progress, and an account-wide readiness roster (`Ready` vs `Locked` per character) with a single full-width **Mark Dungeon Entrance** 3D waypoint button.
4.  **Quest Chains Tab:** Covers 54 multi-step questline, secret, reputation, and incubation mounts (including _Siesbarg_, _Alunira_, _Kah, Legend of the Deep_, _Ochre Dreamtalon_, _Otto_, _Lizi_, _Loyal Magmammoth_, _Pattie_, _Sinrunner Blanchy_, _Loyal Gorger_, _Hand of Nilganihmaht_, _Maelie_, _Kua'fon_, _Honeyback Harvester_, _Shadowbarb Drone_, _Springfur Alpaca_, _Lucid Nightmare_, _Riddler's Mind-Worm_, _Long-Forgotten Hippogryph_, all four _Legion Falcosaurs_, and all 12 _Legion Class Order Hall_ mount chains and alternate tints).
5.  **Glory & Achievements Tab:** Tracks 43 meta-achievement mounts and 604 boss sub-achievements from _Wrath of the Lich King_ through _Midnight_, sorted by closest completion percentage and `[100% Solo]` soloability.
6.  **All Account Attempts Tab:** Displays all uncollected mounts with recorded attempts across your account, sorted by total tries, with manual attempt override support (`Set Attempts`).
7.  **Integrated Settings Tab:** Opens directly inside `/mc` alongside standard registration in Blizzard's `ESC -> Options -> AddOns -> MountCollector` panel, featuring independent radar alert toggles for soloable open-world Rares vs Bosses & Group Rare-Bosses (`Vignette.db2` `VignetteKill` vs `VignetteKillElite`).

### 2. Smart 3D Navigation, Nearest-Neighbor Spawn Tour & Rare Alert Banner

Built on a verified database of 264 drop mounts, 353 mount items, and 223 rare NPCs:

*   **Nearest-Neighbor Spawn Tour & Cross-Continent Portal Routing (`Navigation.lua`):** Orders all remaining unlocked spawn points for a rare mount into an optimal loop starting from your player position, and automatically guides you step-by-step through capital portal rooms when routing across continents. As you fly into/touch a point (`<= 48` yards) or kill a rare, the 3D diamond pin (`C_SuperTrack`), TomTom arrow, and World Map pin automatically clear or advance to the next coordinate.
*   **Non-Intrusive Manual Override:** If you manually Ctrl/Shift-click a custom pin on the World Map or switch super-tracking to a quest objective, MountCollector immediately exits the automated spawn tour so it never fights your manual waypoints.
*   **Open-World Rare Radar & Auto-Target (`RareRadar.lua`):** Monitors unit targets, mouseovers, nameplates, vignettes, and monster yells exclusively in the open world (`IsPlayerInInstancedContent()` blocks all alerts inside dungeons, raids, arenas, and battlegrounds). Left-clicking the alert banner (or pressing `Tab` on approach when out of combat) targets the rare via a taint-free `SecureActionButtonTemplate` overlay and sets a 3D waypoint.
*   **Interactive World Map Pins & Repeatable Rare Respawn Timers (`MapPins.lua`, `Lockouts.lua`):** Renders interactive mount icons on the World Map (`M`) for uncollected rares and World Bosses that are still available to loot today, tracks Unique 3-day incubating eggs (_Primal Egg_ / _Mysterious Egg_), per-corpse AoE mob counters, and live respawn countdowns (`Killed X min ago — respawn ~30–60 min`) for repeatable rares.

### 3. Mount Journal (`CollectionsJournal`) Integration & Side-Dock

Enhances Blizzard's native Mount Journal without replacing it:

*   **Docked Inspector Column (`MountCollectorJournalDock`):** Attaches a collapsible checklist and navigation panel to the right side of `CollectionsJournal` that updates automatically as you select mounts in the journal.
*   **Full Row-Hover & Item Tooltips (`Tooltips.lua`):** Hovering over any mount row in the journal list or any mount-related item in your bags displays global rarity, realm ownership estimates, account attempts (with per-character breakdown), daily lockout counts, and current quest chain progress.

***

## Slash Commands & Controls

*   `/mc` or `/mountcollector` — Toggle the main **MountCollector** window.
*   `/mc config` or `/mc settings` — Open **MountCollector** directly on the **Settings** tab.
*   `/mc check` — Run the built-in module and `C_MountJournal` DB2 ID integrity validator.
*   `/mc debug [mountID]` — Open the Lua diagnostic inspector for the selected mount.
*   `/mc set [count]` — Manually set or reset the account attempt counter for the selected mount.
*   **Left-Click (Minimap Horseshoe Icon):** Toggle the **MountCollector** window.
*   **Right-Click (Minimap Horseshoe Icon):** Open the **Mount Journal (`CollectionsJournal`)**.
*   **Middle-Click (Minimap Horseshoe Icon):** Open the **Settings** tab.
*   **Left-Click (Checklist Card / Map Pin):** Set a Blizzard 3D waypoint (and **TomTom** arrow if installed) to that step or spawn point.
*   **Right-Click (Checklist Card):** Open the **Copy Wowhead Link (`Ctrl+C`)** dialog for that quest or mount.
