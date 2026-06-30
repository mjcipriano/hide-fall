# Build And Release

Current local build targets:

```bash
conda activate hidefall
make install-godot
make install-export-templates
make install-android-sdk
make build-apks
make verify-apks
```

Outputs:

- `build/hidefall-quest.apk`
- `build/hidefall-mobile.apk`

Local APKs are signed with a generated local debug keystore at `tools/android-keystore/debug.keystore` unless the Hidefall upload-key environment variables are present. This file is ignored by git and recreated by `make create-debug-keystore`.

Release APKs are signed with a persistent Hidefall upload key stored in GitHub Secrets:

- `HIDEFALL_ANDROID_KEYSTORE_BASE64`
- `HIDEFALL_ANDROID_KEYSTORE_PASSWORD`
- `HIDEFALL_ANDROID_KEY_ALIAS`
- `HIDEFALL_ANDROID_KEY_PASSWORD`
- `HIDEFALL_ANDROID_CERT_SHA256`

The public upload certificate SHA-256 fingerprint is tracked in `tools/android-signing-cert.sha256`. Release CI fails before building if any signing secret is missing, and `make verify-apks` checks the release certificate when `HIDEFALL_ANDROID_CERT_SHA256` is set.

Because `v0.2.0` and `v0.2.1` were signed by ephemeral CI debug keys, moving from either of those builds to the first upload-key-signed build may still require one uninstall. Builds after that should install over the existing package as long as the package name and upload key remain unchanged.

GitHub Actions runs tests and builds both release APKs, then uploads them as the `hidefall-release-apks` artifact.

The Quest preset intentionally uses the Android Gradle build template. `make build-quest-apk` prepares that generated template under ignored `game/android/` and injects the Godot OpenXR Vendors Meta AAR dependency. `make verify-apks` verifies signatures, Quest/OpenXR immersive manifest categories, packaged OpenXR vendor files, and confirms the mobile APK has no XR manifest or vendor binary entries.

Useful low-level local post-build checks:

```bash
tools/android-sdk/build-tools/36.1.0/apksigner verify --verbose build/hidefall-quest.apk
tools/android-sdk/build-tools/36.1.0/aapt dump xmltree build/hidefall-quest.apk AndroidManifest.xml | rg "com.oculus.intent.category.VR|IMMERSIVE_HMD|GodotOpenXR|vr.headtracking|OPENXR"
tools/android-sdk/build-tools/36.1.0/apksigner verify --verbose build/hidefall-mobile.apk
tools/android-sdk/build-tools/36.1.0/aapt dump xmltree build/hidefall-mobile.apk AndroidManifest.xml | rg "com.oculus.intent.category.VR|IMMERSIVE_HMD|GodotOpenXR|vr.headtracking|OPENXR" || true
```

The Quest manifest query should find immersive/OpenXR entries. The mobile manifest query should return no matches.

## Quest Smoke Test

With one authorized Quest connected over USB or wireless ADB:

```bash
make smoke-quest-apk
```

The smoke test installs the Quest APK with `adb install -r -d`, launches the package, waits briefly, captures logcat to `build/quest-smoke/quest-smoke-logcat.txt`, confirms the process is still running, and fails on crash/OpenXR error markers. This cannot run in GitHub Actions without Quest hardware, but it is the local hardware gate before asking someone to test in-headset.

## GitHub Releases

Versioned releases are created from tags named `vX.Y.Z`. Use a new tag for each published build; do not move an existing release tag.

```bash
git tag -a v0.2.1 -m "Hidefall 0.2.1"
git push origin v0.2.1
```

The `Release` workflow builds the APKs from the tag, verifies signatures, verifies the upload certificate, writes `SHA256SUMS`, creates a GitHub Release titled `Hidefall X.Y.Z`, and attaches:

- `hidefall-quest-<version>.apk`
- `hidefall-mobile-<version>.apk`
- `SHA256SUMS`

The workflow can also be started manually from GitHub Actions with the same tag value.

Store AAB signing remains to be configured separately if a store track is needed. Do not commit keystores, downloaded templates, or build outputs.
