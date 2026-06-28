from __future__ import annotations

import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
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
    debug_keystore = ROOT / "tools" / "android-keystore" / "debug.keystore"
    SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
    settings_lines = [
        f"export/android/android_sdk_path = {q(android_sdk)}",
        f"export/android/java_sdk_path = {q(java_sdk)}",
        f"export/android/debug_keystore = {q(debug_keystore)}",
        'export/android/debug_keystore_user = "androiddebugkey"',
        'export/android/debug_keystore_pass = "android"',
    ]
    for path in SETTINGS_PATHS:
        write_settings(path, settings_lines)
        print(f"Configured Godot Android editor settings at {path}")
    print(f"Android SDK: {android_sdk}")
    print(f"Java SDK: {java_sdk}")
    print(f"Debug keystore: {debug_keystore}")


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
