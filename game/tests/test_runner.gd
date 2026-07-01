extends SceneTree

const GameConfigScript := preload("res://scripts/shared/config/game_config.gd")
const ContentDatabaseScript := preload("res://scripts/shared/content/content_database.gd")
const HidefallSimulationScript := preload("res://scripts/shared/game_state/hidefall_simulation.gd")
const NetworkMessageValidatorScript := preload("res://scripts/shared/networking/network_message_validator.gd")
const QrCodeScript := preload("res://scripts/shared/qr/qr_code.gd")
const ScoreCalculatorScript := preload("res://scripts/shared/scoring/score_calculator.gd")
const WebSocketLanHostScript := preload("res://scripts/shared/networking/websocket_lan_host.gd")

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
	_test_orientation_settle()
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
	_assert(content.get_shape_ids().size() >= 12, "MVP shape set loads")
	_assert(content.get_color_ids().size() >= 12, "MVP color set loads")


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
	_assert(sim.phase == HidefallSimulationScript.PHASE_BLACKOUT, "object rain transitions to blackout")
	_advance_for(sim, 10.2)
	_assert(sim.phase == HidefallSimulationScript.PHASE_SEEK, "blackout transitions to seek")


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
	_assert(sim.phase == HidefallSimulationScript.PHASE_RESULTS, "seek timeout ends round")
	var results := sim.get_results()
	_assert(results["hiders"].values()[0] >= 1000, "surviving hider receives survival score")


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
	sim.objects[decoy]["orientation"] = Quaternion(Vector3.RIGHT, 0.9)
	for _frame in 60:
		sim._integrate_free_decoys(0.033)
	var settled: Quaternion = sim.objects[decoy]["orientation"]
	var local_up := settled * Vector3.UP
	_assert(local_up.dot(Vector3.UP) > 0.99, "dropped prop settles upright onto a flat face")


func _test_scoring_rules() -> void:
	var moving := ScoreCalculator.hider_score({"alive": true, "alive_time": 10.0, "distance_moved": 12.0}, 90.0)
	var still := ScoreCalculator.hider_score({"alive": true, "alive_time": 10.0, "distance_moved": 0.0}, 90.0)
	_assert(moving > still, "hiders earn more the more they move")
	var finder := ScoreCalculator.seeker_score({"correct_shots": 2, "wrong_shots": 0, "all_hiders_found": true})
	var misser := ScoreCalculator.seeker_score({"correct_shots": 1, "wrong_shots": 0})
	_assert(finder > misser, "seeker earns points for finding hiders")
	var clean := ScoreCalculator.seeker_score({"correct_shots": 1, "wrong_shots": 0})
	var sloppy := ScoreCalculator.seeker_score({"correct_shots": 1, "wrong_shots": 2})
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
	scene._update_hud()
	_assert(not scene.get_join_payload_text().is_empty(), "host scene creates join payload")
	_assert(scene.get_join_payload_text().to_utf8_buffer().size() <= 106, "host join payload fits QR capacity")
	_assert(scene.qr_texture_rect.texture != null, "host scene creates join QR texture")
	scene._start_visible_solo_round()
	_assert(scene.simulation.phase == HidefallSimulationScript.PHASE_OBJECT_RAIN, "host scene can start a visible solo round")
	_assert(scene.object_nodes.size() >= 75, "visible solo round creates prop nodes immediately")
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
		"player_name": "Remote"
	})
	_assert(scene.peer_to_player.has(7), "host accepts valid mobile join")
	_assert(fake_host.sent[0]["message"]["type"] == "join_accepted", "host sends join acceptance")
	_assert(not scene.simulation.can_start_round(), "joined mobile hider must ready before round start")
	scene.simulation.set_player_ready(scene.peer_to_player[7], true)
	scene.simulation.start_round()
	scene.simulation.confirm_room_setup()
	_advance_for(scene.simulation, 20.4)
	scene._handle_join_request(8, {
		"type": "join_request",
		"version": 1,
		"room_id": "842913",
		"token": "hidefall",
		"player_name": "Late"
	})
	_assert(fake_host.sent[-2]["message"]["type"] == "join_accepted" and fake_host.sent[-2]["message"]["spectator"], "host accepts default late join as spectator")
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
	scene._on_message_received({
		"type": "join_accepted",
		"version": 1,
		"player_id": "p1",
		"room_id": "842913",
		"spectator": false,
		"shapes": ["cube", "sphere"],
		"colors": ["red", "blue"]
	})
	scene._on_ready_pressed()
	_assert(scene.player_ready, "mobile ready button toggles ready")
	scene.player_id = "p1"
	scene._request_next_color()
	scene._request_next_shape()
	var input: Dictionary = scene.build_hider_input()
	_assert(NetworkMessageValidatorScript.validate_client_message(input).is_empty(), "mobile scene builds valid hider input")
	_assert(input["request_color"] == "blue", "mobile color button queues color request")
	_assert(input["request_shape"] == "sphere", "mobile shape button queues shape request")
	scene.apply_snapshot({
		"type": "state_snapshot",
		"version": 1,
		"server_tick": 1,
		"phase": "seek",
		"time_remaining": 80.0,
		"shots_remaining": 4,
		"danger": "watched",
		"cooldowns": {"shape": 3.0, "color": 1.0},
		"hider_state": {"player_id": "p1", "object_id": "obj_001", "alive": true, "shape": "sphere", "color": "blue", "position": [0.0, 0.15, 0.0]},
		"objects": [{"object_id": "obj_001", "shape": "sphere", "color": "blue", "position": [0.0, 0.15, 0.0], "velocity": [0.0, 0.0, 0.0], "is_hider": true, "alive": true}]
	})
	_assert(scene.current_phase == "seek" and scene.danger == "watched", "mobile scene applies state snapshots")
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
