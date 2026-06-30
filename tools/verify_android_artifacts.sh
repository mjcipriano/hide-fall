#!/usr/bin/env bash
set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-tools/android-sdk}"
ANDROID_SDK_ROOT="$(python -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${ANDROID_SDK_ROOT}")"
BUILD_TOOLS_VERSION="${ANDROID_BUILD_TOOLS_VERSION:-36.1.0}"
BUILD_TOOLS_DIR="${ANDROID_SDK_ROOT}/build-tools/${BUILD_TOOLS_VERSION}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_VERSION_NAME="${HIDEFALL_EXPECTED_VERSION_NAME:-$(grep -m1 '^version/name=' "${ROOT}/game/export_presets.cfg" | sed -E 's/version\/name="([^"]+)"/\1/')}"
EXPECTED_CERT_SHA256="${HIDEFALL_ANDROID_CERT_SHA256:-}"
if [[ -z "${EXPECTED_CERT_SHA256}" && "${HIDEFALL_ENFORCE_UPLOAD_SIGNING:-0}" == "1" && -f "${ROOT}/tools/android-signing-cert.sha256" ]]; then
  EXPECTED_CERT_SHA256="$(tr -d '[:space:]' < "${ROOT}/tools/android-signing-cert.sha256")"
fi

if [[ ! -x "${BUILD_TOOLS_DIR}/apksigner" || ! -x "${BUILD_TOOLS_DIR}/aapt" ]]; then
  echo "Android build tools ${BUILD_TOOLS_VERSION} not found under ${ANDROID_SDK_ROOT}" >&2
  exit 1
fi

quest_apk="${1:-build/hidefall-quest.apk}"
mobile_apk="${2:-build/hidefall-mobile.apk}"

test -f "${quest_apk}"
test -f "${mobile_apk}"

"${BUILD_TOOLS_DIR}/apksigner" verify --verbose "${quest_apk}"
"${BUILD_TOOLS_DIR}/apksigner" verify --verbose "${mobile_apk}"

quest_cert="$("${BUILD_TOOLS_DIR}/apksigner" verify --print-certs "${quest_apk}")"
mobile_cert="$("${BUILD_TOOLS_DIR}/apksigner" verify --print-certs "${mobile_apk}")"
quest_cert_sha="$(sed -n 's/Signer #1 certificate SHA-256 digest: //p' <<< "${quest_cert}")"
mobile_cert_sha="$(sed -n 's/Signer #1 certificate SHA-256 digest: //p' <<< "${mobile_cert}")"
if [[ "${quest_cert_sha}" != "${mobile_cert_sha}" ]]; then
  echo "Quest and mobile APKs are signed by different certificates" >&2
  echo "Quest:  ${quest_cert_sha}" >&2
  echo "Mobile: ${mobile_cert_sha}" >&2
  exit 1
fi
if [[ -n "${EXPECTED_CERT_SHA256}" && "${quest_cert_sha,,}" != "${EXPECTED_CERT_SHA256,,}" ]]; then
  echo "APK signing certificate does not match expected upload certificate" >&2
  echo "Expected: ${EXPECTED_CERT_SHA256}" >&2
  echo "Actual:   ${quest_cert_sha}" >&2
  exit 1
fi

quest_manifest_file="$(mktemp)"
mobile_manifest_file="$(mktemp)"
trap 'rm -f "${quest_manifest_file}" "${mobile_manifest_file}"' EXIT
"${BUILD_TOOLS_DIR}/aapt" dump badging "${quest_apk}" | grep -q "targetSdkVersion:'35'" || {
  echo "Quest APK targetSdkVersion must be 35 for current Quest/OpenXR Vulkan compatibility" >&2
  exit 1
}
"${BUILD_TOOLS_DIR}/aapt" dump xmltree "${quest_apk}" AndroidManifest.xml > "${quest_manifest_file}"
quest_manifest="$(cat "${quest_manifest_file}")"
required_quest_entries=(
  "android:versionName.*\"${EXPECTED_VERSION_NAME}\""
  'org.khronos.openxr.permission.OPENXR'
  'org.khronos.openxr.permission.OPENXR_SYSTEM'
  'android.hardware.vr.headtracking'
  'com.oculus.feature.PASSTHROUGH'
  'com.oculus.permission.HAND_TRACKING'
  'oculus.software.handtracking'
  'com.oculus.handtracking.version'
  'com.oculus.handtracking.frequency'
  'org.godotengine.plugin.v2.GodotOpenXR'
  'com.oculus.intent.category.VR'
  'org.khronos.openxr.intent.category.IMMERSIVE_HMD'
  'com.oculus.supportedDevices'
)

for pattern in "${required_quest_entries[@]}"; do
  if ! grep -Eq "${pattern}" <<< "${quest_manifest}"; then
    echo "Quest APK is missing required manifest entry matching: ${pattern}" >&2
    exit 1
  fi
done
python "${ROOT}/tools/verify_quest_launcher_filter.py" "${quest_manifest_file}"

quest_contents="$(unzip -l "${quest_apk}")"
required_quest_files=(
  'lib/arm64-v8a/libopenxr_loader.so'
  'lib/arm64-v8a/libgodotopenxrvendors.so'
  'assets/addons/godotopenxrvendors/plugin.gdextension'
  'openxr_action_map'
)

for pattern in "${required_quest_files[@]}"; do
  if ! grep -Eq "${pattern}" <<< "${quest_contents}"; then
    echo "Quest APK is missing packaged OpenXR file matching: ${pattern}" >&2
    exit 1
  fi
done
"${BUILD_TOOLS_DIR}/aapt" dump xmltree "${mobile_apk}" AndroidManifest.xml > "${mobile_manifest_file}"
mobile_manifest="$(cat "${mobile_manifest_file}")"
if grep -Eq 'com.oculus.intent.category.VR|org.khronos.openxr.intent.category.IMMERSIVE_HMD|org.godotengine.plugin.v2.GodotOpenXR|android.hardware.vr.headtracking|com.oculus.feature.PASSTHROUGH|oculus.software.handtracking|com.oculus.permission.HAND_TRACKING|org.khronos.openxr.permission.OPENXR' <<< "${mobile_manifest}"; then
  echo "Mobile APK unexpectedly contains XR manifest entries" >&2
  exit 1
fi
if ! grep -Eq "android:versionName.*\"${EXPECTED_VERSION_NAME}\"" <<< "${mobile_manifest}"; then
  echo "Mobile APK versionName is not ${EXPECTED_VERSION_NAME}" >&2
  exit 1
fi

mobile_contents="$(unzip -l "${mobile_apk}")"
if grep -Eq 'libgodotopenxrvendors|libopenxr_loader|assets/addons/godotopenxrvendors' <<< "${mobile_contents}"; then
  echo "Mobile APK unexpectedly contains Quest OpenXR vendor binaries" >&2
  exit 1
fi
if grep -Eiq 'vulkan_validation_layers|VkLayer|libVkLayer' <<< "${quest_contents}"; then
  echo "Quest APK unexpectedly contains Vulkan validation layers" >&2
  exit 1
fi

echo "Android APK artifact verification passed"
