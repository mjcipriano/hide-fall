# Agent Notes

Follow `GAME_DESIGN.md` as the product source of truth.

Rules:

- Keep gameplay logic in shared scripts under `game/scripts/shared`.
- Keep Quest/XR-specific code under `game/scripts/quest`.
- Keep mobile/client UI code under `game/scripts/mobile`.
- Keep all balance and content data-driven in `game/content`.
- Add or update tests for every gameplay/system change.
- Keep `PROGRESS.md` current so another agent can continue immediately.
- Do not commit downloaded Godot binaries, export templates, generated `.godot` caches, or build outputs.

The target engine is Godot 4.7 stable. The target Quest MR path is OpenXR plus the Godot OpenXR Vendors plugin, but the current local verification path must remain runnable headlessly.

