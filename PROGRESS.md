# Hidefall Progress Log

This file is the handoff point for future agents. Keep it current before and after major changes.

## 2026-06-28

- Read `GAME_DESIGN.md`.
- User clarified this must be a Godot implementation, not a browser prototype.
- Installed official Godot `4.7-stable` Linux x86_64 binary into `tools/godot/`.
- Confirmed binary reports `4.7.stable.official.5b4e0cb0f`.
- Created reproducible `hidefall` conda environment from `environment.yml`.
- Added Godot project under `game/` with a desktop host prototype scene.
- Added data-driven config/content JSON for round settings, shapes, colors, and classic mode.
- Added shared gameplay systems:
  - deterministic authoritative round simulation,
  - phase transitions,
  - hider movement and freeze state,
  - shape/color cooldowns,
  - shooting and hit resolution,
  - scoring,
  - network message validation.
- Added Godot mobile hider client scene scaffold and WebSocket LAN host scaffold.
- Continued implementation after user asked whether mobile was complete:
  - Host now starts in lobby instead of auto-starting a round.
  - Host scene starts a WebSocket LAN server during normal runs.
  - Host accepts/rejects mobile join requests, maps peers to authoritative hider players, applies hider input, and sends per-player snapshots.
  - Host HUD shows room ID, token, WebSocket URL, and JSON join payload.
  - Mobile scene now has join fields, WebSocket client connection, join request handling, periodic input sending, freeze/color/shape controls, snapshot handling, cooldown/danger/status display, and top-down map drawing.
  - Added tests for host join handling and mobile join/snapshot/disguise request behavior.
- Continued release/build work:
  - Installed official Godot 4.7 export templates locally.
  - Installed Android command-line tools and SDK packages under ignored `tools/android-sdk`.
  - Added OpenJDK 17 to `environment.yml`.
  - Added ignored debug keystore generation.
  - Added boot scene that chooses Quest host or mobile client via export feature tags.
  - Added Android export presets for `Quest Debug APK` and `Mobile Debug APK`.
  - Added Make targets for export template install, Android SDK install, Android export configuration, and APK builds.
  - Built and verified local debug APKs:
    - `build/hidefall-quest-debug.apk`
    - `build/hidefall-mobile-debug.apk`
  - Updated GitHub Actions to run tests and build/upload both APKs.
- Added docs: `README.md`, `ARCHITECTURE.md`, `NETWORK_PROTOCOL.md`, `TESTING.md`, `BUILD_AND_RELEASE.md`, `CONTENT_SCHEMA.md`, `AGENTS.md`.
- Added `tools/validate_content.py`, `Makefile`, and GitHub Actions test workflow.
- Verified locally with `conda run -n hidefall make test`.
- Opened draft PR #1 from `codex/godot-hidefall-mvp`.
- Fixed CI Android SDK bootstrap issues:
  - SDK license acceptance no longer fails under `pipefail`,
  - SDK package install verifies `adb` and `apksigner`,
  - Android SDK paths are configured with absolute paths,
  - Godot Android editor settings are written to both `editor_settings-4.tres` and `editor_settings-4.7.tres` for Godot 4.7.
- Re-verified locally at 2026-06-28T00:52:20-04:00:
  - `conda run -n hidefall make test`
  - `conda run -n hidefall make build-apks GODOT_ENV='XDG_DATA_HOME=/tmp/hidefall-godot-data XDG_CONFIG_HOME=/tmp/hidefall-clean-config XDG_CACHE_HOME=/tmp/hidefall-godot-cache'`
  - `tools/android-sdk/build-tools/35.0.0/apksigner verify --verbose build/hidefall-quest-debug.apk`
  - `tools/android-sdk/build-tools/35.0.0/apksigner verify --verbose build/hidefall-mobile-debug.apk`
- After CI still reported missing Android SDK directories on the runner, pinned `ANDROID_SDK_ROOT`, `ANDROID_HOME`, and `JAVA_HOME` through the Makefile and made `tools/configure_godot_android.py` honor those environment values.
- Re-verified locally at 2026-06-28T00:57:41-04:00:
  - `conda run -n hidefall make test`
  - clean-config `conda run -n hidefall make build-apks`
  - APK signature verification for both debug APKs.
- Implemented host lobby QR generation using an in-project Godot QR encoder; the host HUD now shows a scan-to-join QR texture and keeps the manual payload fallback.
- Added runtime OpenXR scaffold for the Quest host scene:
  - initializes OpenXR when available,
  - creates `XROrigin3D`, `XRCamera3D`, and left/right `XRController3D` nodes,
  - falls back to the desktop/headless camera path for local development and CI.
- Reworked seeker interactions to use a 3D pointer ray from the right controller or fallback camera.
- Added pickup/drop support:
  - host can hold/drop pointed-at props,
  - held hider input is blocked,
  - held objects follow the seeker pointer,
  - dropped live hiders receive an inspection-survived stat.
- Re-verified locally at 2026-06-28T01:04:55-04:00:
  - `conda run -n hidefall make test`
  - `conda run -n hidefall make build-apks`
  - APK signature verification for both debug APKs.
- Added disconnect handling and 10-round simulation soak coverage to the Godot test runner.
- Re-verified locally at 2026-06-28T01:07:32-04:00 with `conda run -n hidefall make test`.
- GitHub Actions passed on PR #1 at 2026-06-28T11:05:03-04:00:
  - Run `28312156078`: `test` passed, `android-apks` passed.
  - Run `28312155231`: `test` passed, `android-apks` passed.
- Confirmed CI artifact `hidefall-debug-apks` exists and is not expired for both successful runs.
- Downloaded the latest CI artifact from run `28312156078` to `/tmp/hidefall-ci-artifacts`.
- Verified CI-built APK signatures:
  - `/tmp/hidefall-ci-artifacts/hidefall-quest-debug.apk`
  - `/tmp/hidefall-ci-artifacts/hidefall-mobile-debug.apk`
- User merged PR #1 into `master` and deleted the branch.
- Pulled merged `master` locally.
- Added `.github/workflows/release.yml` at 2026-06-28T13:30:44-04:00:
  - triggers on version tags like `v0.1.0`,
  - installs the same Godot/export template/Android SDK toolchain,
  - runs tests,
  - builds both debug APKs,
  - verifies APK signatures,
  - writes `SHA256SUMS`,
  - creates a GitHub Release and attaches both APKs plus checksums.
- Updated `BUILD_AND_RELEASE.md` with the tag-driven release process.
- Pushed tag `v0.1.0`.
- Release workflow run `28330348506` failed at 2026-06-28T13:35:34-04:00 because the verification step hardcoded `tools/android-sdk/.../apksigner`; GitHub-hosted runners use `ANDROID_SDK_ROOT` for the SDK path.
- Patched `.github/workflows/release.yml` to verify APKs using `${ANDROID_SDK_ROOT}/build-tools/35.0.0/apksigner` and to create releases from the existing tag without passing a separate `--target`.

## Next

1. Push the release workflow fix to `master`.
2. Manually run the corrected release workflow for existing tag `v0.1.0`.
3. Watch the release workflow until it passes.
4. Confirm GitHub Release `v0.1.0` exists and has `hidefall-quest-debug.apk`, `hidefall-mobile-debug.apk`, and `SHA256SUMS` attached.
5. Test the debug APKs on physical Quest/Android/iOS devices.
6. Install and validate the Godot OpenXR Vendors plugin for Meta Quest passthrough/scene API support.
7. Add production release signing secrets/workflow for store-ready signed release APKs/AABs.
8. Expand simulation tests for reconnect and deeper bot behavior.
