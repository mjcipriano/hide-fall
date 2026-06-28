# Build And Release

Current local build targets:

```bash
conda activate hidefall
make install-godot
make install-export-templates
make install-android-sdk
make build-apks
```

Outputs:

- `build/hidefall-quest-debug.apk`
- `build/hidefall-mobile-debug.apk`

Debug APKs are signed with a generated local debug keystore at `tools/android-keystore/debug.keystore`. This file is ignored by git and recreated by `make create-debug-keystore`.

GitHub Actions runs tests and builds both debug APKs, then uploads them as the `hidefall-debug-apks` artifact.

Release signing remains to be configured outside git. Target path:

1. Create a release keystore outside git.
2. Add CI secrets for release keystore bytes, alias, and passwords.
3. Add release export presets or CI-time preset patching.
4. Build signed release APKs/AABs.
5. Attach release artifacts to GitHub Releases.

Do not commit keystores, downloaded templates, or build outputs.
