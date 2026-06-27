#!/usr/bin/env python3
"""
Reads TARGET_CITIES and TARGET_VERTICALS from .env and generates
one Apify Google Maps input JSON per city × vertical combination.

Output: scripts/apify_inputs/{city_slug}_{vertical_slug}.json

NOTE — Airtable category field:
  The 'category' column that receives Google Maps categoryName must be
  a "Single line text" field in Airtable, NOT a "Single select".
  Single-select fields restrict values to predefined options and will
  reject new verticals. Change the field type in Airtable if needed.
"""
import json
import os
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
ROOT_DIR = SCRIPT_DIR.parent
INPUTS_DIR = SCRIPT_DIR / "apify_inputs"

MAX_CRAWLED_PER_SEARCH = 200


def load_env(env_path: Path) -> dict:
    env: dict = {}
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, rest = line.partition("=")
            key = key.strip()
            rest = rest.strip()
            # Extract quoted value — stop at the closing quote, ignoring inline comments
            if rest.startswith("'"):
                end = rest.find("'", 1)
                value = rest[1:end] if end != -1 else rest[1:]
            elif rest.startswith('"'):
                end = rest.find('"', 1)
                value = rest[1:end] if end != -1 else rest[1:]
            else:
                # Unquoted — strip inline comment
                value = rest.split("#")[0].strip()
            env[key] = value
    return env


def slugify(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def build_search_strings(vertical: str, city: str) -> list:
    v = vertical.strip()
    c = city.strip()
    return [
        f"{v} in {c}",
        f"{v} near {c}",
        f"best {v} in {c}",
        f"local {v} {c}",
        f"{v} services {c}",
    ]


def main() -> None:
    env_path = ROOT_DIR / ".env"
    if not env_path.exists():
        print(f"ERROR: .env not found at {env_path}", file=sys.stderr)
        sys.exit(1)

    env = load_env(env_path)

    cities_raw = env.get("TARGET_CITIES", "").strip()
    verticals_raw = env.get("TARGET_VERTICALS", "").strip()

    if not cities_raw:
        print("ERROR: TARGET_CITIES is not set in .env", file=sys.stderr)
        sys.exit(1)
    if not verticals_raw:
        print("ERROR: TARGET_VERTICALS is not set in .env", file=sys.stderr)
        sys.exit(1)

    cities = [c.strip() for c in cities_raw.split(",") if c.strip()]
    verticals = [v.strip() for v in verticals_raw.split(",") if v.strip()]

    INPUTS_DIR.mkdir(parents=True, exist_ok=True)

    # Remove previously generated files so stale city/vertical combos don't linger
    removed = 0
    for existing in sorted(INPUTS_DIR.glob("*.json")):
        existing.unlink()
        removed += 1
    if removed:
        print(f"Removed {removed} existing input file(s).\n")

    generated = []
    for city in cities:
        city_slug = slugify(city)
        for vertical in verticals:
            vertical_slug = slugify(vertical)
            filename = f"{city_slug}_{vertical_slug}.json"
            output_path = INPUTS_DIR / filename

            payload = {
                "searchStringsArray": build_search_strings(vertical, city),
                "maxCrawledPlacesPerSearch": MAX_CRAWLED_PER_SEARCH,
                "language": "en",
                "exportPlaceUrls": False,
                "additionalInfo": False,
                "maxReviews": 0,
                "proxyConfiguration": {
                    "useApifyProxy": True,
                    "apifyProxyGroups": ["RESIDENTIAL"],
                },
            }

            output_path.write_text(json.dumps(payload, indent=2) + "\n")
            generated.append(filename)
            print(f"  Generated: {filename}")

    print(f"\nDone. {len(generated)} file(s) written to: {INPUTS_DIR}")
    print(f"  Cities   ({len(cities)}): {', '.join(cities)}")
    print(f"  Verticals ({len(verticals)}): {', '.join(verticals)}")


if __name__ == "__main__":
    main()
