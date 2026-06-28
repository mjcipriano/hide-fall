from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "game" / "content"
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
SIZE_CLASSES = {"small", "medium", "large"}


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def fail(message: str) -> None:
    print(f"content validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_keys(data: dict, keys: list[str], path: Path) -> None:
    missing = [key for key in keys if key not in data]
    if missing:
        fail(f"{path} missing keys: {', '.join(missing)}")


def validate_settings() -> None:
    path = CONTENT / "settings" / "default.json"
    data = load_json(path)
    require_keys(data, ["round", "objects", "seeker", "hiders", "network"], path)
    for key in ["object_rain_seconds", "blackout_seconds", "seek_seconds", "results_seconds"]:
        if data["round"][key] <= 0:
            fail(f"{path} round.{key} must be positive")
    if data["objects"]["decoy_count"] < 20:
        fail(f"{path} objects.decoy_count must be at least 20")
    if data["objects"]["max_decoy_count"] < data["objects"]["decoy_count"]:
        fail(f"{path} objects.max_decoy_count must be >= decoy_count")
    if data["network"]["transport"] != "websocket_lan":
        fail(f"{path} network.transport must be websocket_lan")


def validate_colors() -> None:
    path = CONTENT / "objects" / "colors.json"
    colors = load_json(path)
    ids: set[str] = set()
    for color in colors:
        require_keys(color, ["id", "display_name", "hex", "colorblind_safe"], path)
        if color["id"] in ids:
            fail(f"{path} duplicate color id {color['id']}")
        ids.add(color["id"])
        if not HEX_RE.match(color["hex"]):
            fail(f"{path} color {color['id']} has invalid hex {color['hex']}")
    if len(colors) < 8:
        fail(f"{path} should define at least 8 colors")


def validate_shapes() -> None:
    path = CONTENT / "objects" / "shapes.json"
    shapes = load_json(path)
    ids: set[str] = set()
    for shape in shapes:
        require_keys(
            shape,
            ["id", "display_name", "size_class", "mass", "friction", "bounce", "roll_factor", "rarity_weight"],
            path,
        )
        if shape["id"] in ids:
            fail(f"{path} duplicate shape id {shape['id']}")
        ids.add(shape["id"])
        if shape["size_class"] not in SIZE_CLASSES:
            fail(f"{path} shape {shape['id']} has invalid size_class")
        if shape["mass"] <= 0 or shape["rarity_weight"] <= 0:
            fail(f"{path} shape {shape['id']} mass and rarity_weight must be positive")
        if not 0 <= shape["bounce"] <= 1:
            fail(f"{path} shape {shape['id']} bounce must be 0..1")
    if len(shapes) < 12:
        fail(f"{path} should define the 12 MVP shapes")


def main() -> None:
    validate_settings()
    validate_colors()
    validate_shapes()
    print("content validation passed")


if __name__ == "__main__":
    main()

