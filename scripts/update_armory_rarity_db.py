#!/usr/bin/env python3
"""
MountCollector — Armory / Data for Azeroth Rarity DB Updater
Fetches the latest MountsRarity-2.0 database from upstream (sgade/MountsRarity),
which aggregates Battle.net Armory mount ownership statistics from Data for Azeroth,
updates Libs/MountsRarity-2.0.lua in the repository, and syncs to the local WoW client
if installed.
"""

import os
import re
import shutil
import sys
import urllib.request

UPSTREAM_URL = "https://raw.githubusercontent.com/sgade/MountsRarity/main/MountsRarity.lua"
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB_PATH = os.path.join(REPO_ROOT, "Libs", "MountsRarity-2.0.lua")
WOW_CLIENT_LIB_PATH = r"C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\MountCollector\Libs\MountsRarity-2.0.lua"


def parse_db(text: str):
    minor_match = re.search(r"local\s+MINOR\s*=\s*(\d+)", text)
    updated_match = re.search(r"local\s+LAST_UPDATED\s*=\s*(\d+)", text)
    minor = int(minor_match.group(1)) if minor_match else 0
    last_updated = int(updated_match.group(1)) if updated_match else 0
    entries = dict(re.findall(r"\[(\d+)\]\s*=\s*([0-9.]+)", text))
    return minor, last_updated, entries


def main() -> int:
    if not os.path.exists(LIB_PATH):
        print(f"[ERROR] Local library not found: {LIB_PATH}", file=sys.stderr)
        return 1

    with open(LIB_PATH, "r", encoding="utf-8") as f:
        old_text = f.read()

    old_minor, _, old_entries = parse_db(old_text)

    req = urllib.request.Request(
        UPSTREAM_URL,
        headers={"User-Agent": "MountCollector-RarityUpdater/1.4"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        new_text = resp.read().decode("utf-8")

    new_minor, new_updated, new_entries = parse_db(new_text)
    if new_minor <= 0 or len(new_entries) < 1000:
        print(f"[ERROR] Invalid upstream data (MINOR={new_minor}, entries={len(new_entries)})", file=sys.stderr)
        return 1

    added_ids = sorted(int(k) for k in (set(new_entries.keys()) - set(old_entries.keys())))
    changed_count = sum(1 for k, v in new_entries.items() if k in old_entries and old_entries[k] != v)

    print(f"Current MINOR : {old_minor} ({len(old_entries)} mounts)")
    print(f"Upstream MINOR: {new_minor} ({len(new_entries)} mounts, LAST_UPDATED={new_updated})")

    if new_minor <= old_minor and changed_count == 0 and not added_ids:
        print("Status        : Already up to date.")
        if os.path.exists(os.path.dirname(WOW_CLIENT_LIB_PATH)):
            shutil.copy2(LIB_PATH, WOW_CLIENT_LIB_PATH)
        return 0

    with open(LIB_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write(new_text)

    print(f"Updated       : {changed_count} mount rarity % entries changed, {len(added_ids)} new mount(s) added {added_ids}")

    if os.path.exists(os.path.dirname(WOW_CLIENT_LIB_PATH)):
        shutil.copy2(LIB_PATH, WOW_CLIENT_LIB_PATH)
        print(f"Synced to WoW : {WOW_CLIENT_LIB_PATH}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
