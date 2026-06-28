class_name HidefallSimulation
extends RefCounted

const NetworkMessageValidatorScript := preload("res://scripts/shared/networking/network_message_validator.gd")
const ScoreCalculatorScript := preload("res://scripts/shared/scoring/score_calculator.gd")

const PHASE_LOBBY := "lobby"
const PHASE_ROOM_SETUP := "room_setup"
const PHASE_OBJECT_RAIN := "object_rain"
const PHASE_BLACKOUT := "blackout"
const PHASE_SEEK := "seek"
const PHASE_RESULTS := "results"

var config
var content
var rng := RandomNumberGenerator.new()

var phase := PHASE_LOBBY
var phase_elapsed := 0.0
var server_tick := 0
var shots_remaining := 0
var room_id := "842913"
var room_token := "hidefall"
var seeker_position := Vector3.ZERO
var seeker_forward := Vector3.FORWARD
var play_radius := 3.0

var players: Dictionary = {}
var objects: Dictionary = {}
var scores: Dictionary = {}
var stats: Dictionary = {}

var _next_player_index := 1
var _next_object_index := 1
var _shape_ids: Array[String] = []
var _color_ids: Array[String] = []


func setup(p_config, p_content, seed: int = 12345) -> void:
	config = p_config
	content = p_content
	rng.seed = seed
	_shape_ids = content.get_shape_ids()
	_color_ids = content.get_color_ids()
	_reset_session_state()


func _reset_session_state() -> void:
	phase = PHASE_LOBBY
	phase_elapsed = 0.0
	server_tick = 0
	shots_remaining = 0
	players.clear()
	objects.clear()
	scores.clear()
	stats = {
		"correct_shots": 0,
		"wrong_shots": 0,
		"shots_fired": 0,
		"all_hiders_found": false,
		"time_bonus": 0.0
	}
	_next_player_index = 1
	_next_object_index = 1


func add_hider(player_name: String, is_bot: bool = false) -> String:
	var player_id := "p%d" % _next_player_index
	_next_player_index += 1
	players[player_id] = {
		"id": player_id,
		"name": player_name,
		"role": "hider",
		"ready": true,
		"is_bot": is_bot,
		"alive": true,
		"object_id": "",
		"score": 0
	}
	return player_id


func remove_player(player_id: String, inert_decoy: bool = true) -> bool:
	if not players.has(player_id):
		return false
	var object_id: String = players[player_id].get("object_id", "")
	if inert_decoy and objects.has(object_id):
		objects[object_id]["is_hider"] = false
		objects[object_id]["owner_player_id"] = ""
		objects[object_id]["alive"] = true
		objects[object_id]["move_input"] = Vector2.ZERO
		objects[object_id]["freeze"] = false
	elif objects.has(object_id):
		objects.erase(object_id)
	players.erase(player_id)
	return true


func set_player_ready(player_id: String, ready: bool) -> bool:
	if not players.has(player_id):
		return false
	players[player_id]["ready"] = ready
	return true


func add_bot_hiders(count: int) -> Array[String]:
	var ids: Array[String] = []
	for index in count:
		ids.append(add_hider("Bot %d" % (index + 1), true))
	return ids


func start_round() -> void:
	if players.is_empty():
		add_bot_hiders(1)
	objects.clear()
	_next_object_index = 1
	for player_id in players:
		players[player_id]["alive"] = true
		players[player_id]["object_id"] = ""
		players[player_id]["score"] = 0
	_spawn_decoys()
	_spawn_hiders()
	shots_remaining = _calculate_bullets()
	stats["correct_shots"] = 0
	stats["wrong_shots"] = 0
	stats["shots_fired"] = 0
	stats["all_hiders_found"] = false
	stats["time_bonus"] = 0.0
	_set_phase(PHASE_OBJECT_RAIN)


func advance(delta: float) -> void:
	server_tick += 1
	phase_elapsed += delta
	_update_hider_scores(delta)
	match phase:
		PHASE_OBJECT_RAIN:
			_integrate_object_rain(delta)
			if phase_elapsed >= float(config.get_value("round", "object_rain_seconds", 10.0)):
				_set_phase(PHASE_BLACKOUT)
		PHASE_BLACKOUT:
			if phase_elapsed >= float(config.get_value("round", "blackout_seconds", 10.0)):
				_set_phase(PHASE_SEEK)
		PHASE_SEEK:
			_integrate_hider_motion(delta)
			if _live_hider_count() == 0:
				stats["all_hiders_found"] = true
				stats["time_bonus"] = _time_remaining()
				_finish_round()
			elif phase_elapsed >= float(config.get_value("round", "seek_seconds", 90.0)):
				_finish_round()
		PHASE_RESULTS:
			if phase_elapsed >= float(config.get_value("round", "results_seconds", 15.0)):
				_set_phase(PHASE_LOBBY)


func apply_hider_input(player_id: String, input: Dictionary) -> bool:
	if not players.has(player_id):
		return false
	var player: Dictionary = players[player_id]
	if not player.get("alive", false):
		return false
	var object_id: String = player.get("object_id", "")
	if object_id.is_empty() or not objects.has(object_id):
		return false
	var obj: Dictionary = objects[object_id]
	if obj.get("held_by_seeker", false) and bool(config.get_value("hiders", "cannot_move_while_held", true)):
		return false
	if phase != PHASE_BLACKOUT and phase != PHASE_SEEK:
		return false

	var move := Vector2.ZERO
	if input.get("move", null) is Array and input["move"].size() == 2:
		move = Vector2(float(input["move"][0]), float(input["move"][1])).limit_length(1.0)
	obj["move_input"] = move
	obj["freeze"] = bool(input.get("freeze", false))

	if input.get("request_shape", null) is String:
		_try_change_shape(obj, input["request_shape"])
	if input.get("request_color", null) is String:
		_try_change_color(obj, input["request_color"])

	objects[object_id] = obj
	return true


func shoot_object(object_id: String) -> Dictionary:
	if phase != PHASE_SEEK:
		return {"accepted": false, "reason": "not_seek_phase"}
	if shots_remaining <= 0:
		return {"accepted": false, "reason": "no_shots_remaining"}
	if not objects.has(object_id):
		return {"accepted": false, "reason": "unknown_object"}
	shots_remaining -= 1
	stats["shots_fired"] = int(stats["shots_fired"]) + 1
	var obj: Dictionary = objects[object_id]
	if obj.get("is_hider", false) and obj.get("alive", true):
		obj["alive"] = false
		objects[object_id] = obj
		var owner_id: String = obj.get("owner_player_id", "")
		if players.has(owner_id):
			players[owner_id]["alive"] = false
		stats["correct_shots"] = int(stats["correct_shots"]) + 1
		if _live_hider_count() == 0:
			stats["all_hiders_found"] = true
			stats["time_bonus"] = _time_remaining()
			_finish_round()
		return {"accepted": true, "hit": true, "player_id": owner_id}
	stats["wrong_shots"] = int(stats["wrong_shots"]) + 1
	obj["damaged"] = true
	objects[object_id] = obj
	return {"accepted": true, "hit": false}


func get_state_snapshot(for_player_id: String = "") -> Dictionary:
	var object_list: Array = []
	for object_id in objects:
		var obj: Dictionary = objects[object_id]
		object_list.append({
			"object_id": object_id,
			"shape": obj["shape"],
			"color": obj["color"],
			"position": _vector3_to_array(obj["position"]),
			"velocity": _vector3_to_array(obj["velocity"]),
			"is_hider": obj["is_hider"] if for_player_id.is_empty() else obj.get("owner_player_id", "") == for_player_id,
			"alive": obj["alive"]
		})
	return {
		"type": "state_snapshot",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"server_tick": server_tick,
		"phase": phase,
		"time_remaining": _time_remaining(),
		"shots_remaining": shots_remaining,
		"players": players.values(),
		"objects": object_list,
		"hider_state": get_hider_state(for_player_id),
		"danger": get_danger_for_player(for_player_id),
		"cooldowns": get_hider_cooldowns(for_player_id),
		"scores": scores
	}


func get_hider_state(player_id: String) -> Dictionary:
	if player_id.is_empty() or not players.has(player_id):
		return {}
	var object_id: String = players[player_id].get("object_id", "")
	if object_id.is_empty() or not objects.has(object_id):
		return {
			"player_id": player_id,
			"alive": players[player_id].get("alive", false),
			"object_id": object_id
		}
	var obj: Dictionary = objects[object_id]
	return {
		"player_id": player_id,
		"object_id": object_id,
		"alive": obj.get("alive", false),
		"shape": obj.get("shape", ""),
		"color": obj.get("color", ""),
		"position": _vector3_to_array(obj.get("position", Vector3.ZERO)),
		"held_by_seeker": obj.get("held_by_seeker", false),
		"freeze": obj.get("freeze", false)
	}


func get_hider_cooldowns(player_id: String) -> Dictionary:
	if player_id.is_empty() or not players.has(player_id):
		return {}
	var object_id: String = players[player_id].get("object_id", "")
	if object_id.is_empty() or not objects.has(object_id):
		return {}
	var obj: Dictionary = objects[object_id]
	return {
		"shape": float(obj.get("shape_cooldown", 0.0)),
		"color": float(obj.get("color_cooldown", 0.0))
	}


func get_danger_for_player(player_id: String) -> String:
	if player_id.is_empty() or not players.has(player_id):
		return "safe"
	var object_id: String = players[player_id].get("object_id", "")
	if object_id.is_empty() or not objects.has(object_id):
		return "safe"
	var obj: Dictionary = objects[object_id]
	if not obj.get("alive", false):
		return "found"
	var distance: float = obj.get("position", Vector3.ZERO).distance_to(seeker_position)
	if obj.get("held_by_seeker", false):
		return "critical"
	if distance < 0.9:
		return "critical"
	if distance < 1.8:
		return "watched"
	if distance < 2.6:
		return "suspicious"
	return "safe"


func get_join_payload(host_ip: String, port: int) -> Dictionary:
	return {
		"game": "hidefall",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"host_ip": host_ip,
		"port": port,
		"room_id": room_id,
		"token": room_token
	}


func get_results() -> Dictionary:
	return {
		"seeker_score": ScoreCalculatorScript.seeker_score({
			"correct_shots": stats["correct_shots"],
			"wrong_shots": stats["wrong_shots"],
			"shots_remaining": shots_remaining,
			"all_hiders_found": stats["all_hiders_found"],
			"time_bonus": stats["time_bonus"]
		}),
		"hiders": scores,
		"stats": stats.duplicate(true)
	}


func get_hider_object_ids() -> Array[String]:
	var ids: Array[String] = []
	for object_id in objects:
		if objects[object_id].get("is_hider", false):
			ids.append(object_id)
	return ids


func get_decoy_object_ids() -> Array[String]:
	var ids: Array[String] = []
	for object_id in objects:
		if not objects[object_id].get("is_hider", false):
			ids.append(object_id)
	return ids


func _spawn_decoys() -> void:
	var decoy_count := int(config.get_value("objects", "decoy_count", 75))
	for _index in decoy_count:
		_create_object(false, "")


func _spawn_hiders() -> void:
	for player_id in players:
		var object_id := _create_object(true, player_id)
		players[player_id]["object_id"] = object_id


func _create_object(is_hider: bool, owner_player_id: String) -> String:
	var object_id := "obj_%03d" % _next_object_index
	_next_object_index += 1
	var angle := rng.randf_range(0.0, TAU)
	var radius := sqrt(rng.randf()) * play_radius
	var y := float(config.get_value("objects", "spawn_height_meters", 2.5)) if not is_hider else 0.15
	var position := Vector3(cos(angle) * radius, y, sin(angle) * radius)
	objects[object_id] = {
		"object_id": object_id,
		"shape": content.pick_weighted_shape(rng),
		"color": content.pick_color(rng),
		"position": position,
		"rotation_y": rng.randf_range(0.0, TAU),
		"velocity": Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3)),
		"move_input": Vector2.ZERO,
		"freeze": false,
		"is_hider": is_hider,
		"owner_player_id": owner_player_id,
		"held_by_seeker": false,
		"alive": true,
		"damaged": false,
		"shape_cooldown": 0.0,
		"color_cooldown": 0.0,
		"alive_time": 0.0,
		"freeze_near_seconds": 0.0,
		"close_calls": 0,
		"inspected_survived": 0
	}
	return object_id


func _integrate_object_rain(delta: float) -> void:
	for object_id in objects:
		var obj: Dictionary = objects[object_id]
		if obj.get("is_hider", false):
			continue
		var velocity: Vector3 = obj["velocity"]
		velocity.y -= 9.8 * delta
		var position: Vector3 = obj["position"] + velocity * delta
		if position.y <= 0.15:
			position.y = 0.15
			velocity.y = abs(velocity.y) * 0.22
			velocity.x *= 0.92
			velocity.z *= 0.92
		obj["position"] = _clamp_to_play_area(position)
		obj["velocity"] = velocity.limit_length(8.0)
		objects[object_id] = obj


func _integrate_hider_motion(delta: float) -> void:
	for object_id in objects:
		var obj: Dictionary = objects[object_id]
		if not obj.get("is_hider", false) or not obj.get("alive", false):
			continue
		obj["shape_cooldown"] = max(0.0, float(obj["shape_cooldown"]) - delta)
		obj["color_cooldown"] = max(0.0, float(obj["color_cooldown"]) - delta)
		if obj.get("freeze", false):
			obj["velocity"] = Vector3.ZERO
			if obj["position"].distance_to(seeker_position) < 1.5:
				obj["freeze_near_seconds"] = float(obj["freeze_near_seconds"]) + delta
		else:
			var move: Vector2 = obj.get("move_input", Vector2.ZERO)
			var speed := float(config.get_value("hiders", "movement_speed", 1.0))
			var acceleration := Vector3(move.x, 0.0, move.y) * speed * 4.0
			var velocity: Vector3 = obj["velocity"]
			velocity += acceleration * delta
			velocity *= 0.88
			obj["velocity"] = velocity.limit_length(2.4 * speed)
			obj["position"] = _clamp_to_play_area(obj["position"] + obj["velocity"] * delta)
		objects[object_id] = obj


func _update_hider_scores(delta: float) -> void:
	if phase != PHASE_SEEK:
		return
	for object_id in objects:
		var obj: Dictionary = objects[object_id]
		if obj.get("is_hider", false) and obj.get("alive", false):
			obj["alive_time"] = float(obj["alive_time"]) + delta
			objects[object_id] = obj


func _try_change_shape(obj: Dictionary, shape_id: String) -> void:
	if not _shape_ids.has(shape_id):
		return
	if float(obj.get("shape_cooldown", 0.0)) > 0.0:
		return
	obj["shape"] = shape_id
	obj["shape_cooldown"] = float(config.get_value("hiders", "shape_change_cooldown", 12.0))


func _try_change_color(obj: Dictionary, color_id: String) -> void:
	if not _color_ids.has(color_id):
		return
	if float(obj.get("color_cooldown", 0.0)) > 0.0:
		return
	obj["color"] = color_id
	obj["color_cooldown"] = float(config.get_value("hiders", "color_change_cooldown", 6.0))


func _calculate_bullets() -> int:
	var hider_count := players.size()
	if hider_count <= 1:
		return int(config.get_value("seeker", "base_bullets", 3))
	return int(config.get_value("seeker", "base_bullets", 3)) + hider_count * int(config.get_value("seeker", "bullets_per_hider", 1))


func _set_phase(new_phase: String) -> void:
	phase = new_phase
	phase_elapsed = 0.0


func _finish_round() -> void:
	var seek_seconds := float(config.get_value("round", "seek_seconds", 90.0))
	scores.clear()
	for object_id in objects:
		var obj: Dictionary = objects[object_id]
		if obj.get("is_hider", false):
			var player_id: String = obj.get("owner_player_id", "")
			var hider_score := ScoreCalculatorScript.hider_score({
				"alive": obj.get("alive", false),
				"alive_time": obj.get("alive_time", 0.0),
				"freeze_near_seconds": obj.get("freeze_near_seconds", 0.0),
				"close_calls": obj.get("close_calls", 0),
				"inspected_survived": obj.get("inspected_survived", 0)
			}, seek_seconds)
			scores[player_id] = hider_score
			if players.has(player_id):
				players[player_id]["score"] = hider_score
	_set_phase(PHASE_RESULTS)


func _live_hider_count() -> int:
	var count := 0
	for object_id in objects:
		var obj: Dictionary = objects[object_id]
		if obj.get("is_hider", false) and obj.get("alive", false):
			count += 1
	return count


func _time_remaining() -> float:
	var duration := 0.0
	match phase:
		PHASE_OBJECT_RAIN:
			duration = float(config.get_value("round", "object_rain_seconds", 10.0))
		PHASE_BLACKOUT:
			duration = float(config.get_value("round", "blackout_seconds", 10.0))
		PHASE_SEEK:
			duration = float(config.get_value("round", "seek_seconds", 90.0))
		PHASE_RESULTS:
			duration = float(config.get_value("round", "results_seconds", 15.0))
		_:
			return 0.0
	return max(0.0, duration - phase_elapsed)


func _clamp_to_play_area(position: Vector3) -> Vector3:
	var planar := Vector2(position.x, position.z)
	if planar.length() > play_radius:
		planar = planar.normalized() * play_radius
	return Vector3(planar.x, max(0.15, position.y), planar.y)


func _vector3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
