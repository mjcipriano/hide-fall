class_name GameConfig
extends RefCounted

const DEFAULT_PATH := "res://content/settings/default.json"

var data: Dictionary = {}


func load_default() -> void:
	data = _read_json(DEFAULT_PATH)
	_apply_defaults()


static func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open JSON file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("Unable to parse JSON file: %s" % path)
		return {}
	return parsed


func get_value(section: String, key: String, fallback: Variant = null) -> Variant:
	return data.get(section, {}).get(key, fallback)


func duplicate_data() -> Dictionary:
	return data.duplicate(true)


func _apply_defaults() -> void:
	if data.is_empty():
		data = {
			"round": {"room_setup_seconds": 5, "object_rain_seconds": 10, "blackout_seconds": 10, "seek_seconds": 90, "results_seconds": 15},
			"objects": {"decoy_count": 75, "max_decoy_count": 150, "spawn_height_meters": 2.5},
			"seeker": {"base_bullets": 3, "bullets_per_hider": 1, "scan_pulse_enabled": true, "scan_pulse_count": 1},
			"hiders": {"shape_change_cooldown": 12, "color_change_cooldown": 6, "movement_speed": 1.0, "bot_decision_seconds": 1.6},
			"network": {"max_hiders": 8, "allow_late_join": false, "transport": "websocket_lan", "protocol_version": 1}
		}
