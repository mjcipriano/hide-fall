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

NOTE: the actual build toolchain (`Makefile`, CI) currently pins Godot `4.6.2-stable` and the shipped Quest builds run on it. Keep `Makefile`'s `GODOT_VERSION` and this doc in sync when bumping engines.

## Critical Quest rendering requirement (do not regress)

The Quest runs OpenXR in **stereo multiview**, which requires the Vulkan renderer with the multiview shader variants compiled. `game/project.godot` MUST keep:

```ini
[xr]
openxr/enabled=true
shaders/enabled=true          ; compiles the multiview shader variants

[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
```

If `xr/shaders/enabled` is missing, or the renderer is left on `gl_compatibility`, the app still launches and the simulation runs (objects spawn, passthrough turns on) but the **Forward Mobile tonemapper subpass shader is null every frame** and nothing composites — you get a blank passthrough world with no virtual props. The tell in logcat:

```
ERROR: tonemapper_subpass: Condition "shader.is_null()" is true.
ERROR: version_get_shader: Condition "!variants_enabled[p_variant]" is true. Returning: RID()
```

Zero of those lines == rendering is healthy. This was the "blank AR world" bug fixed on 2026-06-30. See Godot issues #84841 / #109855.

## Deploying and debugging on real Quest hardware (from this WSL2 box)

The Quest is USB-tethered to Windows; the Linux side reaches it over **wireless adb**. Bundled tools: Godot at `tools/godot/`, Android SDK (incl. `adb`) at `tools/android-sdk/platform-tools/adb`. Windows-side adb (already authorized with the headset) lives at `/mnt/c/Program Files/Oculus Developer Hub/resources/bin/adb.exe`.

One-time wireless adb setup (USB must be attached to Windows for this):

```bash
WADB="/mnt/c/Program Files/Oculus Developer Hub/resources/bin/adb.exe"
LADB=tools/android-sdk/platform-tools/adb
SERIAL=$("$WADB" devices | awk 'NR==2{print $1}')            # e.g. 2G97C5ZH6J00SH
IP=$("$WADB" -s "$SERIAL" shell ip -f inet addr show wlan0 | grep -o 'inet [0-9.]*' | awk '{print $2}')
"$WADB" -s "$SERIAL" tcpip 5555                              # put device in TCP mode
# Linux adb needs the key the headset already trusts (the Windows one):
cp /mnt/c/Users/*/.android/adbkey ~/.android/adbkey && chmod 600 ~/.android/adbkey
cp /mnt/c/Users/*/.android/adbkey.pub ~/.android/adbkey.pub
$LADB connect "$IP:5555"                                     # -> "device", not "unauthorized"
```

After that, everything runs from Linux adb: `LADB="tools/android-sdk/platform-tools/adb -s <IP>:5555"`.

Build, install, launch, watch:

```bash
source ~/miniconda3/etc/profile.d/conda.sh && conda activate hidefall
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
make build-quest-apk                                         # -> build/hidefall-quest.apk

PKG=com.mjcipriano.hidefall.quest
$LADB install -r -d build/hidefall-quest.apk                 # if it fails INSTALL_FAILED_UPDATE_INCOMPATIBLE:
$LADB uninstall $PKG && $LADB install -r -d build/hidefall-quest.apk   # signing key differs -> uninstall once
$LADB logcat -c
$LADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1
$LADB logcat -d | grep -aE "Hidefall|tonemapper|SCRIPT ERROR"
```

Success marker (the app prints it once objects exist):

```
Hidefall visible gameplay ready: phase=object_rain objects=78 object_nodes=78 xr=OpenXR immersive passthrough network=solo bot round running
```

Gotchas seen in practice:

- **"Launch is blocked because: a Reprojected OS dialog is currently showing"** — the *Oculus Link Available* dialog pops whenever the headset is USB-tethered, and it swallows the launch. Dismiss it with `$LADB shell am force-stop com.oculus.systemux` right before launching, or unplug USB (wireless adb survives the unplug), or dismiss it in-headset.
- **`unauthorized` on `adb connect`** — Linux adb is using its own unsigned key; copy the Windows `adbkey`/`adbkey.pub` as above and reconnect.
- **Device drops off adb after the headset sleeps** — wake it, `$LADB connect <IP>:5555` again. `tcpip` mode persists until the headset reboots.
- **Signature mismatch on install** — released builds are signed with the upload key; local builds use the debug keystore. Uninstall once, then local installs stick.

`make smoke-quest-apk` automates install+launch+logcat capture into `build/quest-smoke/` and is the gate before asking someone to put the headset on.

