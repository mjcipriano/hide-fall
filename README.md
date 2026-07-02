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

The current executable scene is a Godot prototype of the Quest host experience. On headset it launches directly into a solo bot round with visible falling props, an immersive OpenXR/MR view, a head-locked status panel, and a left-hand wrist menu. It also runs a WebSocket LAN host, broadcasts a UDP discovery beacon so phones list the game automatically, shows join info in-headset (QR remains on the desktop HUD, where a phone camera can actually see it), and supports joined phone hiders. On desktop/headless it starts in a lobby with a normal camera and CanvasLayer HUD for local testing.

Implemented gameplay includes lobby ready gating, room setup confirmation, object rain (hiders drop from the ceiling with the decoys — there is no blackout stage), seek, results/rematch, hider movement with dash/mimic/earthquake/ping abilities, shape/color disguise changes, and bot hider behavior. Two game modes are selectable from the wrist menu: **One-shot** (a found hider is out) and **Endless hiders** (every shot object bursts; a found hider respawns into a surviving decoy body until the prop pile or the seeker's ammo runs out). Earthquake hurls every prop into the air once per round; Ping plays a sub-second taunt jingle — unique per player — spatially from the hider's prop so the seeker can hunt by ear. All sound is procedurally synthesized (layered zaps, arpeggio chimes, rumbles), no bundled assets. There are 16 shapes (composite toy meshes: duck, mug, bottle, gem, donut, book, star...) and 7 surface patterns (stripes, dots, checker, wood, metallic, glow) generated procedurally. Props collide and stack instead of interpenetrating, fall under gravity, tumble when thrown, slide off when dropped on another prop's rim, and settle per-shape: boxes topple to a face, cans/bottles roll onto their side, cones and ducks stand back up, rings lie flat, and spheres rest exactly as placed - a prop set down twisted stays twisted. The seeker can hold-grab and twist props (distant grabs travel to the hand), fires a shot laser with hit/miss/empty sound cues, and has limited shots with a configurable between-shot cooldown (the hiders' escape window - phones see "GUN COOLING"), plus a limited scan pulse. By default only misses consume a shot, spending the last shot ends the round (hiders win), and the hunt timer does not end the round - all tunable from the wrist settings menu. The seeker's view is deliberately uncluttered: status lives on a compact left-wrist panel and a small toggleable settings menu (left Y), with only an aim dot floating in the room. Hiders earn points for how far they travel; the seeker scores for finds and is penalized for wrong shots. Late-join spectators and LAN phone client snapshots are supported.

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

- A lobby that auto-discovers Hidefall games on the local Wi-Fi (UDP beacon) with a tap-to-join list; manual host/port/room/code entry remains as fallback.
- Pre-join disguise selection: shape, color, and pattern pickers with a live rotating 3D preview; choices are sent in the join request and used at spawn.
- An in-round 3D view of the same virtual room the Quest seeker sees (not AR): all props with their true shapes/colors/patterns/orientations, a follow camera behind your prop, drag-to-orbit, and a seeker avatar with a view cone.
- A touch joystick (camera-relative movement), Dash / Mimic / Quake / Ping ability buttons with cooldowns and uses, and color/shape change buttons.
- Ready/unready control before the round starts.
- Danger badge, cooldowns, phase timer, "GUN COOLING" escape hint, and inspected/found/spectator overlays.

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
