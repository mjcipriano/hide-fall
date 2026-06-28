GODOT_VERSION := 4.7-stable
GODOT_BIN := tools/godot/Godot_v$(GODOT_VERSION)_linux.x86_64
GODOT_ZIP := /tmp/godot-$(GODOT_VERSION)-linux.zip
GODOT_URL := https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)/Godot_v$(GODOT_VERSION)_linux.x86_64.zip
ANDROID_SDK_ROOT ?= $(abspath tools/android-sdk)
ANDROID_HOME ?= $(ANDROID_SDK_ROOT)
JAVA_HOME ?= $(CONDA_PREFIX)/lib/jvm
GODOT_ENV := XDG_DATA_HOME=/tmp/hidefall-godot-data XDG_CONFIG_HOME=/tmp/hidefall-godot-config XDG_CACHE_HOME=/tmp/hidefall-godot-cache ANDROID_SDK_ROOT=$(ANDROID_SDK_ROOT) ANDROID_HOME=$(ANDROID_HOME) JAVA_HOME=$(JAVA_HOME)

export ANDROID_SDK_ROOT
export ANDROID_HOME
export JAVA_HOME

.PHONY: install-godot install-export-templates install-android-sdk ensure-android-sdk create-debug-keystore configure-android-export build-apks build-quest-apk build-mobile-apk godot-version validate test run clean-godot

install-godot:
	mkdir -p tools/godot
	curl -L --fail --show-error --output $(GODOT_ZIP) $(GODOT_URL)
	unzip -o $(GODOT_ZIP) -d tools/godot
	chmod +x $(GODOT_BIN)

install-export-templates:
	env $(GODOT_ENV) tools/install_godot_export_templates.sh

install-android-sdk:
	tools/install_android_sdk.sh

ensure-android-sdk:
	test -x "$(ANDROID_SDK_ROOT)/platform-tools/adb" && test -x "$(ANDROID_SDK_ROOT)/build-tools/35.0.0/apksigner" || tools/install_android_sdk.sh

create-debug-keystore:
	tools/create_debug_keystore.sh

configure-android-export: ensure-android-sdk create-debug-keystore
	env $(GODOT_ENV) python tools/configure_godot_android.py

godot-version:
	$(GODOT_BIN) --version

validate:
	python tools/validate_content.py

test: validate
	env $(GODOT_ENV) $(GODOT_BIN) --headless --path game --script res://tests/test_runner.gd

run:
	env $(GODOT_ENV) $(GODOT_BIN) --path game

build-apks: build-quest-apk build-mobile-apk

build-quest-apk: configure-android-export
	mkdir -p build
	env $(GODOT_ENV) HIDEFALL_DISABLE_NETWORK=1 $(GODOT_BIN) --headless --path game --export-debug "Quest Debug APK" ../build/hidefall-quest-debug.apk

build-mobile-apk: configure-android-export
	mkdir -p build
	env $(GODOT_ENV) HIDEFALL_DISABLE_NETWORK=1 $(GODOT_BIN) --headless --path game --export-debug "Mobile Debug APK" ../build/hidefall-mobile-debug.apk

clean-godot:
	rm -rf game/.godot
