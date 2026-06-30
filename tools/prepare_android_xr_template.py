from __future__ import annotations

import os
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
GAME_DIR = ROOT / "game"
ANDROID_BUILD_DIR = GAME_DIR / "android" / "build"
BUILD_GRADLE_PATH = ANDROID_BUILD_DIR / "build.gradle"
CONFIG_GRADLE_PATH = ANDROID_BUILD_DIR / "config.gradle"
GRADLE_PROPERTIES_PATH = ANDROID_BUILD_DIR / "gradle.properties"
ANDROID_NS = "http://schemas.android.com/apk/res/android"
TEMPLATE_VERSION = os.environ.get("TEMPLATE_VERSION", os.environ.get("GODOT_VERSION", "4.6.2-stable").replace("-stable", ".stable"))


def main() -> None:
    ensure_android_template()
    ignore_template_resources()
    patch_manifest()
    patch_gradle()
    patch_gradle_properties()
    print("Prepared Android XR Gradle template")


def ensure_android_template() -> None:
    version_path = ANDROID_BUILD_DIR.parent / ".build_version"
    current_version = version_path.read_text(encoding="utf-8").strip() if version_path.exists() else ""
    if current_version != TEMPLATE_VERSION and ANDROID_BUILD_DIR.exists():
        for child in ANDROID_BUILD_DIR.iterdir():
            if child.is_dir():
                import shutil

                shutil.rmtree(child)
            else:
                child.unlink()
    if not main_manifest_path().exists() or not BUILD_GRADLE_PATH.exists():
        template_zip = find_android_source_zip()
        ANDROID_BUILD_DIR.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(template_zip) as archive:
            archive.extractall(ANDROID_BUILD_DIR)
        version_path.write_text(f"{TEMPLATE_VERSION}\n", encoding="utf-8")
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
        xdg_data_home / "godot" / "export_templates" / TEMPLATE_VERSION / "android_source.zip",
        Path.home() / ".local" / "share" / "godot" / "export_templates" / TEMPLATE_VERSION / "android_source.zip",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError(f"Godot Android source template {TEMPLATE_VERSION} not found. Run `make install-export-templates` first.")


def main_manifest_path() -> Path:
    candidates = [
        ANDROID_BUILD_DIR / "src" / "main" / "AndroidManifest.xml",
        ANDROID_BUILD_DIR / "AndroidManifest.xml",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


def patch_manifest() -> None:
    ET.register_namespace("android", ANDROID_NS)
    ET.register_namespace("tools", "http://schemas.android.com/tools")
    tree = ET.parse(main_manifest_path())
    root = tree.getroot()
    ensure_openxr_queries(root)
    ensure_uses_feature(root, "android.hardware.vr.headtracking", required="true", version="1")
    ensure_uses_feature(root, "oculus.software.handtracking", required="false")
    ensure_uses_permission(root, "org.khronos.openxr.permission.OPENXR")
    ensure_uses_permission(root, "org.khronos.openxr.permission.OPENXR_SYSTEM")
    ensure_uses_permission(root, "com.oculus.permission.HAND_TRACKING")
    application = root.find("application")
    if application is None:
        raise RuntimeError("Android manifest is missing <application>")
    ensure_meta_data(application, "com.oculus.supportedDevices", "quest2|questpro|quest3|quest3s")
    ensure_meta_data(application, "com.oculus.handtracking.version", "V2.0")
    ensure_meta_data(application, "com.oculus.handtracking.frequency", "LOW")
    activity = application.find("activity")
    if activity is None:
        raise RuntimeError("Android manifest is missing main <activity>")
    activity_filter = activity.find("intent-filter")
    if activity_filter is None:
        activity_filter = ET.SubElement(activity, "intent-filter")
        action = ET.SubElement(activity_filter, "action")
        action.set(android_attr("name"), "android.intent.action.MAIN")
    ensure_category(activity_filter, "android.intent.category.DEFAULT")
    ensure_category(activity_filter, "android.intent.category.LAUNCHER")
    ensure_category(activity_filter, "com.oculus.intent.category.VR")
    ensure_category(activity_filter, "org.khronos.openxr.intent.category.IMMERSIVE_HMD")
    remove_category(activity_filter, "android.intent.category.HOME")
    alias = application.find("activity-alias")
    if alias is not None:
        launcher_filter = find_filter_with_category(alias, "android.intent.category.LAUNCHER")
        if launcher_filter is None:
            launcher_filter = ET.SubElement(alias, "intent-filter")
            action = ET.SubElement(launcher_filter, "action")
            action.set(android_attr("name"), "android.intent.action.MAIN")
        ensure_category(launcher_filter, "android.intent.category.DEFAULT")
        ensure_category(launcher_filter, "android.intent.category.LAUNCHER")
        ensure_category(launcher_filter, "com.oculus.intent.category.VR")
        ensure_category(launcher_filter, "org.khronos.openxr.intent.category.IMMERSIVE_HMD")
        remove_category(launcher_filter, "android.intent.category.HOME")
    tree.write(main_manifest_path(), encoding="utf-8", xml_declaration=True)


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


def ensure_uses_permission(root: ET.Element, name: str) -> None:
    for child in root.findall("uses-permission"):
        if child.get(android_attr("name")) == name:
            return
    permission = ET.SubElement(root, "uses-permission")
    permission.set(android_attr("name"), name)


def ensure_openxr_queries(root: ET.Element) -> None:
    queries = root.find("queries")
    if queries is None:
        queries = ET.SubElement(root, "queries")
    provider = queries.find("provider")
    if provider is None:
        provider = ET.SubElement(queries, "provider")
    provider.set(android_attr("authorities"), "org.khronos.openxr.runtime_broker;org.khronos.openxr.system_runtime_broker")
    ensure_query_action(queries, "org.khronos.openxr.OpenXRRuntimeService")
    ensure_query_action(queries, "org.khronos.openxr.OpenXRApiLayerService")


def ensure_query_action(queries: ET.Element, name: str) -> None:
    for intent in queries.findall("intent"):
        action = intent.find("action")
        if action is not None and action.get(android_attr("name")) == name:
            return
    intent = ET.SubElement(queries, "intent")
    action = ET.SubElement(intent, "action")
    action.set(android_attr("name"), name)


def ensure_category(intent_filter: ET.Element, name: str) -> None:
    for child in intent_filter.findall("category"):
        if child.get(android_attr("name")) == name:
            return
    category = ET.SubElement(intent_filter, "category")
    category.set(android_attr("name"), name)


def remove_category(intent_filter: ET.Element, name: str) -> None:
    for child in list(intent_filter.findall("category")):
        if child.get(android_attr("name")) == name:
            intent_filter.remove(child)


def find_filter_with_category(parent: ET.Element, name: str) -> ET.Element | None:
    for intent_filter in parent.findall("intent-filter"):
        for category in intent_filter.findall("category"):
            if category.get(android_attr("name")) == name:
                return intent_filter
    return None


def ensure_meta_data(application: ET.Element, name: str, value: str) -> None:
    for child in application.findall("meta-data"):
        if child.get(android_attr("name")) == name:
            child.set(android_attr("value"), value)
            return
    meta_data = ET.SubElement(application, "meta-data")
    meta_data.set(android_attr("name"), name)
    meta_data.set(android_attr("value"), value)


def android_attr(name: str) -> str:
    return f"{{{ANDROID_NS}}}{name}"


def patch_gradle() -> None:
    text = BUILD_GRADLE_PATH.read_text(encoding="utf-8")
    text = text.replace("targetSdkVersion getExportTargetSdkVersion()", "targetSdkVersion Math.min(getExportTargetSdkVersion(), 35)")
    text = text.replace("debug.jniLibs.srcDirs = ['libs/debug', 'libs/debug/vulkan_validation_layers']", "debug.jniLibs.srcDirs = ['libs/debug']")
    vendor_dependency_block = r'''
    // Hidefall Quest requires the Meta OpenXR vendor plugin in custom Gradle exports.
    debugImplementation files('../../addons/godotopenxrvendors/.bin/android/debug/godotopenxr-meta-debug.aar')
    releaseImplementation files('../../addons/godotopenxrvendors/.bin/android/release/godotopenxr-meta-release.aar')
'''
    if "godotopenxr-meta-debug.aar" not in text:
        markers = [
            '    implementation "androidx.documentfile:documentfile:$versions.documentfileVersion"\n',
            '    implementation "androidx.core:core-splashscreen:$versions.splashscreenVersion"\n',
        ]
        marker = next((candidate for candidate in markers if candidate in text), "")
        if not marker:
            raise RuntimeError("Unable to find dependency insertion point in Android build.gradle")
        text = text.replace(marker, marker + vendor_dependency_block, 1)
    manifest_task = r'''
tasks.register('ensureQuestVrManifest') {
    doLast {
        [file('src/main/AndroidManifest.xml'), file('src/debug/AndroidManifest.xml'), file('src/release/AndroidManifest.xml'), file('AndroidManifest.xml')].each { manifestFile ->
            if (!manifestFile.exists()) {
                return
            }
            def androidName = new groovy.xml.QName('http://schemas.android.com/apk/res/android', 'name', 'android')
            def parser = new XmlParser(false, true)
            def manifest = parser.parse(manifestFile)
            def application = manifest.application[0]
            def alias = application.'activity-alias'.find { node ->
                def nodeName = node.attributes()[androidName] as String
                nodeName == '.GodotAppLauncher' || nodeName == 'com.godot.game.GodotAppLauncher'
            } ?: application.'activity-alias'[0] ?: application.activity[0]
            if (alias == null) {
                throw new GradleException("Android manifest is missing launchable activity or activity-alias")
            }
            def launcherFilter = alias.'intent-filter'.find { filter ->
                filter.category.any { category ->
                    category.attributes()[androidName] == 'android.intent.category.LAUNCHER'
                }
            }
            if (launcherFilter == null) {
                launcherFilter = alias.appendNode('intent-filter')
                def action = launcherFilter.appendNode('action')
                action.attributes()[androidName] = 'android.intent.action.MAIN'
            }
            [
                'android.intent.category.DEFAULT',
                'android.intent.category.LAUNCHER',
                'com.oculus.intent.category.VR',
                'org.khronos.openxr.intent.category.IMMERSIVE_HMD'
            ].each { categoryName ->
                boolean exists = launcherFilter.category.any { category ->
                    category.attributes()[androidName] == categoryName
                }
                if (!exists) {
                    def category = launcherFilter.appendNode('category')
                    category.attributes()[androidName] = categoryName
                }
            }
            launcherFilter.category.findAll { category ->
                category.attributes()[androidName] == 'android.intent.category.HOME'
            }.each { category ->
                launcherFilter.remove(category)
            }
            def writer = new StringWriter()
            def printer = new XmlNodePrinter(new PrintWriter(writer))
            printer.preserveWhitespace = true
            printer.print(manifest)
            manifestFile.write(writer.toString(), 'UTF-8')
        }
    }
}

preBuild.dependsOn ensureQuestVrManifest

'''
    marker = "tasks.register('ensureQuestVrManifest')"
    dependency = "preBuild.dependsOn ensureQuestVrManifest"
    start = text.find(marker)
    if start != -1:
        end = text.find(dependency, start)
        if end == -1:
            raise RuntimeError("Found ensureQuestVrManifest task without preBuild dependency marker")
        end += len(dependency)
        while end < len(text) and text[end] in "\r\n":
            end += 1
        text = text[:start].rstrip() + "\n\n" + text[end:].lstrip()
    text += manifest_task
    BUILD_GRADLE_PATH.write_text(text, encoding="utf-8")
    config_text = CONFIG_GRADLE_PATH.read_text(encoding="utf-8")
    config_text = re.sub(r"(targetSdk\s*:\s*)36,", r"\g<1>35,", config_text)
    CONFIG_GRADLE_PATH.write_text(config_text, encoding="utf-8")


def patch_gradle_properties() -> None:
    lines = GRADLE_PROPERTIES_PATH.read_text(encoding="utf-8").splitlines()
    lines = [line for line in lines if not line.startswith("org.gradle.daemon=")]
    lines.append("org.gradle.daemon=false")
    GRADLE_PROPERTIES_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
