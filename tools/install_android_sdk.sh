#!/usr/bin/env bash
set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-tools/android-sdk}"
ANDROID_SDK_ROOT="$(python -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${ANDROID_SDK_ROOT}")"
CMDLINE_VERSION="${CMDLINE_VERSION:-13114758}"
CMDLINE_ZIP="/tmp/android-commandlinetools.zip"
CMDLINE_UNPACK="/tmp/android-commandlinetools"
CMDLINE_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_VERSION}_latest.zip"
SDKMANAGER="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"

mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"
curl -L --fail --show-error --output "${CMDLINE_ZIP}" "${CMDLINE_URL}"
rm -rf "${CMDLINE_UNPACK}" "${ANDROID_SDK_ROOT}/cmdline-tools/latest"
unzip -o "${CMDLINE_ZIP}" -d "${CMDLINE_UNPACK}"
mv "${CMDLINE_UNPACK}/cmdline-tools" "${ANDROID_SDK_ROOT}/cmdline-tools/latest"

set +o pipefail
yes | "${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" --licenses >/dev/null
set -o pipefail
"${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" "platform-tools"
"${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" "platforms;android-35"
"${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" "build-tools;35.0.0"
"${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" "platforms;android-36"
"${SDKMANAGER}" --sdk_root="${ANDROID_SDK_ROOT}" "build-tools;36.1.0"

test -x "${ANDROID_SDK_ROOT}/platform-tools/adb"
test -x "${ANDROID_SDK_ROOT}/build-tools/36.1.0/apksigner"
