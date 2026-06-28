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

## Next

1. Replace the desktop seeker camera with OpenXR rig scaffolding and Quest runtime feature detection.
2. Replace text-only join payload with an actual QR code texture in the host HUD.
3. Add real 3D pickup/drop interactions and raycast shooting from controller/controller-sim transforms.
4. Add release signing secrets and release workflow for signed release APKs/AABs.
5. Expand simulation tests for disconnect/reconnect, late join, bot behavior, and 10-round soak runs.
6. Test the debug APKs on physical Quest/Android/iOS devices.
