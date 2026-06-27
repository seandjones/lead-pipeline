#!/usr/bin/env python3
"""
Reads TARGET_CITIES_RE from .env and generates one Apify Google Maps input JSON
per city targeting "real estate agents".

Output: scripts/re_apify_inputs/{city_slug}_real_estate_agents.json

NOTE — This is a separate script from generate_apify_inputs.py to keep the two
verticals' input sets independent. Cleaning re_apify_inputs/ won't affect the
original apify_inputs/ and vice-versa.
"""
import json
import os
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
ROOT_DIR = SCRIPT_DIR.parent
INPUTS_DIR = SCRIPT_DIR / "re_apify_inputs"

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
            if rest.startswith("'"):
                end = rest.find("'", 1)
                value = rest[1:end] if end != -1 else rest[1:]
            elif rest.startswith('"'):
                end = rest.find('"', 1)
                value = rest[1:end] if end != -1 else rest[1:]
            else:
                value = rest.split("#")[0].strip()
            env[key] = value
    return env


def slugify(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def build_search_strings(city: str) -> list:
    c = city.strip()
    return [
        f"top real estate agents {c}",
        f"best real estate agents {c}",
        f"real estate agent {c}",
        f"realtor {c}",
        f"real estate broker {c}",
    ]


def main() -> None:
    env_path = ROOT_DIR / ".env"
    if not env_path.exists():
        print(f"ERROR: .env not found at {env_path}", file=sys.stderr)
        sys.exit(1)

    env = load_env(env_path)

    cities_raw = env.get("TARGET_CITIES_RE", "").strip()
    if not cities_raw:
        print("ERROR: TARGET_CITIES_RE is not set in .env", file=sys.stderr)
        sys.exit(1)

    cities = [c.strip() for c in cities_raw.split(",") if c.strip()]

    INPUTS_DIR.mkdir(parents=True, exist_ok=True)

    removed = 0
    for existing in sorted(INPUTS_DIR.glob("*.json")):
        existing.unlink()
        removed += 1
    if removed:
        print(f"Removed {removed} existing input file(s).\n")

    generated = []
    for city in cities:
        city_slug = slugify(city)
        filename = f"{city_slug}_real_estate_agents.json"
        output_path = INPUTS_DIR / filename

        payload = {
            "searchStringsArray": build_search_strings(city),
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
    print(f"  Cities ({len(cities)}): {', '.join(cities)}")


if __name__ == "__main__":
    main()
