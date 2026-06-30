#!/usr/bin/env bash
set -euo pipefail

APK="${1:-build/hidefall-quest-debug.apk}"
PACKAGE="${HIDEFALL_QUEST_PACKAGE:-com.mjcipriano.hidefall.quest}"
ADB="${ADB:-${ANDROID_SDK_ROOT:-tools/android-sdk}/platform-tools/adb}"
LOG_DIR="${HIDEFALL_QUEST_LOG_DIR:-build/quest-smoke}"
LOG_FILE="${LOG_DIR}/quest-smoke-logcat.txt"

if [[ ! -x "${ADB}" ]]; then
  echo "adb not found at ${ADB}. Run make install-android-sdk first." >&2
  exit 1
fi
if [[ ! -f "${APK}" ]]; then
  echo "APK not found: ${APK}" >&2
  exit 1
fi

devices="$("${ADB}" devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
device_count="$(wc -w <<< "${devices}")"
if [[ "${device_count}" -ne 1 ]]; then
  echo "Expected exactly one authorized Quest/Android device, found ${device_count}." >&2
  "${ADB}" devices -l >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"
"${ADB}" logcat -c
"${ADB}" install -r -d "${APK}"

set +e
"${ADB}" shell monkey -p "${PACKAGE}" -c android.intent.category.LAUNCHER 1 >/dev/null
launch_status=$?
set -e
if [[ "${launch_status}" -ne 0 ]]; then
  echo "Launch command failed for ${PACKAGE}" >&2
  "${ADB}" logcat -d -t 400 > "${LOG_FILE}" || true
  exit 1
fi

sleep "${HIDEFALL_QUEST_SMOKE_SECONDS:-12}"
"${ADB}" logcat -d -t 2000 > "${LOG_FILE}"

pid="$("${ADB}" shell pidof "${PACKAGE}" | tr -d '\r' || true)"
if [[ -z "${pid}" ]]; then
  echo "Quest smoke failed: ${PACKAGE} is not running after launch. Log: ${LOG_FILE}" >&2
  grep -Ei 'AndroidRuntime|FATAL EXCEPTION|crash|tombstone|Godot|OpenXR|Vulkan|SIGSEGV|SIGABRT' "${LOG_FILE}" >&2 || true
  exit 1
fi

if grep -Eiq 'FATAL EXCEPTION|AndroidRuntime|SIGSEGV|SIGABRT|native crash|ANR in|OpenXR.*(failed|error)' "${LOG_FILE}"; then
  echo "Quest smoke failed: crash/error markers found in ${LOG_FILE}" >&2
  grep -Ein 'FATAL EXCEPTION|AndroidRuntime|SIGSEGV|SIGABRT|native crash|ANR in|OpenXR.*(failed|error)' "${LOG_FILE}" >&2 || true
  exit 1
fi

echo "Quest smoke passed for ${PACKAGE} with pid ${pid}. Log: ${LOG_FILE}"
