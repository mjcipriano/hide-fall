from __future__ import annotations

import os
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
GAME_DIR = ROOT / "game"
ANDROID_BUILD_DIR = GAME_DIR / "android" / "build"
MANIFEST_PATH = ANDROID_BUILD_DIR / "src" / "main" / "AndroidManifest.xml"
BUILD_GRADLE_PATH = ANDROID_BUILD_DIR / "build.gradle"
ANDROID_NS = "http://schemas.android.com/apk/res/android"


def main() -> None:
    ensure_android_template()
    ignore_template_resources()
    patch_manifest()
    patch_gradle()
    print("Prepared Android XR Gradle template")


def ensure_android_template() -> None:
    if not MANIFEST_PATH.exists() or not BUILD_GRADLE_PATH.exists():
        template_zip = find_android_source_zip()
        ANDROID_BUILD_DIR.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(template_zip) as archive:
            archive.extractall(ANDROID_BUILD_DIR)
        (ANDROID_BUILD_DIR.parent / ".build_version").write_text("4.7.stable\n", encoding="utf-8")
    gradlew = ANDROID_BUILD_DIR / "gradlew"
    if gradlew.exists():
        gradlew.chmod(0o755)


def ignore_template_resources() -> None:
    (ANDROID_BUILD_DIR / ".gdignore").write_text("", encoding="utf-8")
    for import_file in ANDROID_BUILD_DIR.rglob("*.import"):
        import_file.unlink()


def find_android_source_zip() -> Path:
    xdg_data_home = Path(os.environ.get("XDG_DATA_HOME", "/tmp/hidefall-godot-data"))
    candidates = [
        xdg_data_home / "godot" / "export_templates" / "4.7.stable" / "android_source.zip",
        Path.home() / ".local" / "share" / "godot" / "export_templates" / "4.7.stable" / "android_source.zip",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError("Godot Android source template not found. Run `make install-export-templates` first.")


def patch_manifest() -> None:
    ET.register_namespace("android", ANDROID_NS)
    ET.register_namespace("tools", "http://schemas.android.com/tools")
    tree = ET.parse(MANIFEST_PATH)
    root = tree.getroot()
    ensure_uses_feature(root, "android.hardware.vr.headtracking", required="true", version="1")
    application = root.find("application")
    if application is None:
        raise RuntimeError("Android manifest is missing <application>")
    activity = application.find("activity")
    if activity is None:
        raise RuntimeError("Android manifest is missing main <activity>")
    activity_filter = activity.find("intent-filter")
    if activity_filter is None:
        activity_filter = ET.SubElement(activity, "intent-filter")
        action = ET.SubElement(activity_filter, "action")
        action.set(android_attr("name"), "android.intent.action.MAIN")
    ensure_category(activity_filter, "android.intent.category.DEFAULT")
    ensure_category(activity_filter, "com.oculus.intent.category.VR")
    ensure_category(activity_filter, "org.khronos.openxr.intent.category.IMMERSIVE_HMD")
    alias = application.find("activity-alias")
    if alias is None:
        raise RuntimeError("Android manifest is missing launcher <activity-alias>")
    intent_filter = alias.find("intent-filter")
    if intent_filter is None:
        intent_filter = ET.SubElement(alias, "intent-filter")
    ensure_category(intent_filter, "android.intent.category.DEFAULT")
    ensure_category(intent_filter, "android.intent.category.LAUNCHER")
    ensure_category(intent_filter, "com.oculus.intent.category.VR")
    ensure_category(intent_filter, "org.khronos.openxr.intent.category.IMMERSIVE_HMD")
    tree.write(MANIFEST_PATH, encoding="utf-8", xml_declaration=True)


def ensure_uses_feature(root: ET.Element, name: str, required: str, version: str | None = None) -> None:
    for child in root.findall("uses-feature"):
        if child.get(android_attr("name")) == name:
            child.set(android_attr("required"), required)
            if version is not None:
                child.set(android_attr("version"), version)
            return
    feature = ET.SubElement(root, "uses-feature")
    feature.set(android_attr("name"), name)
    feature.set(android_attr("required"), required)
    if version is not None:
        feature.set(android_attr("version"), version)


def ensure_category(intent_filter: ET.Element, name: str) -> None:
    for child in intent_filter.findall("category"):
        if child.get(android_attr("name")) == name:
            return
    category = ET.SubElement(intent_filter, "category")
    category.set(android_attr("name"), name)


def android_attr(name: str) -> str:
    return f"{{{ANDROID_NS}}}{name}"


def patch_gradle() -> None:
    text = BUILD_GRADLE_PATH.read_text(encoding="utf-8")
    marker = "    // Godot user plugins remote dependencies"
    deps = """    debugImplementation files('../../addons/godotopenxrvendors/.bin/android/debug/godotopenxr-meta-debug.aar')
    releaseImplementation files('../../addons/godotopenxrvendors/.bin/android/release/godotopenxr-meta-release.aar')

"""
    if "godotopenxr-meta-debug.aar" not in text:
        text = text.replace(marker, deps + marker)
    manifest_task = r'''
tasks.register('ensureQuestVrManifest') {
    doLast {
        [file('src/main/AndroidManifest.xml'), file('src/debug/AndroidManifest.xml')].each { manifestFile ->
            if (!manifestFile.exists()) {
                return
            }
            String manifestText = manifestFile.getText('UTF-8')
            if (!manifestText.contains('com.oculus.intent.category.VR')) {
                manifestText = manifestText.replace(
                    '<category android:name="org.khronos.openxr.intent.category.IMMERSIVE_HMD" />',
                    '<category android:name="com.oculus.intent.category.VR" />\n                <category android:name="org.khronos.openxr.intent.category.IMMERSIVE_HMD" />'
                )
                manifestFile.write(manifestText, 'UTF-8')
            }
        }
    }
}

preBuild.dependsOn ensureQuestVrManifest

'''
    if "ensureQuestVrManifest" not in text:
        text += manifest_task
    BUILD_GRADLE_PATH.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
