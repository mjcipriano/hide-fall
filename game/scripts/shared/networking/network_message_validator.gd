class_name NetworkMessageValidator
extends RefCounted

const PROTOCOL_VERSION := 1
const CLIENT_TYPES := ["join_request", "hider_input", "ready_state", "ping"]
const HOST_TYPES := ["join_accepted", "join_rejected", "state_snapshot", "round_results", "pong"]


static func validate_client_message(message: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_validate_common(message, CLIENT_TYPES, errors)
	match message.get("type", ""):
		"join_request":
			_require_string(message, "room_id", errors)
			_require_string(message, "token", errors)
			_require_string(message, "player_name", errors)
			for optional_key in ["preferred_shape", "preferred_color", "preferred_pattern"]:
				_optional_string(message, optional_key, errors)
		"hider_input":
			_require_string(message, "player_id", errors)
			if not message.get("move", null) is Array or message["move"].size() != 2:
				errors.append("hider_input.move must be a 2-item array")
		"ready_state":
			_require_string(message, "player_id", errors)
			if not message.get("ready", null) is bool:
				errors.append("ready_state.ready must be boolean")
	return errors


static func validate_host_message(message: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_validate_common(message, HOST_TYPES, errors)
	if message.get("type", "") == "state_snapshot":
		_require_string(message, "phase", errors)
		if not message.has("server_tick"):
			errors.append("state_snapshot.server_tick is required")
	return errors


static func _validate_common(message: Dictionary, allowed_types: Array, errors: Array[String]) -> void:
	if not message.get("type", null) is String:
		errors.append("type must be a string")
	elif not allowed_types.has(message["type"]):
		errors.append("unsupported message type: %s" % message["type"])
	if int(message.get("version", -1)) != PROTOCOL_VERSION:
		errors.append("version must be %d" % PROTOCOL_VERSION)


static func _require_string(message: Dictionary, key: String, errors: Array[String]) -> void:
	if not message.get(key, null) is String or message[key].is_empty():
		errors.append("%s must be a non-empty string" % key)


static func _optional_string(message: Dictionary, key: String, errors: Array[String]) -> void:
	if message.has(key) and message[key] != null and not message[key] is String:
		errors.append("%s must be a string when present" % key)

