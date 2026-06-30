#!/usr/bin/env bash
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.6.2-stable}"
TEMPLATE_VERSION="${TEMPLATE_VERSION:-${GODOT_VERSION/-stable/.stable}}"
XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/hidefall-godot-data}"
ARCHIVE="/tmp/godot-${GODOT_VERSION}-export-templates.tpz"
UNPACK_DIR="/tmp/hidefall-godot-templates-unpacked"
TARGET_DIR="${XDG_DATA_HOME}/godot/export_templates/${TEMPLATE_VERSION}"
URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"

mkdir -p "${TARGET_DIR}"
curl -L --fail --show-error --output "${ARCHIVE}" "${URL}"
rm -rf "${UNPACK_DIR}"
unzip -o "${ARCHIVE}" -d "${UNPACK_DIR}"
cp -a "${UNPACK_DIR}/templates/." "${TARGET_DIR}/"
