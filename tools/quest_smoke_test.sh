#!/usr/bin/env bash
set -euo pipefail

APK="${1:-build/hidefall-quest.apk}"
PACKAGE="${HIDEFALL_QUEST_PACKAGE:-com.mjcipriano.hidefall.quest}"
ADB="${ADB:-${ANDROID_SDK_ROOT:-tools/android-sdk}/platform-tools/adb}"
LOG_DIR="${HIDEFALL_QUEST_LOG_DIR:-build/quest-smoke}"
LOG_FILE="${LOG_DIR}/quest-smoke-logcat.txt"
ACTIVITY_FILE="${LOG_DIR}/quest-smoke-activities.txt"
PACKAGE_FILE="${LOG_DIR}/quest-smoke-package.txt"

if [[ ! -x "${ADB}" ]]; then
  echo "adb not found at ${ADB}. Run make install-android-sdk first." >&2
  exit 1
fi
if [[ ! -f "${APK}" ]]; then
  echo "APK not found: ${APK}" >&2
  exit 1
fi

adb_file_arg() {
  local path="$1"
  if [[ "${ADB}" == *.exe && -x "$(command -v wslpath)" ]]; then
    wslpath -w "${path}"
  else
    printf '%s\n' "${path}"
  fi
}

dismiss_horizon_dialog() {
  local task_id=""
  if [[ -f "${ACTIVITY_FILE}" ]]; then
    task_id="$(tr -d '\r' < "${ACTIVITY_FILE}" | awk '
      /\* Task\{/ {
        task = ""
        if (match($0, /#[0-9]+/)) {
          task = substr($0, RSTART + 1, RLENGTH - 1)
        }
      }
      /OculusLinkAvailableDialogActivity/ && task != "" {
        print task
        exit
      }
    ')"
  fi
  if [[ -n "${task_id}" ]]; then
    "${ADB}" shell am stack remove "${task_id}" >/dev/null 2>&1 || true
  fi
  "${ADB}" shell input keyevent KEYCODE_DPAD_CENTER >/dev/null 2>&1 || true
  "${ADB}" shell input keyevent KEYCODE_ENTER >/dev/null 2>&1 || true
  "${ADB}" shell input keyevent KEYCODE_ESCAPE >/dev/null 2>&1 || true
  "${ADB}" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
}

devices="$("${ADB}" devices | tr -d '\r' | awk 'NR > 1 && $2 == "device" { print $1 }')"
device_count="$(wc -w <<< "${devices}")"
if [[ "${device_count}" -ne 1 ]]; then
  echo "Expected exactly one authorized Quest/Android device, found ${device_count}." >&2
  "${ADB}" devices -l >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"
"${ADB}" install -r -d "$(adb_file_arg "${APK}")"
"${ADB}" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
"${ADB}" shell wm dismiss-keyguard >/dev/null 2>&1 || true
"${ADB}" shell input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
"${ADB}" logcat -c

pid=""
launch_status=1
for attempt in 1 2 3; do
  set +e
  "${ADB}" shell monkey -p "${PACKAGE}" -c android.intent.category.LAUNCHER 1 >/dev/null
  launch_status=$?
  set -e
  if [[ "${launch_status}" -ne 0 ]]; then
    echo "Launch command failed for ${PACKAGE} on attempt ${attempt}" >&2
    "${ADB}" logcat -d -t 400 > "${LOG_FILE}" || true
    exit 1
  fi

  sleep "${HIDEFALL_QUEST_SMOKE_SECONDS:-12}"
  "${ADB}" logcat -d > "${LOG_FILE}"
  "${ADB}" shell dumpsys activity activities > "${ACTIVITY_FILE}" || true
  "${ADB}" shell dumpsys package "${PACKAGE}" > "${PACKAGE_FILE}" || true
  pid="$("${ADB}" shell pidof "${PACKAGE}" | tr -d '\r' || true)"
  if [[ -n "${pid}" ]]; then
    break
  fi
  if grep -Eq 'Launch is blocked because: a Reprojected OS dialog is currently showing|OculusLinkAvailableDialogActivity' "${LOG_FILE}" "${ACTIVITY_FILE}"; then
    echo "Quest launch attempt ${attempt} was blocked by a Horizon dialog; dismissing and retrying." >&2
    dismiss_horizon_dialog
    sleep 2
    "${ADB}" logcat -c
    continue
  fi
  break
done

if [[ -z "${pid}" ]]; then
  echo "Quest smoke failed: ${PACKAGE} is not running after launch. Log: ${LOG_FILE}" >&2
  if grep -Eq 'Launch is blocked because: a Reprojected OS dialog is currently showing|OculusLinkAvailableDialogActivity' "${LOG_FILE}" "${ACTIVITY_FILE}"; then
    echo "Quest launch is blocked by a Horizon system dialog. Wear/unlock the headset and dismiss the visible dialog, then rerun the smoke test. Activities: ${ACTIVITY_FILE}" >&2
  fi
  if grep -Eq 'REQUIRES_CONTROLLERS_LAUNCH_CHECK|LaunchCheckControllerRequiredDialogActivity' "${ACTIVITY_FILE}"; then
    echo "Quest launch is blocked by Horizon's controller-required launch check. Wear/unlock the headset and dismiss the system dialog, or connect/wake controllers/hand tracking before retrying. Activities: ${ACTIVITY_FILE}" >&2
  fi
  if grep -Eq 'KeyguardShowing=true|isSleeping=true' "${ACTIVITY_FILE}"; then
    echo "Quest is still sleeping or keyguard-locked. Put the headset on, unlock it, and rerun the smoke test. Activities: ${ACTIVITY_FILE}" >&2
  fi
  grep -Ei 'AndroidRuntime|FATAL EXCEPTION|crash|tombstone|Godot|OpenXR|Vulkan|SIGSEGV|SIGABRT' "${LOG_FILE}" >&2 || true
  exit 1
fi

if grep -Eiq 'FATAL EXCEPTION|SIGSEGV|SIGABRT|native crash|ANR in|OpenXR: Failed|XR_ERROR|Unable to create DisplayServer|Couldn'\''t create a Vulkan device|VulkanHooks singleton' "${LOG_FILE}"; then
	echo "Quest smoke failed: crash/error markers found in ${LOG_FILE}" >&2
	grep -Ein 'FATAL EXCEPTION|SIGSEGV|SIGABRT|native crash|ANR in|OpenXR: Failed|XR_ERROR|Unable to create DisplayServer|Couldn'\''t create a Vulkan device|VulkanHooks singleton' "${LOG_FILE}" >&2 || true
	exit 1
fi

godot_errors="$(grep -Ein ' E godot[[:space:]]*: ERROR:' "${LOG_FILE}" | grep -Ev 'Unsupported interaction profile /interaction_profiles/khr/generic_controller' || true)"
if [[ -n "${godot_errors}" ]]; then
	echo "Quest smoke failed: Godot errors found in ${LOG_FILE}" >&2
	printf '%s\n' "${godot_errors}" >&2
	exit 1
fi

if ! grep -Eq 'Hidefall visible world pending: phase=lobby objects=0 object_nodes=0' "${LOG_FILE}"; then
	echo "Quest smoke failed: no lobby-first Hidefall startup marker was found in ${LOG_FILE}" >&2
	grep -Ein 'Hidefall visible (gameplay ready|world pending)|OpenXR|passthrough|phase=|objects=' "${LOG_FILE}" >&2 || true
	exit 1
fi

echo "Quest smoke passed for ${PACKAGE} with pid ${pid}. Log: ${LOG_FILE}"
