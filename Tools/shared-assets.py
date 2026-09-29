#!/usr/bin/env python3
"""Works out which image assets the Messages extension can ask for at runtime.

The extension and the app used to compile the same 90MB asset catalog, so every
install carried the art twice. Only a fraction of it is reachable from the
sheet, but "reachable" includes things chosen at runtime — the rival's avatar
and either captain's fleet skin arrive in the message payload and can be
anything — so the set is derived rather than eyeballed. Run it to regenerate or
to check the split:  python3 Tools/shared-assets.py [--check]
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_CATALOG = os.path.join(ROOT, "TubPirates/Assets.xcassets")
SHARED_CATALOG = os.path.join(ROOT, "SharedGameAssets.xcassets")

# Code whose asset references can be reached from the Messages sheet.
SOURCE_DIRS = [
    "TubPiratesMessages",
    "Packages/BathtubEngine/Sources/BathtubArena",
    "Packages/BathtubEngine/Sources/BathtubUI",
]

FLEET_INFIXES = [None, "duck", "sea", "gild"]   # FleetSkin.all
SHIP_SIZES = ["2", "3a", "3b", "4", "5"]        # one per ShipKind


def literals() -> set[str]:
    """Every bare string literal in the reachable sources.

    Over-collects on purpose: it is filtered against the catalog below, so a
    non-asset string simply drops out, while a missed asset would be a blank
    square on somebody's phone.
    """
    found = set()
    for directory in SOURCE_DIRS:
        base = os.path.join(ROOT, directory)
        for entry in sorted(os.listdir(base)):
            if not entry.endswith(".swift"):
                continue
            text = open(os.path.join(base, entry)).read()
            found |= set(re.findall(r'"([a-z0-9_]{3,})"', text))
    return found


def runtime_chosen() -> set[str]:
    """Assets picked from data rather than named in code."""
    names = set()
    # Either captain's fleet skin rides in the payload.
    for infix in FLEET_INFIXES:
        for size in SHIP_SIZES:
            names.add(f"ship_{size}" if infix is None else f"ship_{infix}_{size}")
    # The rival's avatar likewise. Every purchasable avatar, plus the captain
    # portraits, since a profile can carry one.
    avatar_file = open(os.path.join(ROOT, "TubPirates/Profile/Avatar.swift")).read()
    names |= set(re.findall(r'Avatar\(id: "([a-z0-9_]+)"', avatar_file))
    names |= {"portrait_player", "portrait_dogbeard", "portrait_sal",
              "portrait_bess", "portrait_bubbles"}
    return names


def imagesets(catalog: str) -> set[str]:
    if not os.path.isdir(catalog):
        return set()
    return {d[: -len(".imageset")] for d in os.listdir(catalog) if d.endswith(".imageset")}


def required() -> set[str]:
    available = imagesets(APP_CATALOG) | imagesets(SHARED_CATALOG)
    return (literals() | runtime_chosen()) & available


def main() -> int:
    need = required()
    have = imagesets(SHARED_CATALOG)
    if "--check" in sys.argv:
        missing = sorted(need - have)
        extra = sorted(have - need)
        for name in missing:
            print(f"MISSING from shared catalog: {name}")
        for name in extra:
            print(f"unused in shared catalog: {name}")
        if missing:
            print(f"FAIL {len(missing)} asset(s) the extension can request are app-only")
            return 1
        print(f"OK {len(have)} shared assets, none missing")
        return 0
    for name in sorted(need):
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
