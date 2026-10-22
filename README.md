# 🐯 MountCollector — Mount Rarity, Attempt Tracker & Rare Boss Radar

**MountCollector** is a lightweight, modern World of Warcraft (Retail 11.x / 12.x) addon that enriches your **Mount Journal (`CollectionsJournal`)** and open-world exploration with **Global Armory Rarity** (*Data for Azeroth* via `MountsRarity-2.0`), **Realm Rarity & Live Server Sightings**, **Account-Wide Boss/Rare Attempt Tracking**, and a **Real-Time Open-World Rare Mount Radar**.

---

## ✨ Key Features

### 1. Mount Journal & Tooltip Integration
* **Full Row-Hover Tooltips in the Mount Journal:** Hovering anywhere over a mount's row in the Mount Journal list automatically displays its full tooltip (Mount Name, Collected Status, Drop Source, Lore Description, Rarity, and Attempts) without needing to aim at the tiny spell icon.
* **Global Rarity (`Data for Azeroth` / Armory):** Displays exact worldwide ownership percentage (`0.01% – 100%`) color-coded by tier (*Mythic `<1%`*, *Ultra Rare `<3%`*, *Epic `<10%`*, *Rare `<25%`*, *Uncommon*, *Common*).
* **Realm Rarity & Live Server Census:** Estimates active owners on your current realm AND passively scans mounted players around you (`C_UnitAuras`) to count unique live sightings on your server.
* **3D Preview Summary:** Cleanly appends Rarity and Account Attempt stats below the mount's Lore description in the right-side 3D model preview panel.

### 2. Account-Wide Attempt Tracking & Sync
* Tracks boss kills and rare NPC kills across **all characters on your account** (`MountCollectorDB`), with a per-character breakdown in the tooltip.
* Automatically bridges and syncs with **`Rarity`** (if installed) and Blizzard's internal boss kill statistics (`GetStatistic`).
* Calculates cumulative drop probability (*"Cumulative odds after N tries: X%"*) and displays daily/weekly rare lockout status (`[Locked Today]`) on the active character.

### 3. Open-World Rare & Boss Radar (`/mc`)
* Scans `NAME_PLATE_UNIT_ADDED`, `VIGNETTE_MINIMAP_UPDATED`, `PLAYER_TARGET_CHANGED`, and `UPDATE_MOUSEOVER_UNIT` for bosses and rares that drop **uncollected mounts**.
* Pops a sleek, movable radar alert banner when a mount-dropping rare or boss is nearby (Left-Click opens the mount in the Mount Journal; Right-Click dismisses).
* Includes a **Minimap Button (`LibDBIcon-1.0`)**, **DataBroker feed (`LibDataBroker-1.1`)**, and a **Zone Radar Window (`/mc`)** showing all uncollected drop mounts in your current zone or across your entire account.

### 4. Localization & Settings Menu
* Automatic client language detection (`GetLocale()`) supporting **English (`enUS`)** and **Russian (`ruRU`)**, plus manual language switching on the fly in Settings.
* Full Settings panel in `ESC -> Options -> AddOns -> MountCollector` as well as `/mc config` (or clicking **Settings** inside `/mc`).

---

## 💬 Slash Commands
* `/mc` or `/mountcollector` — Toggle the **Mount & Attempt Radar** window.
* `/mc config` or `/mc settings` — Open the **MountCollector Settings** window.
