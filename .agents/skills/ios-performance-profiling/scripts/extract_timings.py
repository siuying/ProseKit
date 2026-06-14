#!/usr/bin/env python3
"""Extract bracketed timing lines from Xcode/XCUITest console logs.

Usage:
    scripts/extract_timings.py test-console-log.txt
    scripts/extract_timings.py test-console-log.txt --prefix live-typing

Matches lines like:
    [live-typing] first char after focusing: 3.499s
"""

from __future__ import annotations

import argparse
import re
from collections import defaultdict
from pathlib import Path


TIMING_RE = re.compile(
    r"\[(?P<prefix>[^\]]+)\]\s+(?P<label>.*?):\s+(?P<seconds>[0-9]+(?:\.[0-9]+)?)s"
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--prefix", help="Only include timings with this bracketed prefix.")
    args = parser.parse_args()

    grouped: dict[str, list[tuple[str, float]]] = defaultdict(list)
    for line in args.log.read_text(errors="replace").splitlines():
        match = TIMING_RE.search(line)
        if not match:
            continue
        prefix = match.group("prefix")
        if args.prefix and prefix != args.prefix:
            continue
        grouped[prefix].append((match.group("label"), float(match.group("seconds"))))

    for prefix, rows in grouped.items():
        print(f"[{prefix}]")
        seen: set[tuple[str, float]] = set()
        for label, seconds in rows:
            # Xcode logs often repeat the same stdout in nested summaries.
            key = (label, seconds)
            if key in seen:
                continue
            seen.add(key)
            print(f"{seconds:8.3f}s  {label}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
