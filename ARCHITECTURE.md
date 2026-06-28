# Architecture

Hidefall is split into four layers.

1. Shared simulation: deterministic phase timing, object state, ready gates, spectator state, bot decisions, hider constraints, seeker scan pulse state, scoring, cooldowns, and hit resolution.
2. Content/config: JSON files in `game/content` validated by `tools/validate_content.py`.
3. Platform scenes: Quest/seeker host scenes and mobile/hider scenes in Godot.
4. Networking: versioned WebSocket messages where the host is authoritative and clients send input requests only.

The Quest host scene initializes OpenXR at runtime when available and falls back to a desktop camera otherwise. Seeker actions are expressed as a pointer ray from the active right controller or camera, so shooting and pickup/drop share one interaction path across Quest and local tests.

The lobby join flow generates a QR texture on-device from the current host IP, port, room ID, and token. The text payload remains visible as a manual fallback.

Round start is gated by active hider readiness. If no hiders are active, the simulation adds a bot hider so the host can be exercised without phone hardware. Once a round leaves the lobby, default late joins are accepted as spectators and receive snapshots without spawning a live object.
