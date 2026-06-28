# Hidefall

Hidefall is a Godot 4 mixed-reality prop-hunt party game prototype. The target product is a Meta Quest seeker app with phone hider clients. This repo is structured so the core gameplay, content, scoring, phase timing, and network message rules are testable without headset hardware.

## Current Build

- Engine: Godot `4.7-stable`
- Primary project: `game/project.godot`
- Local verification: `make test`
- Content validation: `make validate`
- Progress log: `PROGRESS.md`

## Setup

```bash
mamba env create -f environment.yml
conda activate hidefall
make godot-version
make test
```

Godot itself is installed by `make install-godot` into `tools/godot/` from the official Godot release artifact. The binary is intentionally ignored by git.

## Run

```bash
make run
```

The current executable scene is a Godot prototype of the Quest host experience. It starts in a lobby, runs a WebSocket LAN host, shows a QR join code plus manual payload, and begins a round when `R` is pressed. On OpenXR-capable Quest runtime it initializes an `XROrigin3D`, headset camera, and controller nodes; on desktop/headless it falls back to a normal camera for local testing.

Controls:

- `R`: start/rematch from lobby.
- Mouse click / right trigger: shoot along the seeker pointer ray.
- `E` / right grip: pick up or drop the pointed-at prop.
- `WASD`: local hider test movement.
- `Space`: freeze local hider.
- `C`: request next color for local hider.
- `V`: request next shape for local hider.

## Mobile Client

The Godot mobile hider scene is `res://scenes/mobile/hider_client.tscn`. It includes:

- Host, port, room, token, and name fields.
- WebSocket connection and join request.
- Periodic hider input messages.
- Freeze, color, and shape controls.
- Top-down map rendering from authoritative snapshots.
- Danger, cooldown, phase, and hider status display.

It is functional as a Godot client scene. A debug Android APK export preset is included.

## APK Builds

```bash
make install-export-templates
make install-android-sdk
make build-apks
```

Outputs:

- `build/hidefall-quest-debug.apk`
- `build/hidefall-mobile-debug.apk`

Release signing and store packaging are intentionally separate from the debug APK path because signing credentials must not be committed.
