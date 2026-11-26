#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MountCollector — MountVendorsDB.lua Builder
Extracts all purchasable Vendor mounts from official Blizzard Mount.db2 (enUS + ruRU),
resolves CurrencyTypes.db2, Faction.db2 (Classic Reputation + Warband Major Faction Renown),
dual Alliance/Horde vendor blocks, and maps 100% of vendors/zones to UiMapID + (x, y) coordinates
for 3D Waypoint & Multi-Hop Portal Navigation.
"""

import csv
import io
import os
import re
import urllib.request

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(REPO_DIR, "MountVendorsDB.lua")


def fetch_csv(url: str) -> list[dict]:
    req = urllib.request.Request(url, headers={"User-Agent": "MountCollector-VendorBuilder/1.8"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return list(csv.DictReader(io.StringIO(r.read().decode("utf-8"))))


def esc(s: str) -> str:
    if not s:
        return ""
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\r", " ").replace("\n", " ").strip()


# Verified Quartermaster & Hub coordinates: vendorEN_lower -> (mapID, x, y)
VENDOR_COORDS = {
    # Classic Alliance
    "katie stokx": (84, 77.0, 67.8),
    "unger statforth": (56, 8.6, 54.4),
    "veron amberstill": (27, 70.6, 48.8),
    "milli featherwhistle": (27, 56.2, 46.2),
    "lelanai": (84, 52.2, 13.8),  # Stormwind Embassy (post-Teldrassil)
    "torallius the pack handler": (103, 81.6, 52.6),
    "tannec stonebeak": (84, 71.0, 72.4),
    "lieutenant karter": (84, 76.6, 65.8),
    "captain dirgehammer": (84, 76.6, 65.8),
    "old whitenose": (84, 67.8, 18.6),
    "turtlemaster odai": (85, 69.8, 41.0),
    "astrid langstrump": (84, 52.4, 13.4),
    "kall worthaton": (85, 36.6, 86.8),
    "ulaani": (84, 67.0, 33.6),
    "paul north": (84, 67.0, 33.6),
    "quackenbush": (84, 67.0, 33.6),
    "tiana nevermorn": (85, 70.6, 30.8),
    # Classic Horde
    "ogunaro wolfrunner": (85, 61.6, 35.6),
    "zjolnir": (1, 55.2, 75.6),
    "harb clawhoof": (7, 47.6, 58.0),
    "zachariah post": (18, 59.8, 52.6),
    "winaestra": (94, 61.0, 54.6),
    "drakma": (85, 48.0, 58.6),
    "raider bork": (85, 41.8, 73.0),
    # TBC
    "drake dealer hurlunk": (104, 65.6, 86.0),
    "grella": (108, 64.4, 66.2),
    "trader narasu": (107, 54.6, 75.2),
    "provisioner nasela": (107, 53.4, 36.8),
    "fedryen swiftspear": (102, 79.2, 63.8),
    # WotLK
    "mei francis": (125, 58.0, 42.4),
    "cielstrasza": (115, 59.8, 53.0),
    "lillehoff": (120, 66.2, 61.4),
    "hira snowdawn": (125, 51.0, 17.6),
    # Cataclysm
    "blacksmith abasi": (249, 54.0, 33.2),
    "quartermaster brazie": (244, 53.2, 81.6),
    "pogg": (245, 54.8, 80.6),
    # Mists of Pandaria
    "san redscale": (371, 56.6, 44.4),
    "gina mudclaw": (376, 53.2, 51.6),
    "nat pagle": (418, 68.4, 43.4),
    "jaluu the generous": (390, 84.2, 62.6),
    "tan shin tiao": (390, 82.2, 29.4),
    "rushi the fox": (388, 48.8, 70.4),
    "amber-smith zikk": (422, 55.0, 35.6),
    "sage whiteheart": (390, 84.6, 63.6),
    "sage lotusbloom": (390, 62.8, 23.2),
    "hiren loresong": (504, 64.6, 74.6),
    "vasarin redmorn": (504, 33.0, 32.6),
    "mistweaver ku": (554, 42.6, 54.6),
    "uncle bigpocket": (379, 65.4, 61.6),
    "kai featherfall": (390, 82.2, 34.0),
    # Legion
    "vindicator jaelaana": (830, 60.4, 51.4),
    "toraan the revered": (830, 56.6, 52.8),
    "conjurer margoss": (627, 41.0, 25.0),
    "xur'ios": (627, 48.8, 13.6),
    "arcano-crafter vuvril": (680, 36.8, 46.6),
    "the mad merchant": (627, 43.2, 47.4),
    # BfA
    "provisioner faryl": (895, 73.6, 24.8),
    "sister lilyana": (942, 59.2, 69.4),
    "quartermaster alcorn": (896, 37.8, 49.0),
    "natal'hakata": (862, 58.4, 44.4),
    "provisioner lija": (863, 39.0, 79.4),
    "hoarder jena": (864, 56.6, 49.8),
    "artisan okata": (1355, 37.8, 55.6),
    "finder pruc": (1355, 49.8, 62.2),
    "stolen royal vendorbot": (1462, 73.6, 36.6),
    "provisioner qorra": (1527, 55.0, 32.8),
    # Shadowlands
    "adjutant galos": (1533, 52.2, 47.0),
    "nalcorn talsen": (1536, 50.6, 53.4),
    "aithlyn": (1565, 48.6, 50.6),
    "mistress mihaela": (1525, 61.2, 63.8),
    "duchess mynx": (1961, 63.4, 23.4),
    "archivist roh-suir": (1961, 61.6, 21.8),
    "vilo": (1970, 34.8, 64.2),
    # Dragonflight
    "granpap whiskers": (2022, 47.6, 83.6),
    "cataloger jakes": (2022, 47.2, 82.6),
    "tatto": (2024, 13.8, 49.2),
    "quartermaster huseng": (2023, 60.4, 37.6),
    "provisioner aristta": (2025, 38.6, 46.0),
    "sorotis": (2025, 51.1, 56.6),
    "falara nightsong": (2025, 51.1, 56.6),
    "gill the drill": (2025, 51.1, 56.6),
    "baron silver": (2025, 51.1, 56.6),
    "warden krizzik": (2025, 51.1, 56.6),
    "unner": (2112, 58.0, 35.8),
    "brendormi": (2112, 35.4, 79.2),
    "mythressa": (2112, 38.0, 36.8),
    "nalksaa": (2133, 56.2, 56.8),
    "moonpriestess lasara": (2200, 50.2, 61.6),
    "moon priestess lasara": (2200, 50.2, 61.6),
    "elianna": (2200, 50.2, 61.8),
    "talisa whisperbloom": (2200, 49.8, 62.2),
    # The War Within
    "auditor balwurz": (2339, 39.2, 24.4),
    "sir finley mrrgglton": (2339, 47.6, 43.6),
    "torie": (2339, 34.3, 69.5),
    "cendvin": (2248, 74.4, 45.2),
    "waxmonger squick": (2214, 47.4, 32.8),
    "auralia steelstrike": (2215, 41.2, 53.0),
    "lars bronsmaelt": (2215, 28.4, 56.2),
    "lady vinazian": (2255, 56.6, 41.2),
    "y'tekhi": (2255, 55.3, 41.2),
    "soweezi": (2369, 70.0, 48.5),
    "boatswain hardee": (2346, 63.4, 16.8),
    "rocco razzboom": (2346, 42.8, 52.0),
    "shredz the scrapper": (2346, 53.3, 72.7),
    "sitch lowdown": (2346, 30.6, 38.8),
    "smaks topskimmer": (2346, 43.8, 50.8),
    "lab assistant laszly": (2346, 27.1, 72.5),
    "skedgit cinderbangs": (2346, 53.0, 72.6),
    "shad'anis": (2371, 50.4, 36.4),
    "om'sirik": (2371, 50.4, 36.4),
    # Midnight (12.x) — Verified neutral/accessible coordinates!
    "sergeant vornin": (2393, 48.6, 50.6),
    "construct v'anore": (2393, 55.8, 65.8),
    "construct e'nui": (2393, 55.8, 65.8),
    "telemancer astrandis": (2393, 52.5, 78.9),
    "estelia archtender": (2393, 39.3, 80.3),
    "lindormi": (2393, 52.6, 78.0),
    "caeris fairdawn": (2395, 43.4, 47.4),
    "magovu": (2437, 45.9, 65.9),
    "chel the chip": (2437, 31.6, 26.2),
    "skull of er'inye": (2437, 51.0, 62.6),
    "naynar": (2413, 51.0, 50.8),
    "showena": (2576, 61.8, 67.7),
    "void researcher anomander": (2405, 52.6, 72.8),
    "kifaan": (2599, 59.3, 19.5),
    "jan'sari the watchful": (2512, 58.8, 46.0),
    "second mate sluggs": (2512, 51.6, 49.8),
    "any timewalking vendor": (125, 50.2, 46.2),
    "lunar festival": (80, 53.6, 35.4),
    "guild vendors": (84, 64.8, 76.6),
    "world vendors": (84, 64.8, 76.6),
}

VENDOR_DEFAULT_ZONES = {
    "the mad merchant": ("Dalaran (Broken Isles)", "Даларан (Расколотые острова)"),
    "brendormi": ("Valdrakken", "Вальдраккен"),
    "mythressa": ("Valdrakken", "Вальдраккен"),
    "chel the chip": ("Zul'Aman (Abundance)", "Зул'Аман (Изобилие)"),
    "lindormi": ("Silvermoon City", "Луносвет"),
    "any timewalking vendor": ("Timewalking Hub (Dalaran / Shattrath / Timeless Isle)", "Столица Путешествий во времени (Даларан / Шаттрат)"),
    "lunar festival": ("Moonglade (Lunar Festival)", "Лунная поляна (Лунный фестиваль)"),
    "guild vendors": ("Stormwind City", "Штормград"),
    "world vendors": ("Stormwind City", "Штормград"),
}

# Explicit per-mount overrides when Mount.db2 omits Zone or Cost
MOUNT_OVERRIDES = {
    310: {
        "primary": {"vendorEN": "Ogunaro Wolfrunner", "vendorRU": "Огунаро Волкопас", "zoneEN": "Orgrimmar", "zoneRU": "Оргриммар", "mapID": 85, "x": 61.6, "y": 35.6, "side": "HORDE"},
    },
    401: {
        "primary": {"vendorEN": "Shay Pressler (Guild Vendor)", "vendorRU": "Шей Пресслер (гильдейский торговец)", "zoneEN": "Stormwind City", "zoneRU": "Штормград", "mapID": 84, "x": 64.8, "y": 76.6, "side": "ALLIANCE"},
        "alt": {"vendorEN": "Goram (Guild Vendor)", "vendorRU": "Горам (гильдейский торговец)", "zoneEN": "Orgrimmar", "zoneRU": "Оргриммар", "mapID": 85, "x": 48.2, "y": 75.6, "side": "HORDE"},
    },
    403: {
        "primary": {"vendorEN": "Shay Pressler (Guild Vendor)", "vendorRU": "Шей Пресслер (гильдейский торговец)", "zoneEN": "Stormwind City", "zoneRU": "Штормград", "mapID": 84, "x": 64.8, "y": 76.6, "side": "ALLIANCE"},
    },
    518: {"primary": {"vendorEN": "Kai Featherfall", "vendorRU": "Кай Осенний Лист", "zoneEN": "Vale of Eternal Blossoms", "zoneRU": "Вечноцветущий дол", "mapID": 390, "x": 82.2, "y": 34.0}},
    519: {"primary": {"vendorEN": "Kai Featherfall", "vendorRU": "Кай Осенний Лист", "zoneEN": "Vale of Eternal Blossoms", "zoneRU": "Вечноцветущий дол", "mapID": 390, "x": 82.2, "y": 34.0}},
    520: {"primary": {"vendorEN": "Kai Featherfall", "vendorRU": "Кай Осенний Лист", "zoneEN": "Vale of Eternal Blossoms", "zoneRU": "Вечноцветущий дол", "mapID": 390, "x": 82.2, "y": 34.0}},
    663: {
        "costs": [{"kind": "GOLD", "amount": 2000000}],
    },
    2327: {
        "primary": {"vendorEN": "Valadar Starsong (Lunar Festival)", "vendorRU": "Валадар Звездная Песня (Лунный фестиваль)", "zoneEN": "Moonglade", "zoneRU": "Лунная поляна", "mapID": 80, "x": 53.6, "y": 35.4},
        "costs": [{"kind": "ITEM", "id": 21100, "amount": 75}],
    },
}

# Fallback Zone -> (mapID, x, y)
ZONE_COORDS = {
    "stormwind city": (84, 65.0, 72.0),
    "stormwind, old town": (84, 76.6, 65.8),
    "orgrimmar": (85, 50.0, 60.0),
    "dun morogh": (27, 63.0, 48.0),
    "darnassus": (84, 52.2, 13.8),
    "durotar": (1, 55.2, 75.6),
    "mulgore": (7, 47.6, 58.0),
    "tirisfal glades": (18, 59.8, 52.6),
    "wetlands": (56, 8.6, 54.4),
    "hillsbrad foothills": (25, 45.0, 45.0),
    "booty bay": (210, 42.6, 72.8),
    "eversong woods (burning crusade)": (94, 61.0, 54.6),
    "the exodar": (103, 81.6, 52.6),
    "shadowmoon valley, outland": (104, 65.6, 86.0),
    "nagrand, outland": (107, 54.2, 75.0),
    "terokkar forest": (108, 64.4, 66.2),
    "zangarmarsh": (102, 79.2, 63.8),
    "shattrath city": (111, 50.0, 42.0),
    "dalaran": (125, 58.0, 42.4),
    "argent tournament, icecrown": (118, 76.2, 19.6),
    "icecrown": (118, 76.2, 19.6),
    "dragonblight": (115, 59.8, 53.0),
    "the storm peaks": (120, 66.2, 61.4),
    "sholazar basin": (119, 50.0, 62.0),
    "borean tundra": (114, 57.0, 62.0),
    "howling fjord": (117, 58.0, 62.0),
    "wintergrasp": (123, 50.0, 16.0),
    "uldum": (249, 54.0, 33.2),
    "tol barad peninsula": (245, 54.0, 80.0),
    "mount hyjal": (198, 62.0, 24.0),
    "twilight highlands": (241, 49.0, 29.0),
    "darkmoon island": (407, 48.6, 69.6),
    "the jade forest": (371, 56.6, 44.4),
    "valley of the four winds": (376, 53.2, 51.6),
    "krasarang wilds": (418, 68.4, 43.4),
    "kun-lai summit": (379, 65.4, 61.6),
    "townlong steppes": (388, 48.8, 70.4),
    "dread wastes": (422, 55.0, 35.6),
    "vale of eternal blossoms": (390, 82.0, 30.0),
    "isle of thunder": (504, 50.0, 50.0),
    "isle of giants": (507, 27.4, 58.0),
    "timeless isle": (554, 42.6, 54.6),
    "masters' perch": (379, 50.0, 42.0),
    "frostfire ridge": (525, 48.0, 65.0),
    "shadowmoon valley": (539, 30.0, 30.0),
    "spires of arak": (542, 46.0, 45.0),
    "nagrand": (550, 50.0, 50.0),
    "tanaan jungle": (534, 58.0, 59.0),
    "ashran": (588, 45.0, 50.0),
    "stormshield": (622, 47.0, 50.0),
    "warspear": (624, 53.0, 50.0),
    "stormshield / warspear": (622, 47.0, 50.0),
    "garrison trading post": (582, 50.0, 50.0),
    "horde garrison trading post": (590, 50.0, 50.0),
    "garrison: fishing shack": (582, 54.0, 72.0),
    "bizmo's brawlpub": (84, 67.0, 33.6),
    "brawl'gar arena": (85, 70.6, 30.8),
    "broken isles": (619, 50.0, 50.0),
    "azsuna": (630, 46.8, 41.4),
    "val'sharah": (641, 54.6, 73.2),
    "highmountain": (650, 46.4, 63.8),
    "stormheim": (634, 60.2, 50.8),
    "suramar": (680, 36.8, 46.6),
    "broken shore": (646, 44.6, 63.0),
    "argus": (830, 60.4, 51.4),
    "sanctum of light": (23, 75.8, 52.8),
    "boralus": (1161, 71.0, 25.0),
    "boralus harbor": (1161, 71.0, 25.0),
    "tiragarde sound": (895, 73.6, 24.8),
    "drustvar": (896, 37.8, 49.0),
    "stormsong valley": (942, 59.2, 69.4),
    "dazar'alor": (1165, 50.0, 50.0),
    "zuldazar": (862, 58.4, 44.4),
    "nazmir": (863, 39.0, 79.4),
    "vol'dun": (864, 56.6, 49.8),
    "arathi highlands": (14, 45.0, 50.0),
    "darkshore": (62, 48.0, 36.0),
    "nazjatar": (1355, 45.0, 58.0),
    "mechagon": (1462, 73.6, 36.6),
    "mechagon island": (1462, 73.6, 36.6),
    "oribos": (1670, 50.0, 50.0),
    "bastion": (1533, 52.2, 47.0),
    "maldraxxus": (1536, 50.6, 53.4),
    "ardenweald": (1565, 48.6, 50.6),
    "revendreth": (1525, 61.2, 63.8),
    "the maw": (1543, 46.8, 41.6),
    "korthia": (1961, 62.6, 22.6),
    "zereth mortis": (1970, 34.8, 64.2),
    "the waking shores": (2022, 47.6, 83.0),
    "dragonscale basecamp": (2022, 47.6, 83.0),
    "ohn'ahran plains": (2023, 60.4, 37.6),
    "the azure span": (2024, 13.8, 49.2),
    "iskaara": (2024, 13.8, 49.2),
    "thaldraszus": (2025, 50.0, 50.0),
    "valdrakken": (2112, 58.0, 35.8),
    "the forbidden reach": (2151, 34.2, 59.8),
    "zaralek cavern": (2133, 56.2, 56.8),
    "emerald dream": (2200, 50.2, 61.6),
    "dornogal": (2339, 44.0, 46.0),
    "isle of dorn": (2248, 44.0, 46.0),
    "the isle of dorn": (2248, 44.0, 46.0),
    "the ringing deeps": (2214, 47.4, 32.8),
    "hallowfall": (2215, 41.2, 53.0),
    "azj-kahet": (2255, 56.6, 41.2),
    "city of threads": (2213, 50.0, 42.0),
    "undermine": (2346, 43.4, 51.0),
    "liberation of undermine": (2346, 50.0, 50.0),
    "k'aresh": (2371, 50.0, 50.0),
    "silvermoon city": (2393, 48.6, 65.0),
    "eversong woods": (2395, 43.4, 47.4),
    "zul'aman": (2437, 45.9, 65.9),
    "harandar": (2413, 51.0, 50.8),
    "the den": (2576, 61.8, 67.7),
    "voidstorm": (2405, 52.6, 72.8),
    "val": (2599, 59.3, 19.5),
    "naigtal": (2600, 47.8, 81.2),
    "val and naigtal": (2599, 59.3, 19.5),
    "the coiled isle": (2512, 58.8, 46.0),
    "vaults of atal'utek": (2437, 51.0, 62.6),
}

ALLIANCE_FACTIONS = {47, 54, 69, 72, 930, 978, 1094, 1134, 1177, 1353, 1376, 1387, 1682, 1710, 1731, 1847, 2160, 2161, 2162, 2400, 2767}
HORDE_FACTIONS = {68, 76, 81, 530, 911, 941, 1124, 1133, 1178, 1352, 1375, 1388, 1445, 1681, 1708, 1848, 2103, 2156, 2158, 2373, 2766}

# Classic / TBC / Cata / MoP Racial City Mount Vendors:
# Free of reputation ONLY if player is of `freeRace`, otherwise requires Exalted (8) with that city faction!
RACIAL_VENDOR_GATES = {
    "katie stokx": (72, "Human"),
    "unger statforth": (72, "Human"),
    "veron amberstill": (47, "Dwarf"),
    "milli featherwhistle": (54, "Gnome"),
    "lelanai": (69, "NightElf"),
    "torallius the pack handler": (930, "Draenei"),
    "astrid langstrump": (1134, "Worgen"),
    "old whitenose": (1353, "Pandaren"),
    "ogunaro wolfrunner": (76, "Orc"),
    "zjolnir": (530, "Troll"),
    "harb clawhoof": (81, "Tauren"),
    "zachariah post": (68, "Scourge"),
    "winaestra": (911, "BloodElf"),
    "kall worthaton": (1133, "Goblin"),
    "turtlemaster odai": (1352, "Pandaren"),
}

COVENANT_MAP = {
    "kyrian": (1, "Kyrian Covenant", "Ковенант Кирий"),
    "venthyr": (2, "Venthyr Covenant", "Ковенант Вентиров"),
    "night fae": (3, "Night Fae Covenant", "Ковенант Ночного народца"),
    "necrolord": (4, "Necrolord Covenant", "Ковенант Некролордов"),
}
ALLIANCE_ZONES = {"stormwind city", "stormwind, old town", "dun morogh", "darnassus", "the exodar", "wetlands", "stormshield", "bizmo's brawlpub", "boralus", "boralus harbor", "tiragarde sound", "drustvar", "stormsong valley", "garrison trading post", "shadowmoon valley"}
HORDE_ZONES = {"orgrimmar", "durotar", "mulgore", "tirisfal glades", "warspear", "brawl'gar arena", "dazar'alor", "zuldazar", "nazmir", "vol'dun", "horde garrison trading post", "frostfire ridge"}

STANDING_MAP = {
    "friendly": 5,
    "honored": 6,
    "revered": 7,
    "exalted": 8,
}

EXPLICIT_FACTION_IDS = {
    "cenarion expedition": 942,
    "the mag'har": 941,
    "the kurenai": 978,
    "sha'tari skyguard": 1031,
    "netherwing": 1015,
    "the wyrmrest accord": 1091,
    "the sons of hodir": 1119,
    "the silver covenant": 1094,
    "the sunreavers": 1124,
    "baradin's wardens": 1177,
    "hellscream's reach": 1178,
    "ramkahen": 1173,
    "order of the cloud serpent": 1271,
    "golden lotus": 1269,
    "shado-pan": 1270,
    "the august celestials": 1341,
    "the klaxxi": 1337,
    "the anglers": 1302,
    "the tillers": 1272,
    "the lorewalkers": 1345,
    "nat pagle": 1358,
    "operation: shieldwall": 1376,
    "dominance offensive": 1375,
    "kirin tor offensive": 1387,
    "sunreaver onslaught": 1388,
    "emperor shaohao": 1492,
    "council of exarchs": 1731,
    "frostwolf orcs": 1445,
    "sha'tari defense": 1710,
    "laughing skull": 1708,
    "steamwheedle \"preservation\" society": 1711,
    "arakkoa outcasts": 1515,
    "wrynn's vanguard": 1682,
    "vol'jin's spear": 1681,
    "hand of the prophet": 1847,
    "vol'jin's headhunters": 1848,
    "order of the awakened": 1849,
    "the saberstalkers": 1850,
    "conjurer margoss": 1975,
    "army of the light": 2165,
    "argussian reach": 2170,
    "proudmoore admiralty": 2160,
    "order of embers": 2161,
    "storm's wake": 2162,
    "zandalari empire": 2103,
    "talanji's expedition": 2156,
    "voldunai": 2158,
    "ankoan": 2400,
    "waveblade ankoan": 2400,
    "unshackled": 2373,
    "the unshackled": 2373,
    "rustbolt resistance": 2391,
    "uldum accord": 2417,
    "rajani": 2415,
    "the ascended": 2407,
    "the undying army": 2410,
    "the wild hunt": 2465,
    "court of harvesters": 2413,
    "death's advance": 2470,
    "the archivists' codex": 2472,
    "the enlightened": 2478,
    "dragonscale expedition": 2507,
    "maruuk centaur": 2503,
    "iskaara tuskarr": 2511,
    "valdrakken accord": 2510,
    "loamm niffen": 2564,
    "dream wardens": 2574,
    "council of dornogal": 2590,
    "the assembly of the deeps": 2594,
    "hallowfall arathi": 2570,
    # Midnight (12.x)
    "amani tribe": 2696,
    "the singularity": 2699,
    "hara'ti": 2704,
    "the hara'ti": 2704,
    "silvermoon court": 2710,
    "delves: season 1": 2742,
    "delver's journey": 2742,
    "prey: season 1": 2764,
    "preyhunter's journey": 2808,
    "brawl'gar arena": 2766,
    "bizmo's brawlpub": 2767,
    "slayer's duellum": 2770,
    "zul'jarra's forces": 2772,
    "captain tokka": 2773,
    "ritual sites": 2792,
    "aqir research enclave": 2838,
}

# Explicit Reputation / Renown / Journey gates omitted by Blizzard from Mount.db2 SourceText_lang
MOUNT_REP_OVERRIDES = {
    # Argent Tournament Champion Quartermasters & Exalted City Mounts
    294: {"factionID": 72, "reqStanding": 8, "reqNoteEN": "Champion of Stormwind", "reqNoteRU": "Чемпион Штормграда (Серебряный турнир)"},
    295: {"factionID": 530, "reqStanding": 8, "reqNoteEN": "Champion of Sen'jin", "reqNoteRU": "Чемпион Сен'джина (Серебряный турнир)"},
    296: {"factionID": 47, "reqStanding": 8, "reqNoteEN": "Champion of Ironforge", "reqNoteRU": "Чемпион Стальгорна (Серебряный турнир)"},
    297: {"factionID": 69, "reqStanding": 8, "reqNoteEN": "Champion of Darnassus", "reqNoteRU": "Чемпион Дарнаса (Серебряный турнир)"},
    298: {"factionID": 54, "reqStanding": 8, "reqNoteEN": "Champion of Gnomeregan", "reqNoteRU": "Чемпион Гномрегана (Серебряный турнир)"},
    299: {"factionID": 930, "reqStanding": 8, "reqNoteEN": "Champion of the Exodar", "reqNoteRU": "Чемпион Экзодара (Серебряный турнир)"},
    300: {"factionID": 76, "reqStanding": 8, "reqNoteEN": "Champion of Orgrimmar", "reqNoteRU": "Чемпион Оргриммара (Серебряный турнир)"},
    301: {"factionID": 81, "reqStanding": 8, "reqNoteEN": "Champion of Thunder Bluff", "reqNoteRU": "Чемпион Громового Утеса (Серебряный турнир)"},
    302: {"factionID": 911, "reqStanding": 8, "reqNoteEN": "Champion of Silvermoon", "reqNoteRU": "Чемпион Луносвета (Серебряный турнир)"},
    303: {"factionID": 68, "reqStanding": 8, "reqNoteEN": "Champion of the Undercity", "reqNoteRU": "Чемпион Подгорода (Серебряный турнир)"},
    305: {"factionID": 1106, "reqStanding": 8},
    318: {"factionID": 930, "reqStanding": 8},
    319: {"factionID": 69, "reqStanding": 8},
    320: {"factionID": 911, "reqStanding": 8},
    321: {"factionID": 72, "reqStanding": 8},
    322: {"factionID": 81, "reqStanding": 8},
    323: {"factionID": 54, "reqStanding": 8},
    324: {"factionID": 47, "reqStanding": 8},
    325: {"factionID": 530, "reqStanding": 8},
    326: {"factionID": 68, "reqStanding": 8},
    327: {"factionID": 76, "reqStanding": 8},
    338: {"factionID": 1106, "reqStanding": 8, "reqNoteEN": "Crusader Title (Paladin)", "reqNoteRU": "Звание «Крестоносец» (Паладин)"},
    341: {"factionID": 1106, "reqStanding": 8, "reqNoteEN": "Exalted Champion of the Argent Crusade", "reqNoteRU": "Превозносимый чемпион Серебряного Авангарда"},
    # Guild Vendors & Brawler's Guild
    401: {"reqAchEN": "Guild Glory of the Cataclysm Raider", "reqAchRU": "Слава рейдеру Cataclysm (гильдия)"},
    403: {"reqAchEN": "Guild Level 25 / Exalted", "reqAchRU": "Превознесение в гильдии"},
    409: {"reqAchEN": "Guild Level 25 / Exalted", "reqAchRU": "Превознесение в гильдии"},
    466: {"reqAchEN": "Guild Glory of the Pandaria Raider", "reqAchRU": "Слава рейдеру Пандарии (гильдия)"},
    550: {"brawlersRank": 8},
    878: {"brawlersRank": 8},
    2807: {"brawlersRank": 6},
    2808: {"brawlersRank": 8},
    # Legion / Shadowlands / Dragonflight / K'aresh hidden gates
    877: {"factionID": 2018, "reqStanding": 8},
    1420: {"factionID": 2464, "reqStanding": 6},
    1429: {"factionID": 2463, "reqStanding": 6},
    1612: {"factionID": 2517, "reqStanding": 8, "reqNoteEN": "True Friend with Wrathion & Sabellian", "reqNoteRU": "Настоящий друг Гневиона и Сабеллиана"},
    1738: {"factionID": 2564, "reqRenown": 18},
    1809: {"factionID": 2574, "reqRenown": 17},
    1811: {"factionID": 2574, "reqRenown": 17},
    1837: {"factionID": 2574, "reqRenown": 5},
    1838: {"factionID": 2574, "reqRenown": 5},
    1839: {"factionID": 2574, "reqRenown": 5},
    1938: {"factionID": 2574, "reqRenown": 5},
    1939: {"factionID": 2574, "reqRenown": 5},
    1940: {"factionID": 2574, "reqRenown": 5},
    2510: {"factionID": 2658, "reqRenown": 19},
    2552: {"factionID": 2658, "reqRenown": 15},
    2556: {"factionID": 2658, "reqRenown": 19},
    2557: {"factionID": 2658, "reqRenown": 15},
    # The War Within Renown & Cartel Quartermasters (omitted in Mount.db2)
    2148: {"factionID": 2590, "reqRenown": 23},
    2213: {"factionID": 2590, "reqRenown": 18},
    2162: {"factionID": 2594, "reqRenown": 23},
    2209: {"factionID": 2594, "reqRenown": 19},
    2191: {"factionID": 2570, "reqRenown": 23},
    2193: {"factionID": 2570, "reqRenown": 21},
    2177: {"factionID": 2600, "reqRenown": 23},
    2184: {"factionID": 2600, "reqRenown": 22},
    2277: {"factionID": 2653, "reqRenown": 15},
    2280: {"factionID": 2653, "reqRenown": 19},
    2272: {"factionID": 2673, "reqStanding": 8},
    2286: {"factionID": 2675, "reqStanding": 8},
    2294: {"factionID": 2677, "reqStanding": 8},
    2284: {"factionID": 2692, "reqStanding": 8},
    2287: {"factionID": 2669, "reqStanding": 8},
    2519: {"factionID": 2688, "reqRenown": 9},
    # Midnight (12.x) Renown, Enclave, Delver's Journey & Preyhunter's Journey gates
    2614: {"factionID": 2704, "reqRenown": 16},
    2710: {"factionID": 2704, "reqRenown": 19},
    2694: {"factionID": 2696, "reqRenown": 19},
    2776: {"factionID": 2696, "reqRenown": 17},
    2753: {"factionID": 2710, "reqRenown": 19},
    2761: {"factionID": 2710, "reqRenown": 17},
    2789: {"factionID": 2699, "reqRenown": 17},
    2828: {"factionID": 2699, "reqRenown": 19},
    2769: {"factionID": 2764, "reqRenown": 5, "factionEN": "Preyseeker's Journey (S1)", "factionRU": "Путь загонщика (1-й сезон)"},
    2770: {"factionID": 2764, "reqRenown": 5, "factionEN": "Preyseeker's Journey (S1)", "factionRU": "Путь загонщика (1-й сезон)"},
    3032: {"factionID": 2808, "reqRenown": 10, "factionEN": "Preyseeker's Journey (S2)", "factionRU": "Путь загонщика (2-й сезон)"},
    2840: {"factionID": 2742, "reqRenown": 5, "factionEN": "Delver's Journey (S1)", "factionRU": "Путь участника вылазки (1-й сезон)"},
    3043: {"factionID": 2796, "reqRenown": 5, "factionEN": "Delver's Journey (S2)", "factionRU": "Путь участника вылазки (2-й сезон)"},
    2935: {"factionID": 2792, "reqRenown": 8},
    3019: {"factionID": 2773, "reqStanding": 8},
    3020: {"reqNoteEN": "Quest: Vaults of Atal'utek: Certain Doom", "reqNoteRU": "Квест: «Своды Атал'Утека: Верная погибель»"},
    3054: {"factionID": 2772, "reqRenown": 19},
    3060: {"factionID": 2772, "reqRenown": 17},
    3066: {"factionID": 2838, "reqStanding": 8},
}


ITEM_NAMES_FALLBACK = {
    21100: ("Coin of Ancestry", "Монета предков"),
    26044: ("Halaa Research Token", "Исследовательский жетон Халаа"),
    26045: ("Halaa Battle Token", "Боевой жетон Халаа"),
    49927: ("Love Token", "Знак любви"),
    90045: ("Ancestral Phoenix Egg", "Древнее яйцо феникса"),
    103533: ("Vicious Saddle", "Седло ярости"),
    117397: ("Nat's Lucky Coin", "Счастливая монета Ната"),
    124099: ("Blackfang Claw", "Коготь Черного Клыка"),
    137642: ("Mark of Honor", "Почетный знак"),
    138777: ("Drowned Mana", "Утопленная мана"),
    168802: ("Nazjatar Battle Commendation", "Боевой почетный знак Назжатара"),
    169780: ("Prismatic Manapearl", "Радужная манажемчужина"),
    169783: ("Prismatic Manapearl", "Радужная манажемчужина"),
    170100: ("Rubbery Flank", "Жилистая вырезка"),
    174230: ("Memento of Epoch Challenges", "Памятный знак испытаний эпох"),
    193053: ("Dream Infusion", "Настой Сна"),
    193633: ("Wildseed Root Grain", "Зерно корня дикого семени"),
    193696: ("Thunderous Downburst", "Грозовой шквал"),
    193708: ("Swoglet", "Маленький рогоплав"),
    195496: ("Charred Elemental Remains", "Обугленные останки элементаля"),
    195502: ("Terrible Talon", "Жуткий коготь"),
    201400: ("Tattered Wildercloth", "Изорванная дикая ткань"),
    201401: ("Iridescent Plume", "Переливчатое перо"),
    201403: ("Mastodon Tusk", "Бивень мастодонта"),
    202039: ("Storm Sigil", "Печать бури"),
    202173: ("Magmote", "Частица магмы"),
    204727: ("Coveted Bauble", "Желанная безделушка"),
    205188: ("Barter Brick", "Обменный кирпич"),
    207026: ("Dreamsurge Coalescence", "Сгусток Прилива Снов"),
    211376: ("Seedbloom", "Семяцвет"),
    211409: ("Dream Infusion", "Настой Сна"),
    225557: ("Sizzling Cinderpollen", "Шипящая пепельная пыльца"),
    234741: ("Miscellaneous Mechanica", "Разнородная механика"),
}


def parse_costs(src_en: str, src_ru: str, curr_en: dict, curr_ru: dict) -> list[dict]:
    costs = []
    cost_match = re.search(r"Cost:\s*(?:\|r)?([^\r\n]+?)(?:\|n|$)", src_en)
    if not cost_match:
        return costs
    cost_seg = cost_match.group(1)

    for gm in re.finditer(r"(\d[\d,\s]*)\s*\|TINTERFACE[\\/]MONEYFRAME[\\/]UI-GOLDICON\.BLP", cost_seg, flags=re.I):
        amt = int(re.sub(r"[^\d]", "", gm.group(1)) or "0")
        if amt > 0:
            costs.append({"kind": "GOLD", "amount": amt})

    for cm in re.finditer(r"(\d[\d,\s]*)\s*\|Hcurrency:(\d+)\|h(?:\|T([^:|]+))?", cost_seg, flags=re.I):
        amt = int(re.sub(r"[^\d]", "", cm.group(1)) or "0")
        cid = int(cm.group(2))
        c_en = curr_en.get(cid, {}).get("Name_lang", f"Currency #{cid}")
        c_ru = curr_ru.get(cid, {}).get("Name_lang", c_en)
        costs.append({"kind": "CURRENCY", "id": cid, "amount": amt, "nameEN": c_en, "nameRU": c_ru})

    for im in re.finditer(r"(\d[\d,\s]*)\s*\|Hitem:(\d+)\|h", cost_seg, flags=re.I):
        amt = int(re.sub(r"[^\d]", "", im.group(1)) or "0")
        iid = int(im.group(2))
        fb_en, fb_ru = ITEM_NAMES_FALLBACK.get(iid, ("", ""))
        costs.append({"kind": "ITEM", "id": iid, "amount": amt, "nameEN": fb_en, "nameRU": fb_ru})

    return costs


def parse_block(block_en: str, block_ru: str, fac_by_name: dict, fac_ru_by_id: dict, map_by_name: dict):
    v_en_m = re.search(r"Vendor:\s*\|r([^\|\r\n]+)", block_en)
    v_ru_m = re.search(r"Торговец:\s*\|r([^\|\r\n]+)", block_ru)
    z_en_m = re.search(r"(?:Zone|Location)s?:\s*\|r([^\|\r\n]+)", block_en)
    z_ru_m = re.search(r"(?:Зона|Зоны|Местонахождение):\s*\|r([^\|\r\n]+)", block_ru)

    vendor_en = (v_en_m.group(1).strip() if v_en_m else "")
    vendor_ru = (v_ru_m.group(1).strip() if v_ru_m else vendor_en)
    zone_en = (z_en_m.group(1).strip() if z_en_m else "")
    zone_ru = (z_ru_m.group(1).strip() if z_ru_m else zone_en)

    v_low = vendor_en.lower()
    if not zone_en and v_low in VENDOR_DEFAULT_ZONES:
        zone_en, zone_ru = VENDOR_DEFAULT_ZONES[v_low]

    map_id, x, y = 0, 50.0, 50.0
    z_low = zone_en.lower()
    if v_low == "kifaan" and z_low in ZONE_COORDS:
        map_id, x, y = ZONE_COORDS[z_low]
    elif v_low in VENDOR_COORDS:
        map_id, x, y = VENDOR_COORDS[v_low]
    elif z_low in ZONE_COORDS:
        map_id, x, y = ZONE_COORDS[z_low]
    elif z_low.split(",")[0].strip() in ZONE_COORDS:
        map_id, x, y = ZONE_COORDS[z_low.split(",")[0].strip()]
    elif z_low in map_by_name:
        map_id = map_by_name[z_low]

    fac_id = 0
    fac_en = ""
    fac_ru = ""
    req_standing = 0
    req_renown = 0
    req_note_en = ""
    req_note_ru = ""

    f_en_m = re.search(r"(?:Faction|Reputation):\s*\|r([^\|\r\n]+)", block_en)
    f_ru_m = re.search(r"(?:Фракция|Репутация):\s*\|r([^\|\r\n]+)", block_ru)
    r_en_m = re.search(r"Renown:\s*\|r([^\|\r\n]+)", block_en)
    r_ru_m = re.search(r"Известность:\s*\|r([^\|\r\n]+)", block_ru)

    if f_en_m:
        raw_f = f_en_m.group(1).strip()
        raw_f_ru = f_ru_m.group(1).strip() if f_ru_m else raw_f
        if " - " in raw_f:
            f_part, st_part = [p.strip() for p in raw_f.split(" - ", 1)]
            fac_en = f_part
            st_low = st_part.lower()
            if st_low in STANDING_MAP:
                req_standing = STANDING_MAP[st_low]
            else:
                req_note_en = raw_f
                req_note_ru = raw_f_ru
        else:
            fac_en = raw_f
            if "(" in raw_f:
                req_note_en = raw_f
                req_note_ru = raw_f_ru

        f_key = fac_en.lower()
        fac_id = EXPLICIT_FACTION_IDS.get(f_key, fac_by_name.get(f_key, 0))
        if fac_id and fac_id in fac_ru_by_id:
            fac_ru = fac_ru_by_id[fac_id]
        elif f_ru_m:
            fac_ru = re.split(r"\s*[–—-]\s*", raw_f_ru)[0].strip()

    if r_en_m:
        raw_r = r_en_m.group(1).strip()
        raw_r_ru = r_ru_m.group(1).strip() if r_ru_m else raw_r
        rn_num = re.search(r"(\d+)", raw_r)
        if rn_num:
            req_renown = int(rn_num.group(1))
        if not fac_en:
            fac_part = re.sub(r"\s*Rank\s*\d+.*", "", raw_r, flags=re.I).strip()
            if fac_part and not fac_part.isdigit():
                fac_en = fac_part
                fac_id = EXPLICIT_FACTION_IDS.get(fac_en.lower(), fac_by_name.get(fac_en.lower(), 0))
                fac_ru = fac_ru_by_id.get(fac_id, re.sub(r"\s*\d+.*", "", raw_r_ru).strip())

    free_race = ""
    if fac_id == 0 and v_low in RACIAL_VENDOR_GATES:
        fac_id, free_race = RACIAL_VENDOR_GATES[v_low]
        req_standing = 8
        fac_en = next((k for k, v in fac_by_name.items() if v == fac_id), "")
        fac_ru = fac_ru_by_id.get(fac_id, fac_en)

    cov_id = 0
    cov_en = ""
    cov_ru = ""
    c_m = re.search(r"Covenant:\s*\|r([^\|\r\n]+)", block_en)
    if c_m:
        c_key = c_m.group(1).strip().lower()
        if c_key in COVENANT_MAP:
            cov_id, cov_en, cov_ru = COVENANT_MAP[c_key]

    if v_low == "landro longshot" and not req_note_en:
        req_note_en = "TCG Loot Card Code"
        req_note_ru = "Промо-код карты TCG"

    side = ""
    if fac_id in ALLIANCE_FACTIONS or z_low in ALLIANCE_ZONES:
        side = "ALLIANCE"
    elif fac_id in HORDE_FACTIONS or z_low in HORDE_ZONES:
        side = "HORDE"

    return {
        "vendorEN": vendor_en,
        "vendorRU": vendor_ru,
        "zoneEN": zone_en,
        "zoneRU": zone_ru,
        "mapID": map_id,
        "x": x,
        "y": y,
        "factionID": fac_id,
        "factionEN": fac_en,
        "factionRU": fac_ru,
        "reqStanding": req_standing,
        "reqRenown": req_renown,
        "reqNoteEN": req_note_en,
        "reqNoteRU": req_note_ru,
        "freeRace": free_race,
        "reqCovID": cov_id,
        "reqCovEN": cov_en,
        "reqCovRU": cov_ru,
        "side": side,
    }


def main():
    mounts_en = fetch_csv("https://wago.tools/db2/Mount/csv")
    mounts_ru = {int(r["ID"]): r for r in fetch_csv("https://wago.tools/db2/Mount/csv?locale=ruRU")}
    factions_en = fetch_csv("https://wago.tools/db2/Faction/csv")
    factions_ru = {int(r["ID"]): r for r in fetch_csv("https://wago.tools/db2/Faction/csv?locale=ruRU")}
    curr_en = {int(r["ID"]): r for r in fetch_csv("https://wago.tools/db2/CurrencyTypes/csv")}
    curr_ru = {int(r["ID"]): r for r in fetch_csv("https://wago.tools/db2/CurrencyTypes/csv?locale=ruRU")}
    maps_en = fetch_csv("https://wago.tools/db2/UiMap/csv")
    achs_en = fetch_csv("https://wago.tools/db2/Achievement/csv")
    achs_ru = {int(r["ID"]): r for r in fetch_csv("https://wago.tools/db2/Achievement/csv?locale=ruRU")}

    ach_by_name = {}
    for a in achs_en:
        t = (a.get("Title_lang") or "").strip()
        if t and t.lower() not in ach_by_name:
            ach_by_name[t.lower()] = int(a["ID"])
    ach_ru_by_id = {aid: (r.get("Title_lang") or "").strip() for aid, r in achs_ru.items()}

    fac_en_by_id = {int(f["ID"]): (f.get("Name_lang") or "").strip() for f in factions_en}

    fac_by_name = {}
    for f in factions_en:
        nm = (f.get("Name_lang") or "").strip()
        if nm and nm.lower() not in fac_by_name:
            fac_by_name[nm.lower()] = int(f["ID"])
    fac_ru_by_id = {fid: (r.get("Name_lang") or "").strip() for fid, r in factions_ru.items()}

    map_by_name = {}
    for m in maps_en:
        nm = (m.get("Name_lang") or "").strip()
        mtype = int(m.get("Type", 0) or 0)
        if nm:
            low = nm.lower()
            if low not in map_by_name or mtype == 3:
                map_by_name[low] = int(m["ID"])

    entries = []
    for r in mounts_en:
        mid = int(r["ID"])
        spell_id = int(r.get("SourceSpellID", 0) or 0)
        src_en = (r.get("SourceText_lang") or "").strip()
        if "Vendor:" not in src_en and "Vendor :" not in src_en:
            continue
        if "|cFFFFD200Legacy" in src_en:
            continue

        r_ru = mounts_ru.get(mid, {})
        src_ru = (r_ru.get("SourceText_lang") or src_en).strip()

        blocks_en = [b.strip() for b in re.split(r"\|n\|n+", src_en) if "Vendor:" in b or "Vendor :" in b]
        blocks_ru = [b.strip() for b in re.split(r"\|n\|n+", src_ru) if "Торговец:" in b or "Vendor:" in b]
        if not blocks_en:
            blocks_en = [src_en]
        if not blocks_ru:
            blocks_ru = [src_ru]

        primary = parse_block(blocks_en[0], blocks_ru[0], fac_by_name, fac_ru_by_id, map_by_name)
        alt = None
        if len(blocks_en) >= 2:
            alt = parse_block(blocks_en[1], blocks_ru[1] if len(blocks_ru) >= 2 else blocks_ru[0], fac_by_name, fac_ru_by_id, map_by_name)
            if not primary["reqNoteEN"] and alt["reqNoteEN"]:
                primary["reqNoteEN"] = alt["reqNoteEN"]
                primary["reqNoteRU"] = alt["reqNoteRU"]
            if not primary["factionID"] and alt["factionID"]:
                primary["factionID"] = alt["factionID"]
                primary["factionEN"] = alt["factionEN"]
                primary["factionRU"] = alt["factionRU"]
                primary["reqStanding"] = alt["reqStanding"]
                primary["reqRenown"] = alt["reqRenown"]

        # Fallback: check full src_en for trailing Faction/Reputation/Renown/Covenant paragraphs outside Vendor blocks
        full_meta = parse_block(src_en, src_ru, fac_by_name, fac_ru_by_id, map_by_name)
        for target_b in ([primary, alt] if alt else [primary]):
            if not target_b["factionID"] and full_meta["factionID"]:
                target_b["factionID"] = full_meta["factionID"]
                target_b["factionEN"] = full_meta["factionEN"]
                target_b["factionRU"] = full_meta["factionRU"]
                target_b["reqStanding"] = full_meta["reqStanding"]
                target_b["reqRenown"] = full_meta["reqRenown"]
            if not target_b["reqNoteEN"] and full_meta["reqNoteEN"]:
                target_b["reqNoteEN"] = full_meta["reqNoteEN"]
                target_b["reqNoteRU"] = full_meta["reqNoteRU"]
            if not target_b["reqCovID"] and full_meta["reqCovID"]:
                target_b["reqCovID"] = full_meta["reqCovID"]
                target_b["reqCovEN"] = full_meta["reqCovEN"]
                target_b["reqCovRU"] = full_meta["reqCovRU"]

        # Parse Achievement requirement from full SourceText_lang if present
        ach_m = re.search(r"Achievement:\s*\|r([^\|\r\n]+)", src_en)
        ach_ru_m = re.search(r"Достижение:\s*\|r([^\|\r\n]+)", src_ru)
        if ach_m:
            ach_en_str = ach_m.group(1).strip()
            ach_id = ach_by_name.get(ach_en_str.lower(), 0)
            ach_ru_str = ach_ru_by_id.get(ach_id) or (ach_ru_m.group(1).strip() if ach_ru_m else ach_en_str)
            primary["reqAchID"] = ach_id
            primary["reqAchEN"] = ach_en_str
            primary["reqAchRU"] = ach_ru_str
            if alt:
                alt["reqAchID"] = ach_id
                alt["reqAchEN"] = ach_en_str
                alt["reqAchRU"] = ach_ru_str

        # Apply verified Reputation / Renown / Achievement gates omitted in Mount.db2
        rep_ovr = MOUNT_REP_OVERRIDES.get(mid)
        if rep_ovr:
            if "brawlersRank" in rep_ovr:
                rnk = rep_ovr["brawlersRank"]
                for target_b in ([primary, alt] if alt else [primary]):
                    is_horde = (target_b.get("side") == "HORDE") or ("brawl'gar" in target_b["zoneEN"].lower())
                    bfid = 2766 if is_horde else 2767
                    target_b["factionID"] = bfid
                    target_b["factionEN"] = fac_en_by_id.get(bfid, "Brawler's Guild")
                    target_b["factionRU"] = fac_ru_by_id.get(bfid, "Бойцовская гильдия")
                    target_b["reqRenown"] = rnk
                    target_b["reqNoteEN"] = ""
                    target_b["reqNoteRU"] = ""
            for target_b in ([primary, alt] if alt else [primary]):
                if "factionID" in rep_ovr:
                    fid = rep_ovr["factionID"]
                    target_b["factionID"] = fid
                    target_b["factionEN"] = rep_ovr.get("factionEN") or fac_en_by_id.get(fid, "")
                    target_b["factionRU"] = rep_ovr.get("factionRU") or fac_ru_by_id.get(fid, target_b["factionEN"])
                if "reqStanding" in rep_ovr:
                    target_b["reqStanding"] = rep_ovr["reqStanding"]
                if "reqRenown" in rep_ovr:
                    target_b["reqRenown"] = rep_ovr["reqRenown"]
                if "reqNoteEN" in rep_ovr:
                    target_b["reqNoteEN"] = rep_ovr["reqNoteEN"]
                    target_b["reqNoteRU"] = rep_ovr.get("reqNoteRU", rep_ovr["reqNoteEN"])
                if "reqAchEN" in rep_ovr:
                    a_en = rep_ovr["reqAchEN"]
                    a_id = ach_by_name.get(a_en.lower(), 0)
                    target_b["reqAchID"] = a_id
                    target_b["reqAchEN"] = a_en
                    target_b["reqAchRU"] = rep_ovr.get("reqAchRU") or ach_ru_by_id.get(a_id, a_en)

        costs = parse_costs(src_en, src_ru, curr_en, curr_ru)

        ovr = MOUNT_OVERRIDES.get(mid)
        if ovr:
            if "primary" in ovr:
                primary.update(ovr["primary"])
            if "alt" in ovr:
                if alt is None:
                    alt = dict(primary)
                alt.update(ovr["alt"])
            if "costs" in ovr:
                costs = []
                for oc in ovr["costs"]:
                    if oc["kind"] == "ITEM":
                        fb_en, fb_ru = ITEM_NAMES_FALLBACK.get(oc["id"], ("", ""))
                        oc = dict(oc, nameEN=fb_en, nameRU=fb_ru)
                    costs.append(oc)

        entries.append((mid, spell_id, primary, alt, costs))

    entries.sort(key=lambda x: x[0])

    out = [
        "local _, addon = ...",
        "",
        "-- ============================================================================",
        "-- MountCollector — MountVendorsDB.lua",
        "-- Авто-генерируемая верифицированная база покупаемых у торговцев маунтов",
        "-- из официальных таблиц Mount.db2, Faction.db2, CurrencyTypes.db2 и UiMap.db2.",
        "-- Поддерживает проверку живого баланса золота, валют (C_CurrencyInfo), предметов",
        "-- в сумках/банке отряда, репутации/Известности (Renown) и 3D-маршрут к торговцу!",
        "-- ============================================================================",
        "",
        "addon.MountVendorsDB = {",
    ]

    def fmt_block(b: dict) -> str:
        parts = [
            f'vendorRU="{esc(b["vendorRU"])}"',
            f'vendorEN="{esc(b["vendorEN"])}"',
            f'zoneRU="{esc(b["zoneRU"])}"',
            f'zoneEN="{esc(b["zoneEN"])}"',
            f'mapID={b["mapID"]}',
            f'x={b["x"]}',
            f'y={b["y"]}',
        ]
        if b.get("side"):
            parts.append(f'side="{b["side"]}"')
        if b.get("freeRace"):
            parts.append(f'freeRace="{b["freeRace"]}"')
        if b.get("reqCovID", 0) > 0:
            parts.append(f'reqCovID={b["reqCovID"]}')
            parts.append(f'reqCovRU="{esc(b["reqCovRU"])}"')
            parts.append(f'reqCovEN="{esc(b["reqCovEN"])}"')
        if b["factionID"] > 0:
            if not b["factionEN"] and b["factionID"] in fac_en_by_id:
                b["factionEN"] = fac_en_by_id[b["factionID"]]
            parts.append(f'factionID={b["factionID"]}')
            parts.append(f'factionRU="{esc(b["factionRU"])}"')
            parts.append(f'factionEN="{esc(b["factionEN"])}"')
        if b["reqStanding"] > 0:
            parts.append(f'reqStanding={b["reqStanding"]}')
        if b["reqRenown"] > 0:
            parts.append(f'reqRenown={b["reqRenown"]}')
        if b["reqNoteEN"]:
            parts.append(f'reqNoteRU="{esc(b["reqNoteRU"])}"')
            parts.append(f'reqNoteEN="{esc(b["reqNoteEN"])}"')
        if b.get("reqAchEN"):
            if b.get("reqAchID", 0) > 0:
                parts.append(f'reqAchID={b["reqAchID"]}')
            parts.append(f'reqAchRU="{esc(b["reqAchRU"])}"')
            parts.append(f'reqAchEN="{esc(b["reqAchEN"])}"')
        return "{ " + ", ".join(parts) + " }"

    with_coords = 0
    for mid, sp, prim, alt, costs in entries:
        if prim["mapID"] > 0:
            with_coords += 1
        cost_parts = []
        for c in costs:
            if c["kind"] == "GOLD":
                cost_parts.append(f'{{ kind="GOLD", amount={c["amount"]} }}')
            elif c["kind"] == "CURRENCY":
                cost_parts.append(
                    f'{{ kind="CURRENCY", id={c["id"]}, amount={c["amount"]}, nameRU="{esc(c["nameRU"])}", nameEN="{esc(c["nameEN"])}" }}'
                )
            elif c["kind"] == "ITEM":
                n_extra = f', nameRU="{esc(c.get("nameRU",""))}", nameEN="{esc(c.get("nameEN",""))}"' if c.get("nameEN") else ""
                cost_parts.append(f'{{ kind="ITEM", id={c["id"]}, amount={c["amount"]}{n_extra} }}')
        costs_lua = "{ " + ", ".join(cost_parts) + " }"
        alt_lua = f", alt={fmt_block(alt)}" if alt else ""
        out.append(f"    {{ mountID={mid}, spellID={sp}, primary={fmt_block(prim)}{alt_lua}, costs={costs_lua} }},")

    out.append("}")
    out.append("")

    with open(OUT_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))

    print(f"Generated {OUT_PATH}: {len(entries)} vendor mounts ({with_coords}/{len(entries)} with resolved mapID)!")


if __name__ == "__main__":
    main()
