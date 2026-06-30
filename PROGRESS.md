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
- Opened draft PR #1 from `codex/godot-hidefall-mvp`.
- Fixed CI Android SDK bootstrap issues:
  - SDK license acceptance no longer fails under `pipefail`,
  - SDK package install verifies `adb` and `apksigner`,
  - Android SDK paths are configured with absolute paths,
  - Godot Android editor settings are written to both `editor_settings-4.tres` and `editor_settings-4.7.tres` for Godot 4.7.
- Re-verified locally at 2026-06-28T00:52:20-04:00:
  - `conda run -n hidefall make test`
  - `conda run -n hidefall make build-apks GODOT_ENV='XDG_DATA_HOME=/tmp/hidefall-godot-data XDG_CONFIG_HOME=/tmp/hidefall-clean-config XDG_CACHE_HOME=/tmp/hidefall-godot-cache'`
  - `tools/android-sdk/build-tools/35.0.0/apksigner verify --verbose build/hidefall-quest-debug.apk`
  - `tools/android-sdk/build-tools/35.0.0/apksigner verify --verbose build/hidefall-mobile-debug.apk`
- After CI still reported missing Android SDK directories on the runner, pinned `ANDROID_SDK_ROOT`, `ANDROID_HOME`, and `JAVA_HOME` through the Makefile and made `tools/configure_godot_android.py` honor those environment values.
- Re-verified locally at 2026-06-28T00:57:41-04:00:
  - `conda run -n hidefall make test`
  - clean-config `conda run -n hidefall make build-apks`
  - APK signature verification for both debug APKs.
- Implemented host lobby QR generation using an in-project Godot QR encoder; the host HUD now shows a scan-to-join QR texture and keeps the manual payload fallback.
- Added runtime OpenXR scaffold for the Quest host scene:
  - initializes OpenXR when available,
  - creates `XROrigin3D`, `XRCamera3D`, and left/right `XRController3D` nodes,
  - falls back to the desktop/headless camera path for local development and CI.
- Reworked seeker interactions to use a 3D pointer ray from the right controller or fallback camera.
- Added pickup/drop support:
  - host can hold/drop pointed-at props,
  - held hider input is blocked,
  - held objects follow the seeker pointer,
  - dropped live hiders receive an inspection-survived stat.
- Re-verified locally at 2026-06-28T01:04:55-04:00:
  - `conda run -n hidefall make test`
  - `conda run -n hidefall make build-apks`
  - APK signature verification for both debug APKs.
- Added disconnect handling and 10-round simulation soak coverage to the Godot test runner.
- Re-verified locally at 2026-06-28T01:07:32-04:00 with `conda run -n hidefall make test`.
- GitHub Actions passed on PR #1 at 2026-06-28T11:05:03-04:00:
  - Run `28312156078`: `test` passed, `android-apks` passed.
  - Run `28312155231`: `test` passed, `android-apks` passed.
- Confirmed CI artifact `hidefall-debug-apks` exists and is not expired for both successful runs.
- Downloaded the latest CI artifact from run `28312156078` to `/tmp/hidefall-ci-artifacts`.
- Verified CI-built APK signatures:
  - `/tmp/hidefall-ci-artifacts/hidefall-quest-debug.apk`
  - `/tmp/hidefall-ci-artifacts/hidefall-mobile-debug.apk`
- User merged PR #1 into `master` and deleted the branch.
- Pulled merged `master` locally.
- Added `.github/workflows/release.yml` at 2026-06-28T13:30:44-04:00:
  - triggers on version tags like `v0.1.0`,
  - installs the same Godot/export template/Android SDK toolchain,
  - runs tests,
  - builds both debug APKs,
  - verifies APK signatures,
  - writes `SHA256SUMS`,
  - creates a GitHub Release and attaches both APKs plus checksums.
- Updated `BUILD_AND_RELEASE.md` with the tag-driven release process.
- Pushed tag `v0.1.0`.
- Release workflow run `28330348506` failed at 2026-06-28T13:35:34-04:00 because the verification step hardcoded `tools/android-sdk/.../apksigner`; GitHub-hosted runners use `ANDROID_SDK_ROOT` for the SDK path.
- Patched `.github/workflows/release.yml` to verify APKs using `${ANDROID_SDK_ROOT}/build-tools/35.0.0/apksigner` and to create releases from the existing tag without passing a separate `--target`.
- Pushed the release workflow fix to `master` in commit `c51f0bf`.
- Dispatched corrected release workflow run `28330458668` for existing tag `v0.1.0`.
- Release workflow run `28330458668` passed at 2026-06-28T13:39:55-04:00:
  - tests passed,
  - both APKs built,
  - both APK signatures verified,
  - checksums generated,
  - GitHub Release created.
- Confirmed GitHub Release `v0.1.0` exists:
  - URL: https://github.com/mjcipriano/hide-fall/releases/tag/v0.1.0
  - title: `Hidefall 0.1.0`
  - attached assets: `hidefall-quest-debug.apk`, `hidefall-mobile-debug.apk`, `SHA256SUMS`.
- Downloaded release assets to `/tmp/hidefall-release-v0.1.0` and verified:
  - `sha256sum -c SHA256SUMS` passes,
  - `apksigner verify --verbose` passes for both release APK assets.
- Confirmed normal `master` Test And Build workflow is green for commit `c51f0bf` in run `28330452425`.
- Continued gameplay completion pass after user asked whether all features were implemented:
  - Added ready-gated round start for active hider players.
  - Added mobile ready/unready button and `ready_state` client message handling.
  - Added room setup phase before object rain and `R` confirmation on the host.
  - Added late-join spectator acceptance instead of hard rejection once a round is in progress.
  - Added seeker scan pulse state, host input binding, HUD feedback, and reveal/decrement simulation behavior.
  - Added autonomous bot hider decision updates so bot rounds move without phone input.
  - Updated snapshots and lobby data with scan pulse and spectator state.
  - Expanded Godot tests for room setup config, ready gates, scan pulse, bot decisions, host spectator joins, host scan pulse, and mobile ready behavior.
- Re-verified locally at 2026-06-28 after the gameplay pass:
  - `conda run -n hidefall make test`
  - `conda run -n hidefall make build-apks`
  - `tools/android-sdk/build-tools/35.0.0/apksigner verify --verbose build/hidefall-quest-debug.apk`
  - `tools/android-sdk/build-tools/35.0.0/apksigner verify --verbose build/hidefall-mobile-debug.apk`
- Committed and pushed the gameplay pass to `master` in commit `7297c03`.
- Confirmed GitHub Actions Test And Build run `28336123902` passed for commit `7297c03`:
  - `test` passed,
  - `android-apks` passed,
  - CI artifact upload completed.
- Tagged and pushed `v0.2.0` for the gameplay pass.
- Confirmed release workflow run `28336193586` passed for `v0.2.0`:
  - tests passed,
  - both APKs built,
  - both APK signatures verified,
  - checksums generated,
  - GitHub Release created.
- Confirmed tag-triggered Test And Build run `28336193595` passed for `v0.2.0`.
- Confirmed GitHub Release `v0.2.0` exists:
  - URL: https://github.com/mjcipriano/hide-fall/releases/tag/v0.2.0
  - title: `Hidefall 0.2.0`
  - attached assets: `hidefall-quest-debug.apk`, `hidefall-mobile-debug.apk`, `SHA256SUMS`.
- Downloaded release assets to `/tmp/hidefall-release-v0.2.0` and verified:
  - `sha256sum -c SHA256SUMS` passes,
  - `apksigner verify --verbose` passes for both release APK assets.
- User tested the `v0.2.0` Quest APK on physical Quest hardware and reported it launched as a flat screen instead of immersive VR/MR, and that a button press could make the screen disappear.
- Root cause found locally: the Quest export was still a normal Android APK path without the Android Gradle template, Godot OpenXR Vendors Meta plugin packaging, and Quest/OpenXR immersive manifest categories. The scene had runtime OpenXR code, but the APK metadata/package path did not force immersive headset launch.
- Implemented the `v0.2.1` Quest XR packaging fix:
  - enabled Gradle export for the Quest preset,
  - vendored the official Godot OpenXR Vendors `5.1.0-stable` Meta/Android runtime pieces,
  - enabled the Meta OpenXR plugin, Quest 3/3S support metadata, and passthrough option in the Quest preset,
  - added `openxr/enabled`, alpha-blend passthrough, and mobile renderer settings in `project.godot`,
  - added `tools/prepare_android_xr_template.py` to generate the ignored Android template and patch Gradle/manifest files,
  - injects `com.oculus.intent.category.VR`, `org.khronos.openxr.intent.category.IMMERSIVE_HMD`, and `android.hardware.vr.headtracking` into the Quest build,
  - packages `libgodotopenxrvendors.so`, `libopenxr_loader.so`, the Meta AAR, and `openxr_action_map.tres`,
  - mirrors the Quest HUD/QR/status into 3D nodes when XR is active while preserving the desktop CanvasLayer fallback,
  - made Quest primary button context-sensitive instead of only scan-pulse bound,
  - fixed deferred boot scene switching to avoid Godot busy-tree errors,
  - bumped Android APK version metadata to `0.2.1` / code `3`,
  - updated Android SDK bootstrap to install Android 36 platform/build tools used by the Gradle export.
  - added `tools/verify_android_artifacts.sh`, `make verify-apks`, and CI/release workflow verification so signatures, Quest immersive manifest entries, packaged OpenXR vendor files, and mobile non-XR packaging are checked automatically.
- Local verification passed for the `v0.2.1` fix before commit:
  - `conda run -n hidefall make test`,
  - `conda run -n hidefall make build-apks` outside the sandbox because Gradle probes local network interfaces,
  - `conda run -n hidefall make verify-apks`.
- The local `v0.2.1` Quest artifact verification confirms:
  - debug signature verifies,
  - manifest has version `0.2.1` / code `3`,
  - manifest has `org.khronos.openxr.permission.OPENXR`, `org.khronos.openxr.permission.OPENXR_SYSTEM`, required `android.hardware.vr.headtracking`, `com.oculus.intent.category.VR`, `org.khronos.openxr.intent.category.IMMERSIVE_HMD`, `com.oculus.supportedDevices`, and `org.godotengine.plugin.v2.GodotOpenXR`,
  - APK packages `lib/arm64-v8a/libgodotopenxrvendors.so`, `lib/arm64-v8a/libopenxr_loader.so`, `assets/addons/godotopenxrvendors/plugin.gdextension`, and the OpenXR action map.
- The local `v0.2.1` mobile artifact verification confirms:
  - debug signature verifies,
  - manifest has version `0.2.1` / code `3`,
  - manifest has no Quest/OpenXR categories, OpenXR permissions, VR headtracking feature, or GodotOpenXR plugin metadata,
  - APK has no Quest OpenXR vendor binaries.
- Remaining release work for this fix:
  - commit and push `master`,
  - confirm push CI passes with the new artifact verifier,
  - tag and push `v0.2.1`,
  - confirm release workflow publishes APK assets plus `SHA256SUMS`,
  - download released assets and verify checksums/APK artifact contents.
- Pushed commit `3ba36a8` to `master`.
- GitHub Actions run `28342210766` passed the `test` job and built both APKs, then failed in `Verify APK artifacts` because the runner did not have `rg` installed. The APK signatures had already verified before that tool failure.
- Replaced `rg` usage inside `tools/verify_android_artifacts.sh` with `grep -E` so the verifier has no hidden ripgrep dependency.
- Re-verified locally with `conda run -n hidefall make verify-apks`.
- Pushed commit `21552b8` to `master`.
- GitHub Actions Test And Build run `28342367635` passed for `master` on commit `21552b8`:
  - `test` passed,
  - `android-apks` passed,
  - new `Verify APK artifacts` step passed,
  - APK artifact upload completed.
- Tagged and pushed `v0.2.1` at commit `21552b8`.
- Tag-triggered workflows started:
  - Release run `28342480249`,
  - Test And Build run `28342480245`.
- Tag-triggered Test And Build run `28342480245` passed:
  - `test` passed,
  - `android-apks` passed,
  - `Verify APK artifacts` passed,
  - APK artifact upload completed.
- Release workflow run `28342480249` passed:
  - resolved version `0.2.1`,
  - tests passed,
  - both APKs built,
  - `Verify APK artifacts` passed,
  - `SHA256SUMS` and release notes were written,
  - GitHub Release creation passed.
- Confirmed GitHub Release `v0.2.1` exists:
  - URL: https://github.com/mjcipriano/hide-fall/releases/tag/v0.2.1
  - title: `Hidefall 0.2.1`
  - published: 2026-06-29T01:13:56Z
  - attached assets: `hidefall-quest-debug.apk`, `hidefall-mobile-debug.apk`, `SHA256SUMS`.
- Downloaded release assets to `/tmp/hidefall-release-v0.2.1` and verified:
  - `sha256sum -c SHA256SUMS` passes,
  - `tools/verify_android_artifacts.sh /tmp/hidefall-release-v0.2.1/hidefall-quest-debug.apk /tmp/hidefall-release-v0.2.1/hidefall-mobile-debug.apk` passes,
  - downloaded Quest APK signature verifies and contains immersive OpenXR/Quest manifest entries plus packaged Meta OpenXR vendor native files,
  - downloaded mobile APK signature verifies and remains non-XR.

## 2026-06-29

- User installed `v0.2.1` on Quest and reported two release blockers:
  - package could not be installed over the previous version without uninstalling,
  - Quest app starts and immediately stops.
- Confirmed signing root cause:
  - `v0.2.0` Quest release cert SHA-256 was `e50a6184078b2dfa0796499279f38458f39aff0ec71652a8d2a3038efca483a0`,
  - `v0.2.1` Quest release cert SHA-256 was `02fab2dc3178426bd90df0c8060cebccc0fca52bbc280f50960773faa5cce424`,
  - CI had generated a fresh debug keystore per release, so Android correctly rejected upgrade installs.
- Created persistent Hidefall upload signing key and stored it in GitHub Secrets:
  - `HIDEFALL_ANDROID_KEYSTORE_BASE64`,
  - `HIDEFALL_ANDROID_KEYSTORE_PASSWORD`,
  - `HIDEFALL_ANDROID_KEY_ALIAS`,
  - `HIDEFALL_ANDROID_KEY_PASSWORD`,
  - `HIDEFALL_ANDROID_CERT_SHA256`.
- Committed public upload certificate SHA-256 fingerprint in `tools/android-signing-cert.sha256`: `9359b8114e04f13b7e6bf3b626be57c8d1e3e195eb67cb86d908122694f414aa`.
- Added CI/release signing support:
  - `tools/configure_godot_android.py` now decodes secret keystore bytes when present and patches Android export signing settings for the build,
  - `tools/require_release_signing.sh` fails release CI if any signing secret is missing,
  - Release workflow passes the signing secrets and runs `make require-release-signing`,
  - Test And Build workflow passes signing secrets when available, so push builds verify the upload key too,
  - `tools/verify_android_artifacts.sh` now verifies Quest/mobile APKs use the same cert and enforces `HIDEFALL_ANDROID_CERT_SHA256` when present.
- Startup crash hardening for `v0.2.2`:
  - bumped Android version metadata to `0.2.2` / code `4`,
  - changed OpenXR startup blend mode from alpha blend to opaque,
  - disabled Meta passthrough at project/export startup,
  - gated runtime passthrough negotiation behind the project passthrough setting,
  - added Godot tests asserting OpenXR is enabled but starts opaque and does not request Meta passthrough during startup.
- Added `tools/quest_smoke_test.sh` and `make smoke-quest-apk`:
  - requires one authorized Quest/Android device visible to ADB,
  - installs with `adb install -r -d`,
  - launches the package,
  - captures logcat to `build/quest-smoke/quest-smoke-logcat.txt`,
  - fails if the package is not running after launch or crash/OpenXR error markers appear.
- Checked ADB locally; no Quest device was connected/authorized, so live logcat crash diagnosis could not be pulled from this machine.
- Local verification after signing/startup changes:
  - `conda run -n hidefall make test` passes,
  - `conda run -n hidefall make build-apks` passes outside the sandbox,
  - `conda run -n hidefall make verify-apks` passes,
  - `source /tmp/hidefall-upload-signing.env && make require-release-signing` passes for the temporary local copy of the same signing env that was written to GitHub Secrets.
- Pushed commit `c6c2234` to `master`.
- GitHub Actions Test And Build run `28414301811` passed for `master` on commit `c6c2234`:
  - `test` passed,
  - `android-apks` passed,
  - `Verify APK artifacts` passed with the upload signing certificate secret.
- Tagged and pushed `v0.2.2` at commit `c6c2234`.
- Release workflow run `28414437594` passed:
  - release signing secret gate passed,
  - tests passed,
  - both APKs built,
  - `Verify APK artifacts` passed,
  - checksums and release notes were written,
  - GitHub Release creation passed.
- Tag-triggered Test And Build run `28414437569` passed:
  - `test` passed,
  - `android-apks` passed,
  - `Verify APK artifacts` passed.
- Confirmed GitHub Release `v0.2.2` exists:
  - URL: https://github.com/mjcipriano/hide-fall/releases/tag/v0.2.2
  - title: `Hidefall 0.2.2`
  - published: 2026-06-30T01:43:28Z
  - attached assets: `hidefall-quest-debug.apk`, `hidefall-mobile-debug.apk`, `SHA256SUMS`.
- Downloaded release assets to `/tmp/hidefall-release-v0.2.2` and verified:
  - `sha256sum -c SHA256SUMS` passes,
  - `HIDEFALL_ENFORCE_UPLOAD_SIGNING=1 tools/verify_android_artifacts.sh /tmp/hidefall-release-v0.2.2/hidefall-quest-debug.apk /tmp/hidefall-release-v0.2.2/hidefall-mobile-debug.apk` passes,
  - downloaded Quest/mobile APKs are signed with the persistent upload certificate,
  - downloaded Quest APK still contains immersive OpenXR/Quest manifest entries plus packaged Meta OpenXR vendor native files,
  - downloaded mobile APK remains non-XR.

## Next

1. Run `make smoke-quest-apk` with a connected Quest before headset testing when hardware is available.
2. Test `v0.2.2` on Quest; one uninstall may be required when moving from `v0.2.1` to the first upload-key-signed build, but later builds should install over it.
3. Re-enable passthrough only after an ADB smoke test proves the opaque immersive VR startup path works on Quest.
4. Add deeper reconnect/network interruption tests and production/store AAB signing if needed.

## 2026-06-30

- User connected Quest 3 via Windows ADB from WSL; device was visible as `2G97C5ZH6J00SH device product:eureka model:Quest_3`.
- Reproduced the headset failure with `tools/quest_smoke_test.sh`:
  - install over the existing package succeeds when using the persistent upload signing key,
  - Horizon launches the app as immersive VR (`ActivityTaskManager` reports the Hidefall activity as immersive),
  - the app process starts, but then dies before the Godot scene runs.
- Pulled focused app logs from `build/quest-smoke/quest-smoke-logcat.txt`:
  - `GodotPluginRegistry` initializes `GodotOpenXR`,
  - `GodotOpenXR` loads `libgodotopenxrvendors.so`,
  - OpenXR instance creation succeeds on the Oculus runtime (`OpenXR 1.1.54`, runtime `Oculus 204.201.0`),
  - crash root cause is Vulkan device creation through OpenXR:
    - `invalid vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateDevice") call`,
    - `OpenXR: Failed to create Vulkan device [ XR_ERROR_VALIDATION_FAILURE ]`,
    - `ERROR: Unable to create DisplayServer, all display drivers failed`,
    - native `SIGSEGV` follows in `VkThread`.
- Fixed the earlier packaging regression:
  - Quest export now packages the Godot OpenXR Vendors addon and enables the Meta plugin,
  - `tools/prepare_android_xr_template.py` explicitly adds the local `godotopenxr-meta` AAR dependency for custom Gradle exports,
  - artifact verifier now requires `lib/arm64-v8a/libgodotopenxrvendors.so`, `assets/addons/godotopenxrvendors/plugin.gdextension`, and `org.godotengine.plugin.v2.GodotOpenXR`.
- Hardened Quest manifest generation:
  - main manifest now includes OpenXR runtime broker queries and `org.khronos.openxr.permission.OPENXR` / `OPENXR_SYSTEM`, so release builds do not rely on the debug manifest overlay,
  - Gradle manifest post-processing also checks `src/release/AndroidManifest.xml`,
  - Quest launcher filter still requires `LAUNCHER`, `com.oculus.intent.category.VR`, and `org.khronos.openxr.intent.category.IMMERSIVE_HMD` with no `HOME`.
- Switched APK production to release exports to avoid debug Vulkan validation layers:
  - `make build-apks` now writes `build/hidefall-quest.apk` and `build/hidefall-mobile.apk` using `--export-release`,
  - release workflow attaches versioned assets `hidefall-quest-<version>.apk` and `hidefall-mobile-<version>.apk`,
  - verifier rejects Quest APKs containing Vulkan validation layer artifacts,
  - CI artifact is now `hidefall-release-apks`.
- Improved `tools/quest_smoke_test.sh`:
  - default APK is `build/hidefall-quest.apk`,
  - clears logcat after install, not before install,
  - captures the full post-launch logcat instead of a 2,000-line tail.
- Local verification completed:
  - `conda run -n hidefall make test` passes after the release/export changes.
- Local verification blocked:
  - non-escalated `conda run -n hidefall make build-apks` fails in this sandbox because Gradle must open a daemon socket and gets `java.net.SocketException: Operation not permitted`,
  - an escalated ADB/logcat command was rejected by the environment usage limit at 2026-06-30 before release APK build/install/smoke could be rerun.

## Next

1. Get explicit user approval to resume escalated commands after the usage-limit rejection.
2. Run an upload-signed release build outside the sandbox:
   `set -a; source /tmp/hidefall-upload-signing.env; set +a; conda run -n hidefall make build-apks`.
3. Restore any signing secrets that `tools/configure_godot_android.py` writes into `game/export_presets.cfg` before committing.
4. Run `HIDEFALL_ENFORCE_UPLOAD_SIGNING=1 conda run -n hidefall make verify-apks`.
5. Install and smoke-test `build/hidefall-quest.apk` on the connected Quest via Windows ADB.
6. If release smoke passes, commit, push, watch GitHub Actions, tag the next version, confirm the release workflow attaches versioned APK assets, download them, verify checksums/APK contents, and smoke-test the released Quest APK.

## 2026-06-30 Retry

- User approved retry after reconnecting the Quest.
- Built upload-signed release APKs successfully outside the sandbox:
  - `build/hidefall-quest.apk` (80 MB),
  - `build/hidefall-mobile.apk` (26 MB).
- Restored `game/export_presets.cfg` signing fields back to non-secret placeholder values after the signed build.
- Verified release APK artifacts locally:
  - `HIDEFALL_ENFORCE_UPLOAD_SIGNING=1 conda run -n hidefall make verify-apks` passes,
  - Quest/mobile APKs are signed by the same persistent upload certificate,
  - Quest APK contains `lib/arm64-v8a/libgodotopenxrvendors.so`, `lib/arm64-v8a/libopenxr_loader.so`, `assets/addons/godotopenxrvendors/plugin.gdextension`, and the OpenXR action map,
  - Quest APK verifier rejected no Vulkan validation layer artifacts,
  - mobile APK remains non-XR and does not include Quest OpenXR vendor binaries.
- Could not rerun Quest smoke test because Windows ADB did not see any connected device:
  - `powershell.exe ... adb.exe devices -l` returned only `List of devices attached`,
  - direct `/mnt/c/Users/mcipr/AppData/Local/Android/Sdk/platform-tools/adb.exe devices -l` also returned an empty list,
  - after `adb kill-server` / `adb start-server`, the device list stayed empty,
  - a 24-poll direct ADB loop over roughly two minutes stayed empty.

## Next

1. Make Windows ADB show the Quest in `adb devices -l`; if it appears as `unauthorized`, put on the headset and accept the USB debugging prompt.
2. Run `ADB=/mnt/c/Users/mcipr/AppData/Local/Android/Sdk/platform-tools/adb.exe HIDEFALL_QUEST_SMOKE_SECONDS=12 tools/quest_smoke_test.sh build/hidefall-quest.apk`.
3. If smoke passes, commit the release-path changes, push, watch GitHub Actions, tag the next version, and verify the GitHub release artifacts.

## 2026-06-30 Quest Reconnect Attempt

- Retried after the headset was disconnected/reconnected.
- Windows ADB still reported zero devices from both Android SDK ADB and Oculus Developer Hub ADB:
  - `/mnt/c/Users/mcipr/AppData/Local/Android/Sdk/platform-tools/adb.exe devices -l`,
  - `/mnt/c/Program Files/Oculus Developer Hub/resources/bin/adb.exe devices -l`.
- Windows PnP/WMI diagnostics showed Oculus/Meta Link virtual devices, but no Quest/Android USB debug interface:
  - no `VID_2833` Meta/Quest device,
  - no `VID_18D1` Android debug device,
  - no ADB/Android/Quest PnP device row.
- `tools/quest_smoke_test.sh build/hidefall-quest.apk` correctly refused to run because it found zero authorized Android devices.
- User reported the headset battery is low and will charge it before the next ADB retry.

## Next

1. After the headset charges, reconnect it directly over USB, wake it, and keep it out of Oculus/Meta Link if Link prevents the Android USB debug interface from enumerating.
2. Confirm Windows ADB shows one Quest row with `adb devices -l`; if it shows `unauthorized`, accept the USB debugging prompt in-headset.
3. Run `ADB=/mnt/c/Users/mcipr/AppData/Local/Android/Sdk/platform-tools/adb.exe HIDEFALL_QUEST_SMOKE_SECONDS=12 tools/quest_smoke_test.sh build/hidefall-quest.apk`.
4. If smoke passes, commit, push, watch GitHub Actions, tag `v0.2.3`, verify release APK assets and checksums, then smoke-test the downloaded release Quest APK.

## 2026-06-30 ADB Authorization Attempt

- Quest is now visible to Windows ADB as serial `2G97C5ZH6J00SH`, but remains `unauthorized`.
- Restarted Windows ADB and forced transport reconnects; state stayed `unauthorized`.
- Backed up/regenerated Windows ADB host keys under `%USERPROFILE%\.android`:
  - existing keys moved to timestamped `.bak-20260630-134917` files,
  - new `adbkey` / `adbkey.pub` generated at 2026-06-30 13:49.
- After the fresh host key, ADB still reported:
  - `2G97C5ZH6J00SH unauthorized transport_id:1`.
- Launched Oculus Developer Hub from `C:\Program Files\Oculus Developer Hub\Oculus Developer Hub.exe`; raw ADB state remained unauthorized.
- User does not see the authorization prompt in-headset yet.

## Next

1. Put on the headset in standalone Quest home, not inside Quest Link/PCVR.
2. Unlock/wake the headset, then unplug/replug USB while wearing it and accept the `Allow USB debugging?` prompt. Check `Always allow from this computer` if offered.
3. If the prompt still does not appear, open Oculus Developer Hub on Windows and check the device panel for setup/authorization prompts, or use the headset settings path for Developer options to revoke/reset USB debugging authorizations.
4. Once `adb devices -l` shows `2G97C5ZH6J00SH device`, run `ADB=/mnt/c/Users/mcipr/AppData/Local/Android/Sdk/platform-tools/adb.exe HIDEFALL_QUEST_SMOKE_SECONDS=12 tools/quest_smoke_test.sh build/hidefall-quest.apk`.

## 2026-06-30 Authorization Retry

- Retried after user attempted another headset-side change.
- Android SDK ADB still reports `2G97C5ZH6J00SH unauthorized`.
- Oculus Developer Hub is running on Windows.
- Forced reconnect with Oculus Developer Hub's bundled ADB; transport id changed, but state remained `unauthorized`.
- Smoke test is still blocked because ADB install/logcat commands cannot run without an authorized transport.

## Next

1. In Oculus Developer Hub on Windows, inspect the device connection panel for the Quest and complete any authorization/setup prompt it shows.
2. In the headset, stay in standalone Quest Home, not Link, and look for the `Allow USB debugging?` dialog after unplug/replug.
3. If still missing, use the headset's developer settings to revoke/reset USB debugging authorizations, then reconnect and accept the new prompt.
4. Re-run `adb devices -l`; continue only once the row says `device` instead of `unauthorized`.

## 2026-06-30 Engine Compatibility / Quest Runtime Work

- Quest ADB authorization was resolved; Windows ADB can install and launch to serial `2G97C5ZH6J00SH`.
- Confirmed install-over works with the persistent upload signing key:
  - `tools/quest_smoke_test.sh` installs with `adb install -r -d`,
  - installs over prior `com.mjcipriano.hidefall.quest` builds succeeded repeatedly without uninstalling.
- Godot `4.7-stable` is not viable on this Quest runtime:
  - APK launches as immersive after manifest fixes,
  - native startup fails before GDScript with OpenXR/Vulkan device creation errors:
    `OpenXR: Failed to create Vulkan device [ XR_ERROR_VALIDATION_FAILURE ]`,
    `Couldn't create a Vulkan device through the VulkanHooks singleton`,
    `Unable to create DisplayServer`,
    followed by a native `SIGSEGV`.
- Switched tooling to official `godotengine/godot-builds` downloads and made Android source template extraction version-aware.
- Tested Godot `4.6.3-stable`:
  - official editor/templates installed,
  - signed Quest/mobile APKs built,
  - `HIDEFALL_ENFORCE_UPLOAD_SIGNING=1 make verify-apks` passed,
  - Quest install-over and immersive launch succeeded,
  - app remained running and Horizon reported it as the foreground immersive app,
  - runtime log repeatedly emitted Godot render errors:
    `Pre-raster shader (vertex shader) is not provided for pipeline creation`,
    `Condition "!variants_enabled[p_variant]" is true`,
    `Condition "shader.is_null()" is true`,
    `tonemapper_subpass`.
- Fixed one game-code issue found during 4.6.3 smoke:
  - compacted host join QR payload to fit the version 5-L QR capacity,
  - added a test assertion that `get_join_payload_text()` is at most 106 bytes.
- Tightened `tools/quest_smoke_test.sh`:
  - no longer fails on generic Quest runtime warnings or unrelated `AndroidRuntime: VM exiting with result code 0`,
  - does fail on app death, native crash markers, OpenXR/Vulkan startup failures, and unignored Godot errors.
- Tested Godot `4.5.2-stable`:
  - signed APK built after making the patcher handle root-level Android manifests,
  - verifier failed because `lib/arm64-v8a/libopenxr_loader.so` was missing,
  - headset smoke showed the current OpenXR Vendors addon requires Godot 4.6+ and OpenXR loader was missing:
    `GDExtension only compatible with Godot version 4.6.0 or later`,
    `OpenXR loader not found`.
  - 4.5.2 is therefore not viable with the current addon.
- Tested Godot `4.6.2-stable`:
  - official editor/templates installed,
  - signed Quest/mobile APKs built,
  - `HIDEFALL_ENFORCE_UPLOAD_SIGNING=1 make verify-apks` passed,
  - headset install-over and immersive launch succeeded,
  - runtime had the same repeated Godot render errors as 4.6.3.
- Began testing whether switching from Forward Mobile to Forward+ avoids the headset render errors, but did not ship that direction. The final working path is Godot `4.6.2-stable` plus `renderer/rendering_method="gl_compatibility"`.

## 2026-06-30 Compatibility Renderer Pass

- Searched for upstream/primary guidance and found Godot's Android XR deployment docs recommend the Compatibility/OpenGL renderer path for Android XR over the experimental/rough Vulkan Mobile renderer path.
- Set `game/project.godot` to `renderer/rendering_method="gl_compatibility"` and added a validator guard so future changes do not accidentally move the project back to the failing Vulkan renderer path.
- Cleaned generated Godot state and rebuilt a signed Quest APK with Godot `4.6.2-stable`.
- Restored `game/export_presets.cfg` signing fields to placeholders after signing.
- Quest smoke passed over Windows ADB:
  - command: `ADB=/mnt/c/Users/mcipr/AppData/Local/Android/Sdk/platform-tools/adb.exe HIDEFALL_QUEST_SMOKE_SECONDS=12 tools/quest_smoke_test.sh build/hidefall-quest.apk`,
  - install-over succeeded,
  - process stayed running,
  - no unignored Godot errors were found in `build/quest-smoke/quest-smoke-logcat.txt`.
- Rebuilt the signed mobile APK with the same upload signing key and restored signing placeholders again.
- `HIDEFALL_ENFORCE_UPLOAD_SIGNING=1 make verify-apks` passed for both APKs.
- The first `make test` attempt hung during local desktop OpenXR probing. Updated the test target to use `--xr-mode off`; Quest XR startup remains covered by the ADB smoke test.
- `make test` now passes with Godot `4.6.2-stable`.

## 2026-06-30 v0.2.3 Release Verification

- Committed and pushed `17c189d Fix Quest XR release builds` to `master`.
- GitHub Actions `Test And Build` run `28481243164` passed:
  - Godot tests passed,
  - Android APK build passed,
  - APK artifact verification passed,
  - CI uploaded the branch APK artifacts.
- Tagged and pushed `v0.2.3`.
- GitHub Actions `Release` run `28481436288` passed:
  - signing secrets were present,
  - tests passed,
  - release APKs built,
  - release APK artifact verification passed,
  - `Hidefall 0.2.3` was published.
- Verified GitHub release assets:
  - `hidefall-quest-0.2.3.apk`,
  - `hidefall-mobile-0.2.3.apk`,
  - `SHA256SUMS`.
- Downloaded release assets to `/tmp/hidefall-release-v0.2.3.mH4Dd8`.
- `sha256sum -c SHA256SUMS` passed for both APKs.
- `HIDEFALL_ENFORCE_UPLOAD_SIGNING=1 tools/verify_android_artifacts.sh /tmp/hidefall-release-v0.2.3.mH4Dd8/hidefall-quest-0.2.3.apk /tmp/hidefall-release-v0.2.3.mH4Dd8/hidefall-mobile-0.2.3.apk` passed.
- Release Quest APK smoke passed over Windows ADB:
  - command: `ADB=/mnt/c/Users/mcipr/AppData/Local/Android/Sdk/platform-tools/adb.exe HIDEFALL_QUEST_SMOKE_SECONDS=12 tools/quest_smoke_test.sh /tmp/hidefall-release-v0.2.3.mH4Dd8/hidefall-quest-0.2.3.apk`,
  - install-over succeeded,
  - process stayed running,
  - log saved to `build/quest-smoke/quest-smoke-logcat.txt`.

## 2026-06-30 v0.2.4 Gameplay/MR Fix

- Fixed the Quest app launching into an effectively empty lobby:
  - headset launches now auto-start a solo bot round,
  - 78 props are spawned and visible immediately in object-rain phase,
  - desktop/headless local tests still start in lobby for deterministic testing.
- Added persistent XR UI:
  - head-locked status panel and phase banner,
  - QR/status fallback remains in the larger panel,
  - left-controller wrist menu shows phase, time, shots, scans, prop count, and room code.
- Enabled the Meta passthrough path:
  - `xr/openxr/extensions/meta/passthrough=true`,
  - Quest export `meta_xr_features/passthrough=true`,
  - Android template patcher now adds required `com.oculus.feature.PASSTHROUGH`,
  - APK verifier fails if Quest APK lacks passthrough or mobile APK contains XR/passthrough metadata.
- Hardened Quest smoke:
  - requires `Hidefall visible gameplay ready: ... objects=...`,
  - dismisses/removes the Quest Link reprojected OS dialog when it blocks ADB-launched apps,
  - still fails on app death, crash/OpenXR startup errors, and unignored Godot errors.
- Bumped Android version to `0.2.4` / code `6`.
- Local validation passed:
  - `make test`,
  - signed `make build-apks`,
  - `HIDEFALL_ENFORCE_UPLOAD_SIGNING=1 make verify-apks`,
  - `git diff --check`.
- Quest smoke passed over Windows ADB for `build/hidefall-quest.apk`:
  - install-over succeeded,
  - process stayed running,
  - log showed `Hidefall visible gameplay ready: phase=object_rain objects=78 object_nodes=78 xr=OpenXR immersive passthrough`,
  - manifest showed `versionCode=6`, `versionName=0.2.4`, and `com.oculus.feature.PASSTHROUGH`.
- Committed and pushed `1058f57 Make Quest launch into playable MR round`.
- GitHub Actions `Test And Build` run `28483160118` passed:
  - Godot tests passed,
  - Android APK build passed,
  - APK artifact verification passed,
  - CI uploaded branch APK artifacts.
- Tagged and pushed `v0.2.4`.
- GitHub Actions `Release` run `28483331168` passed:
  - signing secrets were present,
  - tests passed,
  - release APKs built,
  - release APK artifact verification passed,
  - `Hidefall 0.2.4` was published.
- Verified GitHub release assets:
  - `hidefall-quest-0.2.4.apk`,
  - `hidefall-mobile-0.2.4.apk`,
  - `SHA256SUMS`.
- Downloaded release assets to `/tmp/hidefall-release-v0.2.4.o1gpXw`.
- `sha256sum -c SHA256SUMS` passed for both APKs.
- `HIDEFALL_ENFORCE_UPLOAD_SIGNING=1 tools/verify_android_artifacts.sh /tmp/hidefall-release-v0.2.4.o1gpXw/hidefall-quest-0.2.4.apk /tmp/hidefall-release-v0.2.4.o1gpXw/hidefall-mobile-0.2.4.apk` passed.
- Release Quest APK smoke passed over Windows ADB:
  - command: `ADB=/mnt/c/Users/mcipr/AppData/Local/Android/Sdk/platform-tools/adb.exe HIDEFALL_QUEST_SMOKE_SECONDS=12 tools/quest_smoke_test.sh /tmp/hidefall-release-v0.2.4.o1gpXw/hidefall-quest-0.2.4.apk`,
  - install-over succeeded,
  - process stayed running,
  - log showed `Hidefall visible gameplay ready: phase=object_rain objects=78 object_nodes=78 xr=OpenXR immersive passthrough`,
  - log saved to `build/quest-smoke/quest-smoke-logcat.txt`.

## Next

1. No release-blocking work is open for `v0.2.4`.
2. If the user reports another headset issue, start from `build/quest-smoke/quest-smoke-logcat.txt`, rerun the released APK smoke test, and compare against the passing `v0.2.4` release assets.
3. Non-blocking cleanup: update GitHub Actions setup-miniconda options to remove deprecation annotations for `auto-activate-base` and implicit `defaults` channel.
