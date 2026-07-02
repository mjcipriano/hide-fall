extends SceneTree

const GameConfigScript := preload("res://scripts/shared/config/game_config.gd")
const ContentDatabaseScript := preload("res://scripts/shared/content/content_database.gd")
const HidefallSimulationScript := preload("res://scripts/shared/game_state/hidefall_simulation.gd")
const NetworkMessageValidatorScript := preload("res://scripts/shared/networking/network_message_validator.gd")
const QrCodeScript := preload("res://scripts/shared/qr/qr_code.gd")
const ScoreCalculatorScript := preload("res://scripts/shared/scoring/score_calculator.gd")
const WebSocketLanHostScript := preload("res://scripts/shared/networking/websocket_lan_host.gd")
const LanGameAnnouncerScript := preload("res://scripts/shared/networking/lan_game_announcer.gd")
const LanGameBrowserScript := preload("res://scripts/shared/networking/lan_game_browser.gd")
const PropFactoryScript := preload("res://scripts/shared/props/prop_factory.gd")
const XrSettingsMenuScript := preload("res://scripts/quest/seeker/xr_settings_menu.gd")

var failures := 0


class FakeNetworkHost:
	extends RefCounted
	var sent: Array = []

	func send_to_peer(peer_id: int, message: Dictionary) -> Error:
		sent.append({"peer_id": peer_id, "message": message})
		return OK

	func stop() -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.max_fps = 0
	_test_content_loads()
	_test_config_overrides()
	_test_project_xr_startup_settings()
	_test_qr_code_generation()
	_test_network_validation()
	_test_phase_transitions()
	_test_hider_input_and_cooldowns()
	_test_shooting_and_results()
	_test_timeout_results()
	_test_disconnect_and_soak()
	_test_object_collisions()
	_test_dropped_object_gravity()
	_test_prop_stacking()
	_test_edge_slide_off()
	_test_orientation_settle()
	_test_rest_modes()
	_test_thrown_prop_tumbles()
	_test_shot_cooldown()
	_test_shot_economy()
	_test_hider_dash_and_mimic()
	_test_end_round()
	_test_hider_preferences()
	_test_prop_factory()
	_test_xr_settings_menu()
	_test_lan_discovery()
	_test_scoring_rules()
	await _test_host_scene_smoke()
	await _test_mobile_scene_smoke()
	_test_websocket_host_instantiates()
	if failures == 0:
		print("Godot tests passed")
		quit(0)
	else:
		push_error("%d Godot tests failed" % failures)
		quit(1)


func _new_sim(seed: int = 99):
	var config = GameConfigScript.new()
	config.load_default()
	var content = ContentDatabaseScript.new()
	content.load_default()
	var sim = HidefallSimulationScript.new()
	sim.setup(config, content, seed)
	return sim


func _test_content_loads() -> void:
	var config = GameConfigScript.new()
	config.load_default()
	var content = ContentDatabaseScript.new()
	content.load_default()
	_assert(int(config.get_value("objects", "decoy_count", 0)) == 75, "default decoy count loads")
	_assert(int(config.get_value("round", "room_setup_seconds", 0)) == 5, "room setup duration loads")
	_assert(bool(config.get_value("seeker", "scan_pulse_enabled", false)), "scan pulse is enabled in default config")
	_assert(float(config.get_value("seeker", "shot_cooldown_seconds", 0.0)) > 0.0, "shot cooldown is configured")
	_assert(not bool(config.get_value("round", "end_on_seek_timeout", true)), "hunt timer does not end rounds by default")
	_assert(bool(config.get_value("round", "end_when_out_of_shots", false)), "round ends when the seeker spends all shots by default")
	_assert(not bool(config.get_value("seeker", "consume_shot_on_hit", true)), "hider hits do not consume shots by default")
	_assert(config.get_value("round", "blackout_seconds", null) == null, "blackout stage setting is removed")
	_assert(int(config.get_value("network", "discovery_port", 0)) == 29445, "discovery port is configured")
	_assert(content.get_shape_ids().size() >= 16, "expanded shape set loads")
	_assert(content.get_color_ids().size() >= 12, "MVP color set loads")
	_assert(content.get_pattern_ids().size() >= 5, "pattern set loads")
	_assert(content.get_pattern_ids().has("solid"), "solid pattern exists")
	_assert(content.get_shape_rest_mode("sphere") == "any", "sphere rest mode loads")
	_assert(content.get_shape_rest_mode("ring") == "flat", "ring rest mode loads")


func _test_config_overrides() -> void:
	var path := "user://hidefall_test_settings.json"
	var config = GameConfigScript.new()
	config.load_default()
	config.set_value("seeker", "shot_cooldown_seconds", 1.5)
	config.set_value("hiders", "bot_count", 4)
	_assert(config.save_overrides(path), "config overrides save to user path")
	var loaded = GameConfigScript.new()
	loaded.load_default()
	_assert(loaded.apply_overrides(path), "config overrides apply from user path")
	_assert(absf(float(loaded.get_value("seeker", "shot_cooldown_seconds", 0.0)) - 1.5) < 0.001, "saved gun cooldown override loads")
	_assert(int(loaded.get_value("hiders", "bot_count", 0)) == 4, "saved bot count override loads")
	_assert(int(loaded.get_value("objects", "decoy_count", 0)) == 75, "deep merge keeps default settings")


func _test_project_xr_startup_settings() -> void:
	_assert(ProjectSettings.get_setting("xr/openxr/enabled", false), "OpenXR project startup is enabled")
	_assert(int(ProjectSettings.get_setting("xr/openxr/environment_blend_mode", 0)) == 0, "OpenXR starts in opaque blend mode")
	_assert(bool(ProjectSettings.get_setting("xr/openxr/extensions/meta/passthrough", false)), "Meta passthrough extension is enabled")
	_assert(bool(ProjectSettings.get_setting("xr/shaders/enabled", false)), "XR multiview shaders are enabled so passthrough renders")
	_assert(String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "mobile", "Forward Mobile renderer is selected for OpenXR")


func _test_qr_code_generation() -> void:
	var matrix := QrCodeScript.make_matrix('{"url":"ws://127.0.0.1:29444","room_id":"842913","token":"hidefall"}')
	_assert(matrix.size() == QrCodeScript.SIZE, "QR matrix has expected height")
	_assert(matrix[0].size() == QrCodeScript.SIZE, "QR matrix has expected width")
	_assert(matrix[0][0] and matrix[6][6] and matrix[30][30], "QR function patterns render")
	var texture := QrCodeScript.make_texture("hidefall", 2)
	_assert(texture != null and texture.get_width() == (QrCodeScript.SIZE + 8) * 2, "QR texture renders with quiet zone")


func _test_network_validation() -> void:
	var join_errors := NetworkMessageValidatorScript.validate_client_message({
		"type": "join_request",
		"version": 1,
		"room_id": "842913",
		"token": "abc",
		"player_name": "Sam"
	})
	_assert(join_errors.is_empty(), "valid join request passes")
	var bad_errors := NetworkMessageValidatorScript.validate_client_message({
		"type": "hider_input",
		"version": 1,
		"player_id": "p1",
		"move": [1]
	})
	_assert(not bad_errors.is_empty(), "invalid hider input fails")


func _test_phase_transitions() -> void:
	var sim = _new_sim()
	sim.add_bot_hiders(1)
	_assert(sim.start_round(), "ready players can start round")
	_assert(sim.phase == HidefallSimulationScript.PHASE_ROOM_SETUP, "round starts in room setup")
	_assert(sim.confirm_room_setup(), "room setup can be confirmed")
	_assert(sim.phase == HidefallSimulationScript.PHASE_OBJECT_RAIN, "round starts in object rain")
	_advance_for(sim, 10.2)
	_assert(sim.phase == HidefallSimulationScript.PHASE_SEEK, "object rain transitions straight to seek (no blackout)")


func _test_hider_input_and_cooldowns() -> void:
	var sim = _new_sim(123)
	var player_id := sim.add_hider("Tester")
	sim.start_round()
	sim.confirm_room_setup()
	_advance_for(sim, 20.4)
	var object_id: String = sim.players[player_id]["object_id"]
	var old_position: Vector3 = sim.objects[object_id]["position"]
	var applied := sim.apply_hider_input(player_id, {
		"move": [1.0, 0.0],
		"freeze": false,
		"request_shape": "sphere",
		"request_color": "blue"
	})
	_assert(applied, "hider input accepted during seek")
	_advance_for(sim, 0.5)
	var new_position: Vector3 = sim.objects[object_id]["position"]
	_assert(new_position.distance_to(old_position) > 0.01, "hider input moves object")
	_assert(sim.objects[object_id]["shape"] == "sphere", "shape change applies")
	_assert(sim.objects[object_id]["color"] == "blue", "color change applies")
	sim.apply_hider_input(player_id, {"move": [0, 0], "request_shape": "cone", "request_color": "red"})
	_assert(sim.objects[object_id]["shape"] == "sphere", "shape cooldown blocks repeat change")
	_assert(sim.objects[object_id]["color"] == "blue", "color cooldown blocks repeat change")
	_assert(sim.set_object_held(object_id, true), "seeker can mark object held")
	_assert(not sim.apply_hider_input(player_id, {"move": [1, 0]}), "held hider input is blocked")
	_assert(sim.move_held_object(object_id, Vector3(0.2, 0.4, 0.2)), "held object can be moved by host")
	_assert(sim.set_object_held(object_id, false), "seeker can drop held object")
	_assert(int(sim.objects[object_id]["inspected_survived"]) == 1, "dropped live hider gets inspection stat")
	sim.objects[object_id]["position"] = Vector3.ZERO
	var scan := sim.use_scan_pulse(Vector3.ZERO, 1.0)
	_assert(scan.get("accepted", false), "scan pulse is accepted during seek")
	_assert(scan.get("revealed", []).size() == 1, "scan pulse reveals nearby hider")
	_assert(sim.scan_pulses_remaining == 0, "scan pulse decrements remaining count")


func _test_shooting_and_results() -> void:
	var sim = _new_sim(321)
	var player_id := sim.add_hider("Target")
	sim.start_round()
	sim.confirm_room_setup()
	_advance_for(sim, 20.4)
	var hider_object_id: String = sim.players[player_id]["object_id"]
	var result := sim.shoot_object(hider_object_id)
	_assert(result.get("accepted", false), "shot accepted during seek")
	_assert(result.get("hit", false), "correct shot hits hider")
	_assert(sim.phase == HidefallSimulationScript.PHASE_RESULTS, "all hiders found ends round")
	_assert(int(sim.get_results()["seeker_score"]) >= 1500, "seeker receives score")


func _test_timeout_results() -> void:
	var sim = _new_sim(555)
	sim.add_hider("Survivor")
	sim.start_round()
	sim.confirm_room_setup()
	_advance_for(sim, 20.4)
	var decoy_id := sim.get_decoy_object_ids()[0]
	var wrong := sim.shoot_object(decoy_id)
	_assert(wrong.get("accepted", false) and not wrong.get("hit", true), "wrong shot damages decoy")
	_advance_for(sim, 91.0)
	_assert(sim.phase == HidefallSimulationScript.PHASE_SEEK, "hunt timer does not end the round by default")
	sim.config.set_value("round", "end_on_seek_timeout", true)
	_advance_for(sim, 0.2)
	_assert(sim.phase == HidefallSimulationScript.PHASE_RESULTS, "seek timeout ends round when the timer setting is on")
	var results := sim.get_results()
	_assert(results["hiders"].values()[0] >= 1000, "surviving hider receives survival score")


func _test_shot_economy() -> void:
	var sim = _new_sim(557)
	var player_id := sim.add_hider("Target")
	sim.start_round()
	sim.confirm_room_setup()
	_advance_for(sim, 20.4)
	var cooldown := float(sim.config.get_value("seeker", "shot_cooldown_seconds", 2.5)) + 0.2
	var shots_before: int = sim.shots_remaining
	_assert(shots_before == 3, "solo hider round starts with base bullets")
	var decoys := sim.get_decoy_object_ids()
	# Two misses each consume a shot; the round survives while ammo remains.
	sim.shoot_object(decoys[0])
	_assert(sim.shots_remaining == shots_before - 1, "miss against a decoy consumes a shot")
	_advance_for(sim, cooldown)
	sim.shoot_object(decoys[1])
	_advance_for(sim, cooldown)
	_assert(sim.phase == HidefallSimulationScript.PHASE_SEEK, "round continues while shots remain")
	# A hit on the live hider is free and ends the round because all are found.
	var hider_object_id: String = sim.players[player_id]["object_id"]
	var hit := sim.shoot_object(hider_object_id)
	_assert(hit.get("hit", false), "hider hit lands")
	_assert(sim.shots_remaining == 1, "hitting a hider does not consume a shot")
	_assert(sim.phase == HidefallSimulationScript.PHASE_RESULTS, "finding every hider still ends the round")
	# Exhausting ammo on decoys ends the round for the seeker.
	var out_sim = _new_sim(558)
	out_sim.add_hider("Escapee")
	out_sim.start_round()
	out_sim.confirm_room_setup()
	_advance_for(out_sim, 20.4)
	var out_decoys := out_sim.get_decoy_object_ids()
	for shot_index in 3:
		out_sim.shoot_object(out_decoys[shot_index])
		_advance_for(out_sim, cooldown)
	_assert(out_sim.shots_remaining == 0, "three misses spend all base bullets")
	_assert(out_sim.phase == HidefallSimulationScript.PHASE_RESULTS, "firing the last shot ends the round")
	_assert(out_sim.get_results()["hiders"].values()[0] >= 1000, "hider outlasting the seeker's ammo survives")


func _test_disconnect_and_soak() -> void:
	var disconnect_sim = _new_sim(777)
	var player_id := disconnect_sim.add_hider("Disconnect")
	disconnect_sim.start_round()
	disconnect_sim.confirm_room_setup()
	_advance_for(disconnect_sim, 20.4)
	var object_id: String = disconnect_sim.players[player_id]["object_id"]
	_assert(disconnect_sim.remove_player(player_id, true), "disconnect removes player")
	_assert(disconnect_sim.objects.has(object_id) and not disconnect_sim.objects[object_id]["is_hider"], "disconnect leaves inert decoy")
	for round_index in 10:
		var sim = _new_sim(900 + round_index)
		# Soak rounds must terminate on their own, so turn the hunt timer end on.
		sim.config.set_value("round", "end_on_seek_timeout", true)
		sim.add_bot_hiders(3)
		sim.start_round()
		sim.confirm_room_setup()
		_advance_for(sim, 130.0)
		_assert(sim.phase == HidefallSimulationScript.PHASE_RESULTS or sim.phase == HidefallSimulationScript.PHASE_LOBBY, "soak round %d reaches terminal phase" % (round_index + 1))
		_assert(not sim.get_results().is_empty(), "soak round %d has results" % (round_index + 1))
	var ready_sim = _new_sim(42)
	var waiting_id := ready_sim.add_hider("Waiting")
	ready_sim.set_player_ready(waiting_id, false)
	_assert(not ready_sim.start_round(), "unready hider blocks round start")
	ready_sim.set_player_ready(waiting_id, true)
	_assert(ready_sim.start_round(), "ready hider allows round start")
	var bot_sim = _new_sim(43)
	bot_sim.add_bot_hiders(1)
	bot_sim.start_round()
	bot_sim.confirm_room_setup()
	_advance_for(bot_sim, 10.2)
	var bot_object_id: String = bot_sim.players[bot_sim.players.keys()[0]]["object_id"]
	_assert(bot_sim.objects[bot_object_id]["move_input"].length() >= 0.0 and bot_sim.objects[bot_object_id].has("bot_decision_time"), "bot hider receives autonomous decisions")


func _test_object_collisions() -> void:
	var sim = _new_sim(4242)
	sim.add_hider("Solo", false)
	_assert(sim.start_round(), "collision round starts")
	sim.confirm_room_setup()
	var ids := sim.get_decoy_object_ids()
	_assert(ids.size() >= 2, "collision round spawns decoys")
	var a: String = ids[0]
	var b: String = ids[1]
	var min_distance: float = float(sim.objects[a]["collision_radius"]) + float(sim.objects[b]["collision_radius"])

	sim.objects[a]["held_by_seeker"] = false
	sim.objects[b]["held_by_seeker"] = false
	sim.objects[a]["position"] = Vector3(0.0, 0.15, 0.0)
	sim.objects[b]["position"] = Vector3(0.02, 0.15, 0.0)
	sim._resolve_collisions()
	var separated: float = sim.objects[a]["position"].distance_to(sim.objects[b]["position"])
	_assert(separated >= min_distance - 0.02, "overlapping props push apart to their combined radius")

	sim.objects[a]["position"] = Vector3(0.5, 0.15, 0.0)
	sim.objects[b]["position"] = Vector3(0.5, 0.15, 0.0)
	sim.objects[a]["held_by_seeker"] = true
	var held_before: Vector3 = sim.objects[a]["position"]
	sim._resolve_collisions()
	_assert(sim.objects[a]["position"].distance_to(held_before) < 0.001, "held prop is not displaced by collisions")
	_assert(sim.objects[b]["position"].distance_to(sim.objects[a]["position"]) >= min_distance - 0.02, "held prop still pushes neighbors away")


func _test_dropped_object_gravity() -> void:
	var sim = _new_sim(555)
	sim.add_hider("Solo", false)
	sim.start_round()
	var decoy: String = sim.get_decoy_object_ids()[0]
	# Isolate one prop so nothing else can support it, then lift and drop it.
	sim.objects = {decoy: sim.objects[decoy]}
	_assert(sim.set_object_held(decoy, true), "decoy can be grabbed")
	sim.move_held_object(decoy, Vector3(0.0, 1.2, 0.0))
	_assert(sim.objects[decoy]["position"].y > 1.0, "held prop lifts to hand height")
	var start_y: float = sim.objects[decoy]["position"].y
	_assert(sim.release_object(decoy, Vector3.ZERO), "held prop can be released")
	for _frame in 90:
		sim._integrate_free_decoys(0.033)
	var end_y: float = sim.objects[decoy]["position"].y
	_assert(end_y < start_y - 0.5, "released prop falls under gravity")
	_assert(end_y <= 0.2, "released prop settles on the floor")


func _test_prop_stacking() -> void:
	var sim = _new_sim(556)
	sim.add_hider("Solo", false)
	sim.start_round()
	var ids := sim.get_decoy_object_ids()
	var base_id: String = ids[0]
	var top_id: String = ids[1]
	sim.objects = {base_id: sim.objects[base_id], top_id: sim.objects[top_id]}
	for prop_id in [base_id, top_id]:
		sim.objects[prop_id]["shape"] = "cube"
		sim.objects[prop_id]["collision_radius"] = 0.19
		sim.objects[prop_id]["half_height"] = 0.14
		sim.objects[prop_id]["velocity"] = Vector3.ZERO
	sim.objects[base_id]["position"] = Vector3(0.0, 0.15, 0.0)
	sim.objects[top_id]["position"] = Vector3(0.0, 0.9, 0.0)
	for _frame in 120:
		sim._integrate_free_decoys(0.033)
		sim._resolve_collisions()
	var base_pos: Vector3 = sim.objects[base_id]["position"]
	var top_pos: Vector3 = sim.objects[top_id]["position"]
	_assert(top_pos.y > base_pos.y + 0.2, "flat prop rests on top of another prop")
	var footprint := Vector2(top_pos.x - base_pos.x, top_pos.z - base_pos.z).length()
	_assert(footprint < 0.15, "squarely stacked prop does not slide off")


func _test_orientation_settle() -> void:
	var sim = _new_sim(600)
	sim.add_hider("Solo", false)
	sim.start_round()
	var decoy: String = sim.get_decoy_object_ids()[0]
	sim.objects = {decoy: sim.objects[decoy]}
	sim.objects[decoy]["position"] = Vector3(0.0, 0.15, 0.0)
	sim.objects[decoy]["velocity"] = Vector3.ZERO
	sim.objects[decoy]["spin_speed"] = 0.0
	sim.objects[decoy]["rest_mode"] = "face"
	sim.objects[decoy]["orientation"] = Quaternion(Vector3.RIGHT, 0.9)
	for _frame in 120:
		sim._integrate_free_decoys(0.033)
	var settled: Quaternion = sim.objects[decoy]["orientation"]
	# A prop resting flat has world-up aligned with one of its own face axes.
	var local_up := settled.inverse() * Vector3.UP
	var axis_alignment := maxf(maxf(absf(local_up.x), absf(local_up.y)), absf(local_up.z))
	_assert(axis_alignment > 0.999, "dropped prop topples to rest flat on a face")
	# Yaw survives settling: a cube set down twisted 30 degrees stays twisted.
	sim.objects[decoy]["orientation"] = Quaternion(Vector3.UP, 0.5) * Quaternion(Vector3.RIGHT, 0.3)
	sim.objects[decoy]["topple_speed"] = 0.0
	for _frame in 120:
		sim._integrate_free_decoys(0.033)
	var yawed: Quaternion = sim.objects[decoy]["orientation"]
	var forward := yawed * Vector3.FORWARD
	_assert(absf((yawed * Vector3.UP).y - 1.0) < 0.001, "twisted cube still rests flat")
	_assert(absf(atan2(-forward.x, -forward.z) - 0.5) < 0.05, "twist (yaw) is preserved when settling")


func _test_rest_modes() -> void:
	var sim = _new_sim(601)
	sim.add_hider("Solo", false)
	sim.start_round()
	var ids := sim.get_decoy_object_ids()
	sim.objects = {ids[0]: sim.objects[ids[0]], ids[1]: sim.objects[ids[1]], ids[2]: sim.objects[ids[2]]}
	var positions := [Vector3(-2.0, 0.15, 0.0), Vector3(0.0, 0.15, 0.0), Vector3(2.0, 0.15, 0.0)]
	for index in 3:
		var obj_id: String = ids[index]
		sim.objects[obj_id]["position"] = positions[index]
		sim.objects[obj_id]["velocity"] = Vector3.ZERO
		sim.objects[obj_id]["spin_speed"] = 0.0
	# A cylinder knocked far over rolls onto its side, not back upright.
	sim.objects[ids[0]]["rest_mode"] = "side_or_upright"
	sim.objects[ids[0]]["orientation"] = Quaternion(Vector3.RIGHT, 1.2)
	# A sphere rests exactly as placed.
	var sphere_orientation := Quaternion(Vector3(0.3, 0.8, 0.5).normalized(), 1.1)
	sim.objects[ids[1]]["rest_mode"] = "any"
	sim.objects[ids[1]]["orientation"] = sphere_orientation
	# A tipped cone stands back up.
	sim.objects[ids[2]]["rest_mode"] = "upright"
	sim.objects[ids[2]]["orientation"] = Quaternion(Vector3.RIGHT, 0.6)
	for _frame in 150:
		sim._integrate_free_decoys(0.033)
	var cylinder_up: Vector3 = (sim.objects[ids[0]]["orientation"] as Quaternion) * Vector3.UP
	_assert(absf(cylinder_up.y) < 0.05, "tipped cylinder settles onto its side")
	var sphere_after: Quaternion = sim.objects[ids[1]]["orientation"]
	_assert(sphere_after.angle_to(sphere_orientation) < 0.01, "sphere keeps the orientation it was placed in")
	var cone_up: Vector3 = (sim.objects[ids[2]]["orientation"] as Quaternion) * Vector3.UP
	_assert(cone_up.y > 0.999, "tipped cone settles back upright")


func _test_thrown_prop_tumbles() -> void:
	var sim = _new_sim(602)
	sim.add_hider("Solo", false)
	sim.start_round()
	var decoy: String = sim.get_decoy_object_ids()[0]
	sim.objects = {decoy: sim.objects[decoy]}
	sim.set_object_held(decoy, true)
	sim.move_held_object(decoy, Vector3(0.0, 1.4, 0.0))
	var before: Quaternion = sim.objects[decoy]["orientation"]
	sim.release_object(decoy, Vector3(2.5, 0.5, 0.0))
	_assert(float(sim.objects[decoy]["spin_speed"]) > 0.5, "thrown prop receives tumble spin")
	sim._integrate_free_decoys(0.033)
	sim._integrate_free_decoys(0.033)
	var during: Quaternion = sim.objects[decoy]["orientation"]
	_assert(before.angle_to(during) > 0.05, "thrown prop tumbles while airborne")


func _test_edge_slide_off() -> void:
	var sim = _new_sim(603)
	sim.add_hider("Solo", false)
	sim.start_round()
	var ids := sim.get_decoy_object_ids()
	var base_id: String = ids[0]
	var top_id: String = ids[1]
	sim.objects = {base_id: sim.objects[base_id], top_id: sim.objects[top_id]}
	for prop_id in [base_id, top_id]:
		sim.objects[prop_id]["shape"] = "cube"
		sim.objects[prop_id]["rest_mode"] = "face"
		sim.objects[prop_id]["collision_radius"] = 0.19
		sim.objects[prop_id]["half_height"] = 0.14
		sim.objects[prop_id]["velocity"] = Vector3.ZERO
		sim.objects[prop_id]["spin_speed"] = 0.0
	sim.objects[base_id]["position"] = Vector3(0.0, 0.15, 0.0)
	# Dropped overlapping the base cube's rim, not squarely on top of it.
	sim.objects[top_id]["position"] = Vector3(0.30, 0.7, 0.0)
	for _frame in 180:
		sim._integrate_free_decoys(0.033)
	var base_pos: Vector3 = sim.objects[base_id]["position"]
	var top_pos: Vector3 = sim.objects[top_id]["position"]
	_assert(top_pos.y < 0.2, "rim-dropped prop slides off and lands on the floor")
	var footprint := Vector2(top_pos.x - base_pos.x, top_pos.z - base_pos.z).length()
	_assert(footprint > 0.3, "rim-dropped prop ends up clear of the base prop")


func _test_shot_cooldown() -> void:
	var sim = _new_sim(604)
	sim.add_bot_hiders(2)
	sim.start_round()
	sim.confirm_room_setup()
	_advance_for(sim, 20.4)
	var decoys := sim.get_decoy_object_ids()
	var first := sim.shoot_object(decoys[0])
	_assert(first.get("accepted", false), "first shot fires")
	var second := sim.shoot_object(decoys[1])
	_assert(not second.get("accepted", true), "immediate second shot is blocked")
	_assert(second.get("reason", "") == "shot_cooldown", "second shot is blocked by the gun cooldown")
	_advance_for(sim, float(sim.config.get_value("seeker", "shot_cooldown_seconds", 2.5)) + 0.2)
	var third := sim.shoot_object(decoys[1])
	_assert(third.get("accepted", false), "shot fires again after the cooldown elapses")
	_assert(sim.get_state_snapshot().has("shot_cooldown_remaining"), "snapshot exposes the gun cooldown")


func _test_hider_dash_and_mimic() -> void:
	var sim = _new_sim(607)
	var player_id := sim.add_hider("Dasher")
	sim.start_round()
	sim.confirm_room_setup()
	_advance_for(sim, 20.4)
	var object_id: String = sim.players[player_id]["object_id"]
	var hider: Dictionary = sim.objects[object_id]
	hider["position"] = Vector3.ZERO
	hider["velocity"] = Vector3.ZERO
	sim.objects[object_id] = hider
	var dash_input := {
		"move": [1.0, 0.0],
		"ability": "dash"
	}
	_assert(sim.apply_hider_input(player_id, dash_input), "dash hider input is accepted")
	_advance_for(sim, 0.12)
	_assert((sim.objects[object_id]["position"] as Vector3).x > 0.45, "dash slingshots hider forward quickly")
	_assert(float(sim.get_hider_cooldowns(player_id).get("dash", 0.0)) > 0.0, "dash cooldown is exposed")
	var decoy_id: String = sim.get_decoy_object_ids()[0]
	var decoy: Dictionary = sim.objects[decoy_id]
	decoy["position"] = sim.objects[object_id]["position"] + Vector3(0.2, 0.0, 0.0)
	decoy["shape"] = "duck"
	decoy["color"] = "purple"
	decoy["pattern"] = "stripes"
	sim.objects[decoy_id] = decoy
	var before_mimic: Dictionary = sim.objects[object_id]
	before_mimic["mimic_cooldown"] = 0.0
	sim.objects[object_id] = before_mimic
	_assert(sim.apply_hider_input(player_id, {"move": [0.0, 0.0], "ability": "mimic"}), "mimic hider input is accepted")
	_assert(sim.objects[object_id]["shape"] == "duck", "mimic copies adjacent object shape")
	_assert(sim.objects[object_id]["color"] == "purple", "mimic copies adjacent object color")
	_assert(sim.objects[object_id]["pattern"] == "stripes", "mimic copies adjacent object pattern")
	_assert(float(sim.get_hider_cooldowns(player_id).get("mimic", 0.0)) > 0.0, "mimic cooldown is exposed")


func _test_end_round() -> void:
	var sim = _new_sim(606)
	sim.add_bot_hiders(1)
	sim.start_round()
	sim.confirm_room_setup()
	_assert(sim.end_round(), "active round can be ended manually")
	_assert(sim.phase == HidefallSimulationScript.PHASE_RESULTS, "manual end round enters results")
	_assert(not sim.end_round(), "results phase is not ended again")


func _test_hider_preferences() -> void:
	var sim = _new_sim(605)
	var player_id := sim.add_hider("Chooser")
	sim.set_player_preferences(player_id, {"shape": "duck", "color": "purple", "pattern": "stripes"})
	sim.set_player_preferences(player_id, {"shape": "not_a_shape"})
	sim.start_round()
	var object_id: String = sim.players[player_id]["object_id"]
	_assert((sim.objects[object_id]["position"] as Vector3).y > 1.0, "hider starts in the ceiling drop with decoys")
	_assert(sim.objects[object_id]["shape"] == "duck", "preferred shape is used at spawn")
	_assert(sim.objects[object_id]["color"] == "purple", "preferred color is used at spawn")
	_assert(sim.objects[object_id]["pattern"] == "stripes", "preferred pattern is used at spawn")
	_assert(sim.objects[object_id]["rest_mode"] == "upright", "spawned prop carries its shape rest mode")


func _test_prop_factory() -> void:
	var content = ContentDatabaseScript.new()
	content.load_default()
	for shape_id in content.get_shape_ids():
		var prop: Node3D = PropFactoryScript.make_prop(shape_id)
		var mesh_parts := 0
		for child in prop.get_children():
			if child is MeshInstance3D:
				mesh_parts += 1
		_assert(mesh_parts >= 1, "prop factory builds mesh for shape %s" % shape_id)
		PropFactoryScript.apply_material(prop, PropFactoryScript.make_material(Color.RED, "solid"))
		prop.free()
	var striped := PropFactoryScript.make_material(Color.BLUE, "stripes")
	_assert(striped.albedo_texture != null, "striped material carries a pattern texture")
	var metallic := PropFactoryScript.make_material(Color.WHITE, "metallic")
	_assert(metallic.metallic > 0.5, "metallic pattern sets metalness")
	var glow := PropFactoryScript.make_material(Color.GREEN, "glow")
	_assert(glow.emission_enabled, "glow pattern enables emission")
	_assert(PropFactoryScript.pattern_texture("dots") == PropFactoryScript.pattern_texture("dots"), "pattern textures are cached")


func _test_xr_settings_menu() -> void:
	var config = GameConfigScript.new()
	config.load_default()
	var menu = XrSettingsMenuScript.new()
	menu.setup(config)
	root.add_child(menu)
	menu.set_open(true)
	_assert(menu.get_row_count() >= 10, "XR settings menu builds action and setting rows")
	_assert(menu.get_row_label(2).contains("Gun cooldown"), "XR settings menu shows gun cooldown row")
	_assert(menu.get_row_label(4).contains("Timer ends hunt: Off"), "XR settings menu shows the hunt timer toggle defaulting off")
	var has_blackout_row := false
	for index in menu.get_row_count():
		if menu.get_row_label(index).contains("Blackout"):
			has_blackout_row = true
	_assert(not has_blackout_row, "XR settings menu no longer offers a blackout setting")
	var changed := {"section": "", "key": "", "value": null}
	menu.setting_changed.connect(func(section, key, value) -> void:
		changed["section"] = section
		changed["key"] = key
		changed["value"] = value
	)
	var hovered := menu.update_pointer(Vector3(0.0, 0.151, 1.0), Vector3(0.0, 0.0, -1.0))
	_assert(hovered, "XR settings menu pointer intersects the panel")
	_assert(menu.activate_hovered(), "XR settings menu activates hovered setting row")
	_assert(changed.get("section", "") == "seeker" and changed.get("key", "") == "shot_cooldown_seconds", "XR settings menu emits setting change")
	_assert(absf(float(config.get_value("seeker", "shot_cooldown_seconds", 0.0)) - 3.5) < 0.001, "XR settings menu cycles config value")
	var action := {"value": ""}
	menu.action_requested.connect(func(value) -> void:
		action["value"] = String(value)
	)
	menu.force_hover(0)
	_assert(menu.activate_hovered(), "XR settings menu activates action row")
	_assert(action["value"] == "restart_round", "XR settings menu emits restart action")
	root.remove_child(menu)
	menu.free()


func _test_lan_discovery() -> void:
	var info := {
		"host_name": "Test Room",
		"host_ip": "192.168.1.50",
		"port": 29444,
		"room_id": "842913",
		"token": "hidefall",
		"phase": "lobby",
		"players": 2
	}
	var beacon := LanGameAnnouncerScript.build_beacon(info)
	var parsed := LanGameBrowserScript.parse_beacon(beacon, "192.168.1.50")
	_assert(not parsed.is_empty(), "beacon parses back")
	_assert(parsed.get("room_id", "") == "842913", "beacon carries room id")
	_assert(parsed.get("host_ip", "") == "192.168.1.50", "beacon host ip comes from the sender address")
	_assert(LanGameBrowserScript.parse_beacon("{\"game\":\"other\"}").is_empty(), "foreign beacons are rejected")
	_assert(LanGameBrowserScript.parse_beacon("not json").is_empty(), "garbage beacons are rejected")
	# Best-effort live loopback check; skipped when the sandbox blocks UDP.
	var browser = LanGameBrowserScript.new()
	var bind_error: Error = browser.udp.bind(38455)
	if bind_error == OK:
		var sender := PacketPeerUDP.new()
		sender.set_dest_address("127.0.0.1", 38455)
		sender.put_packet(beacon.to_utf8_buffer())
		OS.delay_msec(50)
		var received: bool = browser.udp.get_available_packet_count() > 0
		_assert(received, "loopback beacon is received over UDP")
		browser.udp.close()
	else:
		print("SKIP: UDP loopback unavailable in this environment")
	browser.free()


func _test_scoring_rules() -> void:
	var moving := ScoreCalculatorScript.hider_score({"alive": true, "alive_time": 10.0, "distance_moved": 12.0}, 90.0)
	var still := ScoreCalculatorScript.hider_score({"alive": true, "alive_time": 10.0, "distance_moved": 0.0}, 90.0)
	_assert(moving > still, "hiders earn more the more they move")
	var finder := ScoreCalculatorScript.seeker_score({"correct_shots": 2, "wrong_shots": 0, "all_hiders_found": true})
	var misser := ScoreCalculatorScript.seeker_score({"correct_shots": 1, "wrong_shots": 0})
	_assert(finder > misser, "seeker earns points for finding hiders")
	var clean := ScoreCalculatorScript.seeker_score({"correct_shots": 1, "wrong_shots": 0})
	var sloppy := ScoreCalculatorScript.seeker_score({"correct_shots": 1, "wrong_shots": 2})
	_assert(sloppy < clean, "seeker loses points for shooting the wrong prop")


func _test_host_scene_smoke() -> void:
	var packed_scene = load("res://scenes/quest/host_prototype.tscn")
	_assert(packed_scene != null, "host prototype scene loads")
	var scene = packed_scene.instantiate()
	_assert(scene.get_script() != null, "host prototype script loads")
	scene.auto_start_network = false
	root.add_child(scene)
	await process_frame
	await process_frame
	_assert(scene.simulation != null, "host scene creates simulation")
	_assert(scene.simulation.phase == HidefallSimulationScript.PHASE_LOBBY, "host scene starts in lobby")
	_assert(scene.settings_menu != null, "host scene creates settings menu")
	scene.settings_menu.force_hover(2)
	scene.settings_menu.activate_hovered()
	_assert(absf(float(scene.config.get_value("seeker", "shot_cooldown_seconds", 0.0)) - 3.5) < 0.001, "host settings menu updates config")
	var bot_count_before: int = scene.simulation.players.size()
	scene.config.set_value("hiders", "bot_count", 3)
	scene._reconcile_bot_hiders()
	_assert(scene.simulation.players.size() == bot_count_before + 1, "host reconciles configured bot hider count")
	scene._update_hud()
	_assert(not scene.get_join_payload_text().is_empty(), "host scene creates join payload")
	_assert(scene.get_join_payload_text().to_utf8_buffer().size() <= 106, "host join payload fits QR capacity")
	_assert(scene.qr_texture_rect.texture != null, "host scene creates join QR texture")
	scene._start_visible_solo_round()
	_assert(scene.simulation.phase == HidefallSimulationScript.PHASE_OBJECT_RAIN, "host scene can start a visible solo round")
	_assert(scene.object_nodes.size() >= 75, "visible solo round creates prop nodes immediately")
	var takeover_host := FakeNetworkHost.new()
	scene.network_host = takeover_host
	scene._handle_join_request(99, {
		"type": "join_request",
		"version": 1,
		"room_id": "842913",
		"token": "hidefall",
		"player_name": "Phone Join",
		"preferred_shape": "duck",
		"preferred_color": "purple",
		"preferred_pattern": "stripes"
	})
	var takeover_id: String = scene.peer_to_player.get(99, "")
	_assert(not takeover_id.is_empty(), "active round join takes over a bot hider")
	_assert(not scene.simulation.players[takeover_id].get("is_bot", true), "taken-over hider is no longer a bot")
	_assert(takeover_host.sent[0]["message"]["type"] == "join_accepted" and not takeover_host.sent[0]["message"]["spectator"], "active round bot takeover joins as playable hider")
	var takeover_object_id: String = scene.simulation.players[takeover_id]["object_id"]
	_assert(scene.simulation.objects[takeover_object_id]["shape"] == "duck", "bot takeover applies chosen shape to existing hider")
	scene.peer_to_player.erase(99)
	scene.simulation.remove_player(takeover_id, true)
	for player_id in scene.simulation.players.keys():
		if scene.simulation.players[player_id].get("is_bot", false):
			scene.simulation.remove_player(player_id, true)
	var decoy_takeover_host := FakeNetworkHost.new()
	scene.network_host = decoy_takeover_host
	scene._handle_join_request(100, {
		"type": "join_request",
		"version": 1,
		"room_id": "842913",
		"token": "hidefall",
		"player_name": "Late Decoy"
	})
	var decoy_takeover_id: String = scene.peer_to_player.get(100, "")
	_assert(not decoy_takeover_id.is_empty(), "active round join can take over a decoy when no bot is available")
	_assert(not decoy_takeover_host.sent[0]["message"]["spectator"], "decoy takeover joins as playable hider")
	var decoy_object_id: String = scene.simulation.players[decoy_takeover_id]["object_id"]
	_assert(scene.simulation.objects[decoy_object_id]["is_hider"], "decoy takeover converts the body into a hider")
	scene.peer_to_player.erase(100)
	scene.simulation.remove_player(decoy_takeover_id, true)
	scene.simulation._set_phase(HidefallSimulationScript.PHASE_LOBBY)
	scene.simulation.objects.clear()
	scene._rebuild_objects()
	var fake_host := FakeNetworkHost.new()
	scene.network_host = fake_host
	scene._handle_join_request(7, {
		"type": "join_request",
		"version": 1,
		"room_id": "842913",
		"token": "hidefall",
		"player_name": "Remote",
		"preferred_shape": "duck",
		"preferred_color": "purple",
		"preferred_pattern": "stripes"
	})
	_assert(scene.peer_to_player.has(7), "host accepts valid mobile join")
	_assert(fake_host.sent[0]["message"]["type"] == "join_accepted", "host sends join acceptance")
	_assert(fake_host.sent[0]["message"].has("patterns"), "join acceptance lists available patterns")
	_assert(not scene.simulation.can_start_round(), "joined mobile hider must ready before round start")
	_assert(scene.simulation.players[scene.peer_to_player[7]]["preferred_shape"] == "duck", "host stores pre-join disguise preference")
	scene.simulation.set_player_ready(scene.peer_to_player[7], true)
	scene.simulation.start_round()
	var remote_object_id: String = scene.simulation.players[scene.peer_to_player[7]]["object_id"]
	_assert(scene.simulation.objects[remote_object_id]["shape"] == "duck", "remote hider spawns with chosen shape")
	scene.simulation.confirm_room_setup()
	_advance_for(scene.simulation, 20.4)
	scene._handle_join_request(8, {
		"type": "join_request",
		"version": 1,
		"room_id": "842913",
		"token": "hidefall",
		"player_name": "Late"
	})
	var late_player_id: String = scene.peer_to_player.get(8, "")
	_assert(fake_host.sent[-2]["message"]["type"] == "join_accepted" and not fake_host.sent[-2]["message"]["spectator"], "host accepts default late join as playable takeover")
	_assert(not late_player_id.is_empty() and not String(scene.simulation.players[late_player_id].get("object_id", "")).is_empty(), "late playable join owns a hider body")
	scene._rebuild_objects()
	_assert(scene.object_nodes.size() >= 75, "host scene creates visible prop nodes")
	var ray: Dictionary = scene._get_seeker_ray()
	var pick_id: String = scene.simulation.get_decoy_object_ids()[0]
	scene.simulation.objects[pick_id]["position"] = ray["origin"] + ray["direction"] * 1.0
	_assert(scene._pick_object_from_seeker_ray() == pick_id, "host ray picks object")
	scene._begin_grab()
	_assert(scene.held_object_id == pick_id, "host grip grabs object")
	scene._update_held_object(0.016)
	_assert(scene.simulation.objects[pick_id]["held_by_seeker"], "host updates held object")
	scene._end_grab()
	_assert(scene.held_object_id.is_empty(), "host grip release drops object")
	_assert(not scene.simulation.objects[pick_id]["held_by_seeker"], "released prop is no longer held")
	var scan_before: int = scene.simulation.scan_pulses_remaining
	scene._use_scan_pulse()
	_assert(scene.simulation.scan_pulses_remaining == max(0, scan_before - 1), "host scan pulse consumes pulse")
	root.remove_child(scene)
	scene.free()
	await process_frame


func _test_mobile_scene_smoke() -> void:
	var packed_scene = load("res://scenes/mobile/hider_client.tscn")
	_assert(packed_scene != null, "mobile hider scene loads")
	var scene = packed_scene.instantiate()
	_assert(scene.get_script() != null, "mobile hider script loads")
	root.add_child(scene)
	await process_frame
	await process_frame
	var menu_card: Control = scene.menu_panel.get_node("MenuCenter/MenuCard")
	var viewport_center := root.get_visible_rect().size * 0.5
	var card_center := menu_card.get_global_rect().get_center()
	_assert(card_center.distance_to(viewport_center) < 3.0, "mobile lobby card is centered after layout")
	_assert(menu_card.get_global_rect().position.x >= -1.0 and menu_card.get_global_rect().position.y >= -1.0, "mobile lobby card is not clipped offscreen")
	# Pre-join disguise selection flows into the join request.
	scene.selected_shape_index = scene.available_shapes.find("duck")
	scene.selected_color_index = scene.available_colors.find("purple")
	scene.selected_pattern_index = scene.available_patterns.find("stripes")
	scene._refresh_selection_ui()
	var join_request: Dictionary = scene.build_join_request()
	_assert(NetworkMessageValidatorScript.validate_client_message(join_request).is_empty(), "mobile join request validates")
	_assert(join_request["preferred_shape"] == "duck", "join request carries chosen shape")
	_assert(join_request["preferred_color"] == "purple", "join request carries chosen color")
	_assert(join_request["preferred_pattern"] == "stripes", "join request carries chosen pattern")
	scene._on_message_received({
		"type": "join_accepted",
		"version": 1,
		"player_id": "p1",
		"room_id": "842913",
		"spectator": false,
		"shapes": ["cube", "sphere"],
		"colors": ["red", "blue"],
		"patterns": ["solid", "dots"]
	})
	_assert(scene.game_panel.visible and not scene.menu_panel.visible, "joining switches to the in-game screen")
	scene._on_ready_pressed()
	_assert(scene.player_ready, "mobile ready button toggles ready")
	scene.player_id = "p1"
	scene.selected_color_index = 0
	scene.selected_shape_index = 0
	scene._request_next_color()
	scene._request_next_shape()
	var input: Dictionary = scene.build_hider_input()
	_assert(NetworkMessageValidatorScript.validate_client_message(input).is_empty(), "mobile scene builds valid hider input")
	_assert(input["request_color"] == "blue", "mobile color button queues color request")
	_assert(input["request_shape"] == "sphere", "mobile shape button queues shape request")
	scene._request_dash()
	var dash_input: Dictionary = scene.build_hider_input()
	_assert(dash_input["ability"] == "dash", "mobile dash button queues dash ability")
	scene._request_mimic()
	var mimic_input: Dictionary = scene.build_hider_input()
	_assert(mimic_input["ability"] == "mimic", "mobile mimic button queues mimic ability")
	scene.apply_snapshot({
		"type": "state_snapshot",
		"version": 1,
		"server_tick": 1,
		"phase": "seek",
		"time_remaining": 80.0,
		"shots_remaining": 4,
		"shot_cooldown_remaining": 1.2,
		"danger": "watched",
		"cooldowns": {"shape": 3.0, "color": 1.0},
		"seeker": {"position": [1.0, 1.6, 1.0], "forward": [0.0, 0.0, -1.0]},
		"hider_state": {"player_id": "p1", "object_id": "obj_001", "alive": true, "shape": "sphere", "color": "blue", "pattern": "dots", "position": [0.0, 0.15, 0.0]},
		"objects": [
			{"object_id": "obj_001", "shape": "sphere", "color": "blue", "pattern": "dots", "position": [0.0, 0.15, 0.0], "orientation": [0.0, 0.0, 0.0, 1.0], "velocity": [0.0, 0.0, 0.0], "is_hider": true, "alive": true},
			{"object_id": "obj_002", "shape": "mug", "color": "red", "pattern": "stripes", "position": [1.0, 0.15, 0.5], "orientation": [0.0, 0.0, 0.0, 1.0], "velocity": [0.0, 0.0, 0.0], "is_hider": false, "alive": true}
		]
	})
	_assert(scene.current_phase == "seek" and scene.danger == "watched", "mobile scene applies state snapshots")
	_assert(scene.world_props.size() == 2, "mobile scene mirrors snapshot objects into the 3D world")
	_assert(scene.seeker_avatar.visible, "mobile scene shows the seeker avatar during a round")
	# Camera-relative movement converts joystick pushes into world axes.
	scene.cam_yaw = 0.0
	scene.move_vector = Vector2(0.0, -1.0)
	var forward_input: Dictionary = scene.build_hider_input()
	_assert(absf(float(forward_input["move"][0])) < 0.01 and float(forward_input["move"][1]) < -0.9, "joystick up moves away from the camera")
	scene.move_vector = Vector2.ZERO
	root.remove_child(scene)
	scene.free()
	await process_frame


func _test_websocket_host_instantiates() -> void:
	var host = WebSocketLanHostScript.new()
	_assert(host != null, "websocket LAN host instantiates")
	host.free()


func _advance_for(sim, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var delta = min(0.1, remaining)
		sim.advance(delta)
		remaining -= delta


func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
