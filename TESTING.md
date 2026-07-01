# Testing

Run all local checks:

```bash
make test
```

This validates JSON content and runs Godot headless tests.

Current coverage:

- Content/config parsing (shapes with rest modes, colors, patterns, settings).
- Color and object definition validity.
- Phase transitions.
- Ready-gated round start and room setup confirmation.
- Hider movement constraints.
- Shape/color cooldowns.
- Scan pulse reveal and charge consumption.
- Late join spectator handling.
- Mobile join (with pre-join shape/color/pattern preferences), ready, input, snapshot, 3D world mirroring, and camera-relative movement.
- Host join, snapshot, pickup/drop, scan, and spectator smoke behavior.
- Correct and wrong shot behavior, plus the configurable gun cooldown between shots.
- Prop physics feel: collision separation, gravity, stacking, rim slide-off, airborne tumbling, per-shape rest modes (side/upright/flat/any), and yaw preservation when settling.
- Prop factory meshes and procedural pattern materials for every content id.
- LAN discovery beacon build/parse and a live UDP loopback round trip.
- Round ending when all hiders are found or time expires.
- Deterministic bot/simulation behavior.

Device smoke test (Quest connected over adb): `make smoke-quest-apk` — see `AGENTS.md` for the WSL2 wireless-adb runbook.
