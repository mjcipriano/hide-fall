# Architecture

Hidefall is split into four layers.

1. Shared simulation: deterministic phase timing, object state, hider constraints, scoring, cooldowns, and hit resolution.
2. Content/config: JSON files in `game/content` validated by `tools/validate_content.py`.
3. Platform scenes: Quest/seeker host scenes and mobile/hider scenes in Godot.
4. Networking: versioned WebSocket messages where the host is authoritative and clients send input requests only.

The current implementation focuses on a playable Godot host prototype plus headless simulation coverage. Quest MR integration should wrap the same shared systems rather than replacing them.

