from __future__ import annotations

import os
import base64
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT_PRESETS_PATH = ROOT / "game" / "export_presets.cfg"
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", "/tmp/hidefall-godot-config"))
SETTINGS_DIR = XDG_CONFIG_HOME / "godot"
SETTINGS_PATHS = [
    SETTINGS_DIR / "editor_settings-4.tres",
    SETTINGS_DIR / "editor_settings-4.7.tres",
]


def q(value: Path | str) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> None:
    android_sdk = Path(
        os.environ.get("ANDROID_SDK_ROOT")
        or os.environ.get("ANDROID_HOME")
        or ROOT / "tools" / "android-sdk"
    )
    java_sdk = Path(os.environ.get("JAVA_HOME") or os.environ.get("CONDA_PREFIX", ""))
    signing = resolve_signing_config()
    SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
    settings_lines = [
        f"export/android/android_sdk_path = {q(android_sdk)}",
        f"export/android/java_sdk_path = {q(java_sdk)}",
        f"export/android/debug_keystore = {q(signing['keystore'])}",
        f"export/android/debug_keystore_user = {q(signing['alias'])}",
        f"export/android/debug_keystore_pass = {q(signing['store_password'])}",
    ]
    for path in SETTINGS_PATHS:
        write_settings(path, settings_lines)
        print(f"Configured Godot Android editor settings at {path}")
    patch_export_presets(signing)
    print(f"Android SDK: {android_sdk}")
    print(f"Java SDK: {java_sdk}")
    print(f"Android signing keystore: {signing['keystore']}")
    print(f"Android signing alias: {signing['alias']}")


def resolve_signing_config() -> dict[str, str]:
    keystore_dir = ROOT / "tools" / "android-keystore"
    keystore_dir.mkdir(parents=True, exist_ok=True)
    encoded_keystore = os.environ.get("HIDEFALL_ANDROID_KEYSTORE_BASE64", "").strip()
    if encoded_keystore:
        keystore_path = Path(os.environ.get("HIDEFALL_ANDROID_KEYSTORE_PATH", keystore_dir / "hidefall-upload.keystore"))
        if not keystore_path.is_absolute():
            keystore_path = ROOT / keystore_path
        keystore_path.parent.mkdir(parents=True, exist_ok=True)
        keystore_path.write_bytes(base64.b64decode(encoded_keystore))
        alias = require_env("HIDEFALL_ANDROID_KEY_ALIAS")
        store_password = require_env("HIDEFALL_ANDROID_KEYSTORE_PASSWORD")
        key_password = os.environ.get("HIDEFALL_ANDROID_KEY_PASSWORD", store_password)
        return {
            "keystore": str(keystore_path),
            "alias": alias,
            "store_password": store_password,
            "key_password": key_password,
        }
    keystore_path = ROOT / "tools" / "android-keystore" / "debug.keystore"
    return {
        "keystore": str(keystore_path),
        "alias": "androiddebugkey",
        "store_password": "android",
        "key_password": "android",
    }


def require_env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError(f"{name} is required when HIDEFALL_ANDROID_KEYSTORE_BASE64 is set")
    return value


def patch_export_presets(signing: dict[str, str]) -> None:
    lines = EXPORT_PRESETS_PATH.read_text(encoding="utf-8").splitlines()
    replacements = {
        "keystore/debug": q(relative_to_game(signing["keystore"])),
        "keystore/debug_user": q(signing["alias"]),
        "keystore/debug_password": q(signing["store_password"]),
        "keystore/release": q(relative_to_game(signing["keystore"])),
        "keystore/release_user": q(signing["alias"]),
        "keystore/release_password": q(signing["key_password"]),
    }
    patched: list[str] = []
    for line in lines:
        key = line.split("=", 1)[0] if "=" in line else ""
        if key in replacements:
            patched.append(f"{key}={replacements[key]}")
        else:
            patched.append(line)
    EXPORT_PRESETS_PATH.write_text("\n".join(patched) + "\n", encoding="utf-8")


def relative_to_game(path: str) -> str:
    absolute_path = Path(path)
    try:
        return "../" + str(absolute_path.relative_to(ROOT))
    except ValueError:
        return str(absolute_path)


def write_settings(path: Path, settings_lines: list[str]) -> None:
    if path.exists():
        lines = path.read_text(encoding="utf-8").splitlines()
        prefixes = tuple(line.split(" = ", 1)[0] for line in settings_lines)
        lines = [line for line in lines if not line.startswith(prefixes)]
        if "[resource]" not in lines:
            lines.extend(["", "[resource]"])
    else:
        lines = ['[gd_resource type="EditorSettings" format=3]', "", "[resource]"]
    if lines and lines[-1] != "":
        lines.append("")
    lines.extend(settings_lines)
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
