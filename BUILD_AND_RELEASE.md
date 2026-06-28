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

## GitHub Releases

Versioned releases are created from tags named `vX.Y.Z`. Use a new tag for each published build; do not move an existing release tag.

```bash
git tag -a v0.1.0 -m "Hidefall 0.1.0"
git push origin v0.1.0
```

The `Release` workflow builds the APKs from the tag, verifies their debug signatures, writes `SHA256SUMS`, creates a GitHub Release titled `Hidefall X.Y.Z`, and attaches:

- `hidefall-quest-debug.apk`
- `hidefall-mobile-debug.apk`
- `SHA256SUMS`

The workflow can also be started manually from GitHub Actions with the same tag value.

Release signing remains to be configured outside git for production/store builds. Target path:

1. Create a release keystore outside git.
2. Add CI secrets for release keystore bytes, alias, and passwords.
3. Add release export presets or CI-time preset patching.
4. Build signed release APKs/AABs.
5. Attach signed release artifacts to GitHub Releases.

Do not commit keystores, downloaded templates, or build outputs.
