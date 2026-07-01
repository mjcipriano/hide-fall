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
var scan_pulses_remaining := 0
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
	scan_pulses_remaining = 0
	players.clear()
	objects.clear()
	scores.clear()
	stats = {
		"correct_shots": 0,
		"wrong_shots": 0,
		"shots_fired": 0,
		"scan_pulses_used": 0,
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


func add_spectator(player_name: String) -> String:
	var player_id := "p%d" % _next_player_index
	_next_player_index += 1
	players[player_id] = {
		"id": player_id,
		"name": player_name,
		"role": "spectator",
		"ready": false,
		"is_bot": false,
		"alive": false,
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
	if phase == PHASE_LOBBY and players[player_id].get("role", "") == "spectator" and ready:
		players[player_id]["role"] = "hider"
		players[player_id]["alive"] = true
	return true


func add_bot_hiders(count: int) -> Array[String]:
	var ids: Array[String] = []
	for index in count:
		ids.append(add_hider("Bot %d" % (index + 1), true))
	return ids


func can_start_round() -> bool:
	if players.is_empty():
		return true
	for player_id in players:
		var player: Dictionary = players[player_id]
		if player.get("role", "") == "hider" and not player.get("ready", false):
			return false
	return true


func start_round() -> bool:
	if not can_start_round():
		return false
	if _active_hider_player_ids().is_empty():
		add_bot_hiders(1)
	objects.clear()
	_next_object_index = 1
	for player_id in players:
		if players[player_id].get("role", "") == "spectator" and players[player_id].get("ready", false):
			players[player_id]["role"] = "hider"
		if players[player_id].get("role", "") == "hider":
			players[player_id]["alive"] = true
			players[player_id]["object_id"] = ""
			players[player_id]["score"] = 0
	_spawn_decoys()
	_spawn_hiders()
	shots_remaining = _calculate_bullets()
	scan_pulses_remaining = int(config.get_value("seeker", "scan_pulse_count", 1)) if bool(config.get_value("seeker", "scan_pulse_enabled", true)) else 0
	stats["correct_shots"] = 0
	stats["wrong_shots"] = 0
	stats["shots_fired"] = 0
	stats["scan_pulses_used"] = 0
	stats["all_hiders_found"] = false
	stats["time_bonus"] = 0.0
	_set_phase(PHASE_ROOM_SETUP if float(config.get_value("round", "room_setup_seconds", 5.0)) > 0.0 else PHASE_OBJECT_RAIN)
	return true


func confirm_room_setup() -> bool:
	if phase != PHASE_ROOM_SETUP:
		return false
	_set_phase(PHASE_OBJECT_RAIN)
	return true


func advance(delta: float) -> void:
	server_tick += 1
	phase_elapsed += delta
	_update_hider_scores(delta)
	match phase:
		PHASE_ROOM_SETUP:
			if phase_elapsed >= float(config.get_value("round", "room_setup_seconds", 5.0)):
				_set_phase(PHASE_OBJECT_RAIN)
		PHASE_OBJECT_RAIN:
			_integrate_object_rain(delta)
			if phase_elapsed >= float(config.get_value("round", "object_rain_seconds", 10.0)):
				_set_phase(PHASE_BLACKOUT)
		PHASE_BLACKOUT:
			_update_bot_inputs(delta)
			_integrate_free_decoys(delta)
			if phase_elapsed >= float(config.get_value("round", "blackout_seconds", 10.0)):
				_set_phase(PHASE_SEEK)
		PHASE_SEEK:
			_update_bot_inputs(delta)
			_integrate_hider_motion(delta)
			_integrate_free_decoys(delta)
			if _live_hider_count() == 0:
				stats["all_hiders_found"] = true
				stats["time_bonus"] = _time_remaining()
				_finish_round()
			elif phase_elapsed >= float(config.get_value("round", "seek_seconds", 90.0)):
				_finish_round()
		PHASE_RESULTS:
			if phase_elapsed >= float(config.get_value("round", "results_seconds", 15.0)):
				_set_phase(PHASE_LOBBY)
	if phase != PHASE_LOBBY and objects.size() > 1:
		_resolve_collisions()


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


func use_scan_pulse(origin: Vector3, radius: float = 1.35) -> Dictionary:
	if phase != PHASE_SEEK:
		return {"accepted": false, "reason": "not_seek_phase", "revealed": []}
	if scan_pulses_remaining <= 0:
		return {"accepted": false, "reason": "no_scan_pulses_remaining", "revealed": []}
	scan_pulses_remaining -= 1
	stats["scan_pulses_used"] = int(stats.get("scan_pulses_used", 0)) + 1
	var revealed: Array = []
	for object_id in objects:
		var obj: Dictionary = objects[object_id]
		if obj.get("is_hider", false) and obj.get("alive", false) and obj.get("position", Vector3.ZERO).distance_to(origin) <= radius:
			revealed.append({
				"object_id": object_id,
				"player_id": obj.get("owner_player_id", ""),
				"distance": obj.get("position", Vector3.ZERO).distance_to(origin)
			})
	return {"accepted": true, "revealed": revealed, "radius": radius}


func set_object_held(object_id: String, held: bool) -> bool:
	if not objects.has(object_id):
		return false
	var obj: Dictionary = objects[object_id]
	obj["held_by_seeker"] = held
	if held:
		obj["velocity"] = Vector3.ZERO
	elif obj.get("is_hider", false) and obj.get("alive", false):
		obj["inspected_survived"] = int(obj.get("inspected_survived", 0)) + 1
	objects[object_id] = obj
	return true


func release_object(object_id: String, velocity: Vector3 = Vector3.ZERO) -> bool:
	if not objects.has(object_id):
		return false
	var obj: Dictionary = objects[object_id]
	if not obj.get("held_by_seeker", false):
		return false
	obj["held_by_seeker"] = false
	obj["velocity"] = velocity.limit_length(8.0)
	if obj.get("is_hider", false) and obj.get("alive", false):
		obj["inspected_survived"] = int(obj.get("inspected_survived", 0)) + 1
	objects[object_id] = obj
	return true


# Gravity + settling for free (unheld) decoys. Props fall until they land on the
# floor or come to rest on top of another prop whose footprint they overlap, so
# flat props placed squarely on others stack instead of sliding off.
func _integrate_free_decoys(delta: float) -> void:
	for object_id in objects:
		var obj: Dictionary = objects[object_id]
		if obj.get("is_hider", false) or obj.get("held_by_seeker", false):
			continue
		var velocity: Vector3 = obj["velocity"]
		var position: Vector3 = obj["position"]
		# Only props that are off the floor or still moving can be stacked; floor
		# props short-circuit the O(n) support scan.
		var support_y := 0.15
		if position.y > 0.16 or velocity.length() >= 0.06:
			support_y = _support_height(object_id, obj)
		if position.y <= support_y + 0.002 and velocity.length() < 0.06:
			_settle_orientation(obj, delta)
			obj["velocity"] = Vector3.ZERO
			obj["position"] = _clamp_to_play_area(Vector3(position.x, support_y, position.z))
			objects[object_id] = obj
			continue
		velocity.y -= 9.8 * delta
		position += velocity * delta
		if position.y <= support_y:
			position.y = support_y
			velocity.y = abs(velocity.y) * 0.18
			velocity.x *= 0.85
			velocity.z *= 0.85
		_settle_orientation(obj, delta)
		obj["velocity"] = velocity.limit_length(8.0)
		obj["position"] = _clamp_to_play_area(position)
		objects[object_id] = obj


# Rotate a settling prop toward an upright, yaw-only pose so props dropped on an
# edge or corner tip over and come to rest on a flat face.
func _settle_orientation(obj: Dictionary, delta: float) -> void:
	var current: Quaternion = obj.get("orientation", Quaternion.IDENTITY)
	var yaw := current.get_euler(EULER_ORDER_YXZ).y
	var target := Quaternion(Vector3.UP, yaw)
	if current.angle_to(target) < 0.02:
		obj["orientation"] = target
		return
	obj["orientation"] = current.slerp(target, clampf(delta * 6.0, 0.0, 1.0)).normalized()


# Highest resting center height for a prop: the floor, or the top of any prop
# whose footprint it sits squarely over.
func _support_height(object_id: String, obj: Dictionary) -> float:
	var support := 0.15
	var self_radius := float(obj.get("collision_radius", 0.18))
	var self_half := float(obj.get("half_height", 0.15))
	var position: Vector3 = obj["position"]
	for other_id in objects:
		if other_id == object_id:
			continue
		var other: Dictionary = objects[other_id]
		if other.get("is_hider", false) and not other.get("alive", true):
			continue
		var other_position: Vector3 = other["position"]
		if other_position.y >= position.y + 0.02:
			continue
		var footprint := Vector2(position.x - other_position.x, position.z - other_position.z).length()
		if footprint < (self_radius + float(other.get("collision_radius", 0.18))) * 0.7:
			var top := other_position.y + float(other.get("half_height", 0.15)) + self_half
			if top > support:
				support = top
	return support


func move_held_object(object_id: String, position: Vector3) -> bool:
	if not objects.has(object_id):
		return false
	var obj: Dictionary = objects[object_id]
	if not obj.get("held_by_seeker", false):
		return false
	obj["position"] = _clamp_to_play_area(position)
	obj["velocity"] = Vector3.ZERO
	objects[object_id] = obj
	return true


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
			"scan_pulses_remaining": scan_pulses_remaining,
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
		"url": "ws://%s:%d" % [host_ip, port],
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
		if players[player_id].get("role", "") != "hider":
			continue
		var object_id := _create_object(true, player_id)
		players[player_id]["object_id"] = object_id


func _create_object(is_hider: bool, owner_player_id: String) -> String:
	var object_id := "obj_%03d" % _next_object_index
	_next_object_index += 1
	var angle := rng.randf_range(0.0, TAU)
	var radius := sqrt(rng.randf()) * play_radius
	var y := float(config.get_value("objects", "spawn_height_meters", 2.5)) if not is_hider else 0.15
	var position := Vector3(cos(angle) * radius, y, sin(angle) * radius)
	var shape: String = content.pick_weighted_shape(rng)
	var rotation_y := rng.randf_range(0.0, TAU)
	objects[object_id] = {
		"object_id": object_id,
		"shape": shape,
		"collision_radius": _collision_radius_for_shape(shape),
		"half_height": _half_height_for_shape(shape),
		"color": content.pick_color(rng),
		"position": position,
		"rotation_y": rotation_y,
		"orientation": Quaternion(Vector3.UP, rotation_y),
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
		"inspected_survived": 0,
		"distance_moved": 0.0,
		"bot_decision_time": 0.0
	}
	return object_id


func _update_bot_inputs(delta: float) -> void:
	for player_id in players:
		var player: Dictionary = players[player_id]
		if not player.get("is_bot", false) or not player.get("alive", false):
			continue
		var object_id: String = player.get("object_id", "")
		if object_id.is_empty() or not objects.has(object_id):
			continue
		var obj: Dictionary = objects[object_id]
		var decision_time := float(obj.get("bot_decision_time", 0.0)) - delta
		if decision_time <= 0.0:
			var direction := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).limit_length(1.0)
			obj["move_input"] = direction if rng.randf() > 0.28 else Vector2.ZERO
			obj["freeze"] = rng.randf() < 0.35
			obj["bot_decision_time"] = float(config.get_value("hiders", "bot_decision_seconds", 1.6)) * rng.randf_range(0.7, 1.4)
		else:
			obj["bot_decision_time"] = decision_time
		objects[object_id] = obj


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
		var airborne: bool = obj["position"].y > 0.151
		if obj.get("freeze", false) and not airborne:
			obj["velocity"] = Vector3.ZERO
			if obj["position"].distance_to(seeker_position) < 1.5:
				obj["freeze_near_seconds"] = float(obj["freeze_near_seconds"]) + delta
		else:
			var move: Vector2 = Vector2.ZERO if airborne else obj.get("move_input", Vector2.ZERO)
			var speed := float(config.get_value("hiders", "movement_speed", 1.0))
			var acceleration := Vector3(move.x, 0.0, move.y) * speed * 4.0
			var velocity: Vector3 = obj["velocity"]
			velocity.x = (velocity.x + acceleration.x * delta) * 0.88
			velocity.z = (velocity.z + acceleration.z * delta) * 0.88
			var planar := Vector2(velocity.x, velocity.z).limit_length(2.4 * speed)
			velocity.x = planar.x
			velocity.z = planar.y
			velocity.y -= 9.8 * delta
			var next_position: Vector3 = obj["position"] + velocity * delta
			if next_position.y <= 0.15:
				next_position.y = 0.15
				velocity.y = 0.0
			var clamped_next := _clamp_to_play_area(next_position)
			if phase == PHASE_SEEK:
				var step := Vector2(clamped_next.x - obj["position"].x, clamped_next.z - obj["position"].z)
				obj["distance_moved"] = float(obj.get("distance_moved", 0.0)) + step.length()
			obj["velocity"] = velocity
			obj["position"] = clamped_next
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
	obj["collision_radius"] = _collision_radius_for_shape(shape_id)
	obj["half_height"] = _half_height_for_shape(shape_id)
	obj["shape_cooldown"] = float(config.get_value("hiders", "shape_change_cooldown", 12.0))


func _try_change_color(obj: Dictionary, color_id: String) -> void:
	if not _color_ids.has(color_id):
		return
	if float(obj.get("color_cooldown", 0.0)) > 0.0:
		return
	obj["color"] = color_id
	obj["color_cooldown"] = float(config.get_value("hiders", "color_change_cooldown", 6.0))


func _calculate_bullets() -> int:
	var hider_count := _active_hider_player_ids().size()
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
				"inspected_survived": obj.get("inspected_survived", 0),
				"distance_moved": obj.get("distance_moved", 0.0)
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
		PHASE_ROOM_SETUP:
			duration = float(config.get_value("round", "room_setup_seconds", 5.0))
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


func _collision_radius_for_shape(shape_id: String) -> float:
	match shape_id:
		"capsule":
			return 0.15
		"sphere", "duck", "cylinder", "can", "mug", "cone":
			return 0.16
		"ring":
			return 0.17
		"cube", "toy_block":
			return 0.19
		"pyramid", "star":
			return 0.20
	return 0.18


# Vertical half-extent used for stacking: how high above a prop's center its top
# surface sits, and how far its resting center is above whatever supports it.
func _half_height_for_shape(shape_id: String) -> float:
	match shape_id:
		"ring":
			return 0.08
		"cube", "toy_block", "pyramid", "star":
			return 0.14
		"sphere", "duck":
			return 0.16
		"cylinder", "can", "mug", "cone":
			return 0.17
		"capsule":
			return 0.18
	return 0.15


# Horizontal collision so props push each other apart instead of interpenetrating.
# Separation only applies to props that actually overlap vertically, so a prop
# resting on top of another (stacked) is left alone instead of sliding off. Held
# props and eliminated hiders shove others but are not themselves displaced.
func _resolve_collisions(iterations: int = 2) -> void:
	var ids: Array = []
	var pos: Dictionary = {}
	var rad: Dictionary = {}
	var half: Dictionary = {}
	var movable: Dictionary = {}
	for object_id in objects:
		var obj: Dictionary = objects[object_id]
		if obj.get("is_hider", false) and not obj.get("alive", false):
			continue
		ids.append(object_id)
		pos[object_id] = obj["position"]
		rad[object_id] = float(obj.get("collision_radius", 0.18))
		half[object_id] = float(obj.get("half_height", 0.15))
		movable[object_id] = not obj.get("held_by_seeker", false)
	var count := ids.size()
	if count < 2:
		return
	for _iteration in iterations:
		for i in range(count):
			var id_a: String = ids[i]
			var pos_a: Vector3 = pos[id_a]
			var rad_a: float = rad[id_a]
			var half_a: float = half[id_a]
			var move_a: bool = movable[id_a]
			for j in range(i + 1, count):
				var id_b: String = ids[j]
				var pos_b: Vector3 = pos[id_b]
				# Skip props that are stacked (vertically clear of each other).
				if abs(pos_a.y - pos_b.y) >= half_a + half[id_b] - 0.02:
					continue
				var offset := Vector2(pos_a.x - pos_b.x, pos_a.z - pos_b.z)
				var min_distance: float = rad_a + rad[id_b]
				var distance := offset.length()
				if distance >= min_distance:
					continue
				var normal: Vector2
				if distance > 0.0001:
					normal = offset / distance
				else:
					normal = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
					distance = 0.0
				var overlap := min_distance - distance
				var move_b: bool = movable[id_b]
				var push := Vector3(normal.x, 0.0, normal.y)
				if move_a and move_b:
					pos_a += push * (overlap * 0.5)
					pos[id_b] = pos_b - push * (overlap * 0.5)
				elif move_a:
					pos_a += push * overlap
				elif move_b:
					pos[id_b] = pos_b - push * overlap
			pos[id_a] = pos_a
	for object_id in ids:
		var obj: Dictionary = objects[object_id]
		obj["position"] = _clamp_to_play_area(pos[object_id])
		objects[object_id] = obj


func _clamp_to_play_area(position: Vector3) -> Vector3:
	var planar := Vector2(position.x, position.z)
	if planar.length() > play_radius:
		planar = planar.normalized() * play_radius
	return Vector3(planar.x, max(0.15, position.y), planar.y)


func _vector3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _active_hider_player_ids() -> Array[String]:
	var ids: Array[String] = []
	for player_id in players:
		if players[player_id].get("role", "") == "hider":
			ids.append(player_id)
	return ids
