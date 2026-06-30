from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT_PRESETS = ROOT / "game" / "export_presets.cfg"
PROJECT = ROOT / "game" / "project.godot"
EXPECTED_VERSION = "0.2.3"
EXPECTED_VERSION_CODE = "5"


def main() -> None:
    export_text = EXPORT_PRESETS.read_text(encoding="utf-8")
    project_text = PROJECT.read_text(encoding="utf-8")
    require('version/name="0.2.3"', export_text, "Android version name is 0.2.3")
    require("version/code=5", export_text, "Android version code is 5")
    require('exclude_filter=""', export_text, "Quest preset packages OpenXR Vendors addon resources")
    require("xr_features/xr_mode=1", export_text, "Quest preset exports OpenXR")
    require("xr_features/enable_meta_plugin=true", export_text, "Quest preset packages the Meta OpenXR vendor plugin")
    require("meta_xr_features/passthrough=false", export_text, "Quest preset does not request passthrough at startup")
    require("openxr/enabled=true", project_text, "Project OpenXR is enabled")
    require("openxr/environment_blend_mode=0", project_text, "Project OpenXR starts opaque")
    require("openxr/extensions/meta/passthrough=false", project_text, "Project does not request Meta passthrough at startup")
    require('renderer/rendering_method="gl_compatibility"', project_text, "Project uses the Android XR compatible renderer")
    print("android export config validation passed")


def require(needle: str, haystack: str, message: str) -> None:
    if needle not in haystack:
        raise SystemExit(f"android export config validation failed: {message}")


if __name__ == "__main__":
    main()
