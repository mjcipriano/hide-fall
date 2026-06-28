from __future__ import annotations

import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", "/tmp/hidefall-godot-config"))
SETTINGS_DIR = XDG_CONFIG_HOME / "godot"
SETTINGS_PATH = SETTINGS_DIR / "editor_settings-4.tres"


def q(value: Path | str) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> None:
    android_sdk = ROOT / "tools" / "android-sdk"
    java_sdk = Path(os.environ.get("JAVA_HOME") or os.environ.get("CONDA_PREFIX", ""))
    debug_keystore = ROOT / "tools" / "android-keystore" / "debug.keystore"
    SETTINGS_DIR.mkdir(parents=True, exist_ok=True)
    SETTINGS_PATH.write_text(
        "\n".join(
            [
                '[gd_resource type="EditorSettings" format=3]',
                "",
                "[resource]",
                f"export/android/android_sdk_path = {q(android_sdk)}",
                f"export/android/java_sdk_path = {q(java_sdk)}",
                f"export/android/debug_keystore = {q(debug_keystore)}",
                'export/android/debug_keystore_user = "androiddebugkey"',
                'export/android/debug_keystore_pass = "android"',
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(f"Configured Godot Android editor settings at {SETTINGS_PATH}")
    print(f"Android SDK: {android_sdk}")
    print(f"Java SDK: {java_sdk}")
    print(f"Debug keystore: {debug_keystore}")


if __name__ == "__main__":
    main()

