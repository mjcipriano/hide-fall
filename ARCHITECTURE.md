# Architecture

Hidefall is split into four layers.

1. Shared simulation: deterministic phase timing, object state, ready gates, spectator state, bot decisions, hider constraints, seeker scan pulse state, scoring, cooldowns, and hit resolution.
2. Content/config: JSON files in `game/content` validated by `tools/validate_content.py`.
3. Platform scenes: Quest/seeker host scenes and mobile/hider scenes in Godot.
4. Networking: versioned WebSocket messages where the host is authoritative and clients send input requests only.

The Quest host scene initializes OpenXR at runtime when available and falls back to a desktop camera otherwise. The Quest Android export uses the Godot OpenXR Vendors Meta plugin through Gradle so the APK launches as an immersive OpenXR app instead of a flat Android surface. Seeker actions are expressed as a pointer ray from the active right controller or camera, so shooting, pickup/drop, scan pulse, and local tests share one interaction path.

Quest HUD state is mirrored into world-space `Label3D`/`Sprite3D` nodes when XR is active. The desktop/mobile CanvasLayer HUD remains for non-XR fallback and automated validation.

The lobby join flow generates a QR texture on-device from the current host IP, port, room ID, and token. The text payload remains visible as a manual fallback.

Round start is gated by active hider readiness. If no hiders are active, the simulation adds a bot hider so the host can be exercised without phone hardware. Once a round leaves the lobby, default late joins are accepted as spectators and receive snapshots without spawning a live object.
