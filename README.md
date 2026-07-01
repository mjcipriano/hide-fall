# Hidefall

Hidefall is a Godot 4 mixed-reality prop-hunt party game prototype. The target product is a Meta Quest seeker app with phone hider clients. This repo is structured so the core gameplay, content, scoring, phase timing, and network message rules are testable without headset hardware.

## Current Build

- Engine: Godot `4.6.2-stable`
- Primary project: `game/project.godot`
- Local verification: `make test`
- APK verification: `make build-apks`
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

The current executable scene is a Godot prototype of the Quest host experience. On headset it launches directly into a solo bot round with visible falling props, an immersive OpenXR/MR view, a head-locked status panel, and a left-hand wrist menu. It also runs a WebSocket LAN host, shows a QR join code plus manual payload, and supports joined phone hiders. On desktop/headless it starts in a lobby with a normal camera and CanvasLayer HUD for local testing.

Implemented gameplay includes lobby ready gating, room setup confirmation, object rain, blackout, seek, results/rematch, hider movement and freeze, shape/color disguise changes, and bot hider behavior. Props collide and stack instead of interpenetrating, fall under gravity, can be thrown, and topple to rest flat on a face when dropped. The seeker can hold-grab and twist props (distant grabs travel to the hand), fires a shot laser with hit/miss/empty sound cues, has limited shots that stop firing when depleted, and a limited scan pulse. Hiders earn points for how far they travel; the seeker scores for finds and is penalized for wrong shots. Late-join spectators and LAN phone client snapshots are supported.

Controls:

- `R`: start/rematch from lobby or confirm room setup.
- Mouse click / right trigger: shoot along the seeker pointer ray (blocked with an empty-click when out of shots).
- Hold `E` / right grip: grab and turn the pointed-at prop; release to drop it (with throw velocity).
- `Q` / Quest primary face button: use a scan pulse during the seek phase.
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
- Ready/unready control before the round starts.
- Top-down map rendering from authoritative snapshots.
- Danger, cooldown, phase, and hider status display.
- Spectator status for late joins after a round starts.

It is functional as a Godot client scene. A debug Android APK export preset is included.

## APK Builds

```bash
make install-export-templates
make install-android-sdk
make build-apks
make verify-apks
```

Outputs:

- `build/hidefall-quest.apk`
- `build/hidefall-mobile.apk`

The Quest APK uses the generated Android Gradle template so the Meta OpenXR vendor AAR and native plugin are packaged. Release builds use a persistent upload key from GitHub Secrets so upgrades can install over earlier builds signed by that key. The Mobile APK remains a normal flat Android hider client with OpenXR disabled.

If a Quest is connected through authorized ADB, run `make smoke-quest-apk` after building. It installs, launches, captures logcat, and fails if the app exits or logs crash/OpenXR startup errors.

Release signing and store packaging use GitHub Secrets or local environment variables because signing credentials must not be committed.
