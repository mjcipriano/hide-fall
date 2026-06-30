from __future__ import annotations

import re
import sys
from pathlib import Path


REQUIRED = {
    "android.intent.action.MAIN",
    "android.intent.category.LAUNCHER",
    "com.oculus.intent.category.VR",
    "org.khronos.openxr.intent.category.IMMERSIVE_HMD",
}
FORBIDDEN = {
    "android.intent.category.HOME",
}


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_quest_launcher_filter.py <aapt-xmltree.txt>")
    text = Path(sys.argv[1]).read_text(encoding="utf-8")
    for values in intent_filter_values(text):
        if REQUIRED.issubset(values) and values.isdisjoint(FORBIDDEN):
            return
    required = ", ".join(sorted(REQUIRED))
    forbidden = ", ".join(sorted(FORBIDDEN))
    raise SystemExit(
        "Quest APK launcher intent filter must include all of "
        f"{required}, and none of {forbidden}"
    )


def intent_filter_values(text: str) -> list[set[str]]:
    filters: list[set[str]] = []
    current: set[str] | None = None
    for line in text.splitlines():
        if "E: intent-filter" in line:
            current = set()
            filters.append(current)
            continue
        if current is None:
            continue
        match = re.search(r'Raw: "([^"]+)"', line)
        if match:
            current.add(match.group(1))
    return filters


if __name__ == "__main__":
    main()
