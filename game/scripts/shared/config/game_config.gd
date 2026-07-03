class_name GameConfig
extends RefCounted

const DEFAULT_PATH := "res://content/settings/default.json"

var data: Dictionary = {}


func load_default() -> void:
	data = _read_json(DEFAULT_PATH)
	_apply_defaults()


func apply_overrides(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var overrides = _read_json(path)
	if not overrides is Dictionary:
		push_error("Settings overrides must be a JSON object: %s" % path)
		return false
	_deep_merge(data, overrides)
	_apply_defaults()
	return true


func save_overrides(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write settings overrides: %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


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


func set_value(section: String, key: String, value: Variant) -> void:
	if not data.has(section) or not data[section] is Dictionary:
		data[section] = {}
	data[section][key] = value


func duplicate_data() -> Dictionary:
	return data.duplicate(true)


func _deep_merge(target: Dictionary, overrides: Dictionary) -> void:
	for key in overrides:
		var value = overrides[key]
		if target.get(key, null) is Dictionary and value is Dictionary:
			_deep_merge(target[key], value)
		else:
			target[key] = value


func _apply_defaults() -> void:
	if data.is_empty():
		data = {
			"round": {"room_setup_seconds": 5, "seek_seconds": 90, "results_seconds": 15, "countdown_tick_seconds": 15, "end_on_seek_timeout": false, "end_when_out_of_shots": true},
			"objects": {"decoy_count": 75, "max_decoy_count": 150, "spawn_height_meters": 2.5},
			"seeker": {"base_bullets": 3, "bullets_per_hider": 1, "scan_pulse_enabled": true, "scan_pulse_count": 1, "consume_shot_on_hit": false},
			"hiders": {"shape_change_cooldown": 0, "color_change_cooldown": 0, "movement_speed": 1.0, "bot_decision_seconds": 1.6, "bot_count": 2, "dash_enabled": true, "dash_speed": 7.0, "dash_duration_seconds": 0.28, "dash_cooldown_seconds": 3.5, "mimic_radius_meters": 0.75, "mimic_cooldown_seconds": 0.0, "inspection_minigame_enabled": true, "inspection_minigame": ""},
			"network": {"max_hiders": 8, "allow_late_join": false, "transport": "websocket_lan", "protocol_version": 1}
		}
