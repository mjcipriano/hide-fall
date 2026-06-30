#!/usr/bin/env bash
set -euo pipefail

missing=0
for name in \
  HIDEFALL_ANDROID_KEYSTORE_BASE64 \
  HIDEFALL_ANDROID_KEYSTORE_PASSWORD \
  HIDEFALL_ANDROID_KEY_ALIAS \
  HIDEFALL_ANDROID_KEY_PASSWORD \
  HIDEFALL_ANDROID_CERT_SHA256
do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required release signing environment variable: ${name}" >&2
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi

echo "Release signing environment is configured"
