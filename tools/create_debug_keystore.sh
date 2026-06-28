#!/usr/bin/env bash
set -euo pipefail

KEYSTORE="${1:-tools/android-keystore/debug.keystore}"
mkdir -p "$(dirname "${KEYSTORE}")"

if [[ -f "${KEYSTORE}" ]]; then
  exit 0
fi

keytool -genkeypair -v \
  -keystore "${KEYSTORE}" \
  -storepass android \
  -alias androiddebugkey \
  -keypass android \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US"

