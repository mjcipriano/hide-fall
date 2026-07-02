from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT_PRESETS = ROOT / "game" / "export_presets.cfg"
PROJECT = ROOT / "game" / "project.godot"
EXPECTED_VERSION = "0.3.1"
EXPECTED_VERSION_CODE = "10"


def main() -> None:
    export_text = EXPORT_PRESETS.read_text(encoding="utf-8")
    project_text = PROJECT.read_text(encoding="utf-8")
    require(f'version/name="{EXPECTED_VERSION}"', export_text, f"Android version name is {EXPECTED_VERSION}")
    require(f"version/code={EXPECTED_VERSION_CODE}", export_text, f"Android version code is {EXPECTED_VERSION_CODE}")
    require('exclude_filter=""', export_text, "Quest preset packages OpenXR Vendors addon resources")
    require("xr_features/xr_mode=1", export_text, "Quest preset exports OpenXR")
    require("xr_features/enable_meta_plugin=true", export_text, "Quest preset packages the Meta OpenXR vendor plugin")
    require("meta_xr_features/passthrough=true", export_text, "Quest preset requests Meta passthrough")
    require("openxr/enabled=true", project_text, "Project OpenXR is enabled")
    require("openxr/environment_blend_mode=0", project_text, "Project OpenXR starts opaque")
    require("openxr/extensions/meta/passthrough=true", project_text, "Project enables the Meta passthrough extension")
    require('renderer/rendering_method="mobile"', project_text, "Project uses the Forward Mobile renderer required for OpenXR multiview")
    require("shaders/enabled=true", project_text, "Project enables XR multiview shader variants (prevents blank passthrough)")
    print("android export config validation passed")


def require(needle: str, haystack: str, message: str) -> None:
    if needle not in haystack:
        raise SystemExit(f"android export config validation failed: {message}")


if __name__ == "__main__":
    main()
