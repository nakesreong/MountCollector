# Changelog

## [v1.1.0] - 2026-10-22
### Added
- **Localization (`Locales.lua`)**: Full bilingual localization (`enUS` and `ruRU`) with automatic client locale detection (`GetLocale()`) and instant in-game language switching (`Auto / Русский / English`).
- **Settings Menu (`Config.lua`)**: Registered in Blizzard's AddOn Options (`ESC -> Options -> AddOns -> MountCollector`) and accessible via `/mc config`, Middle-Clicking the minimap icon, or clicking the **Settings** button in `/mc`.
- **3D Mount Display Layout Polish**: Dedicated `MountCollectorSummary` FontString anchored cleanly below `infoBtn.Lore` so Rarity and Attempt stats never overlap with the mount's lore text.

## [v1.0.0] - 2026-10-22
### Added
- Initial release of **MountCollector** with embedded `MountsRarity-2.0` (Data for Azeroth), `LibDataBroker-1.1`, `LibDBIcon-1.0`, `MountDropsDB` (264 drop mounts & 353 rare NPCs), live `Rarity` + `GetStatistic` bridge, Realm Census scanner, and Open-World Rare Mount Radar (`/mc`).
