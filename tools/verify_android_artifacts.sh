#!/usr/bin/env bash
set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-tools/android-sdk}"
ANDROID_SDK_ROOT="$(python -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${ANDROID_SDK_ROOT}")"
BUILD_TOOLS_VERSION="${ANDROID_BUILD_TOOLS_VERSION:-36.1.0}"
BUILD_TOOLS_DIR="${ANDROID_SDK_ROOT}/build-tools/${BUILD_TOOLS_VERSION}"

if [[ ! -x "${BUILD_TOOLS_DIR}/apksigner" || ! -x "${BUILD_TOOLS_DIR}/aapt" ]]; then
  echo "Android build tools ${BUILD_TOOLS_VERSION} not found under ${ANDROID_SDK_ROOT}" >&2
  exit 1
fi

quest_apk="${1:-build/hidefall-quest-debug.apk}"
mobile_apk="${2:-build/hidefall-mobile-debug.apk}"

test -f "${quest_apk}"
test -f "${mobile_apk}"

"${BUILD_TOOLS_DIR}/apksigner" verify --verbose "${quest_apk}"
"${BUILD_TOOLS_DIR}/apksigner" verify --verbose "${mobile_apk}"

quest_manifest="$("${BUILD_TOOLS_DIR}/aapt" dump xmltree "${quest_apk}" AndroidManifest.xml)"
required_quest_entries=(
  'android:versionName.*"0.2.1"'
  'org.khronos.openxr.permission.OPENXR'
  'org.khronos.openxr.permission.OPENXR_SYSTEM'
  'android.hardware.vr.headtracking'
  'com.oculus.intent.category.VR'
  'org.khronos.openxr.intent.category.IMMERSIVE_HMD'
  'com.oculus.supportedDevices'
  'org.godotengine.plugin.v2.GodotOpenXR'
)

for pattern in "${required_quest_entries[@]}"; do
  if ! rg -q "${pattern}" <<< "${quest_manifest}"; then
    echo "Quest APK is missing required manifest entry matching: ${pattern}" >&2
    exit 1
  fi
done

quest_contents="$(unzip -l "${quest_apk}")"
required_quest_files=(
  'lib/arm64-v8a/libgodotopenxrvendors.so'
  'lib/arm64-v8a/libopenxr_loader.so'
  'assets/addons/godotopenxrvendors/plugin.gdextension'
  'openxr_action_map'
)

for pattern in "${required_quest_files[@]}"; do
  if ! rg -q "${pattern}" <<< "${quest_contents}"; then
    echo "Quest APK is missing packaged OpenXR file matching: ${pattern}" >&2
    exit 1
  fi
done

mobile_manifest="$("${BUILD_TOOLS_DIR}/aapt" dump xmltree "${mobile_apk}" AndroidManifest.xml)"
if rg -q 'com.oculus.intent.category.VR|org.khronos.openxr.intent.category.IMMERSIVE_HMD|org.godotengine.plugin.v2.GodotOpenXR|android.hardware.vr.headtracking|org.khronos.openxr.permission.OPENXR' <<< "${mobile_manifest}"; then
  echo "Mobile APK unexpectedly contains XR manifest entries" >&2
  exit 1
fi
if ! rg -q 'android:versionName.*"0.2.1"' <<< "${mobile_manifest}"; then
  echo "Mobile APK versionName is not 0.2.1" >&2
  exit 1
fi

mobile_contents="$(unzip -l "${mobile_apk}")"
if rg -q 'libgodotopenxrvendors|libopenxr_loader|assets/addons/godotopenxrvendors' <<< "${mobile_contents}"; then
  echo "Mobile APK unexpectedly contains Quest OpenXR vendor binaries" >&2
  exit 1
fi

echo "Android APK artifact verification passed"
