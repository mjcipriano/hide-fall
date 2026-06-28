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
	_test_qr_code_generation()
	_test_network_validation()
	_test_phase_transitions()
	_test_hider_input_and_cooldowns()
	_test_shooting_and_results()
	_test_timeout_results()
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
	_assert(content.get_shape_ids().size() >= 12, "MVP shape set loads")
	_assert(content.get_color_ids().size() >= 12, "MVP color set loads")


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
	sim.start_round()
	_assert(sim.phase == HidefallSimulationScript.PHASE_OBJECT_RAIN, "round starts in object rain")
	_advance_for(sim, 10.2)
	_assert(sim.phase == HidefallSimulationScript.PHASE_BLACKOUT, "object rain transitions to blackout")
	_advance_for(sim, 10.2)
	_assert(sim.phase == HidefallSimulationScript.PHASE_SEEK, "blackout transitions to seek")


func _test_hider_input_and_cooldowns() -> void:
	var sim = _new_sim(123)
	var player_id := sim.add_hider("Tester")
	sim.start_round()
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


func _test_shooting_and_results() -> void:
	var sim = _new_sim(321)
	var player_id := sim.add_hider("Target")
	sim.start_round()
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
	_advance_for(sim, 20.4)
	var decoy_id := sim.get_decoy_object_ids()[0]
	var wrong := sim.shoot_object(decoy_id)
	_assert(wrong.get("accepted", false) and not wrong.get("hit", true), "wrong shot damages decoy")
	_advance_for(sim, 91.0)
	_assert(sim.phase == HidefallSimulationScript.PHASE_RESULTS, "seek timeout ends round")
	var results := sim.get_results()
	_assert(results["hiders"].values()[0] >= 1000, "surviving hider receives survival score")


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
	_assert(scene.qr_texture_rect.texture != null, "host scene creates join QR texture")
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
	scene.simulation.start_round()
	_advance_for(scene.simulation, 20.4)
	scene._rebuild_objects()
	_assert(scene.object_nodes.size() >= 75, "host scene creates visible prop nodes")
	var ray: Dictionary = scene._get_seeker_ray()
	var pick_id: String = scene.simulation.get_decoy_object_ids()[0]
	scene.simulation.objects[pick_id]["position"] = ray["origin"] + ray["direction"] * 1.0
	_assert(scene._pick_object_from_seeker_ray() == pick_id, "host ray picks object")
	scene._toggle_pickup()
	_assert(scene.held_object_id == pick_id, "host pickup holds object")
	scene._update_held_object()
	_assert(scene.simulation.objects[pick_id]["held_by_seeker"], "host updates held object")
	scene._toggle_pickup()
	_assert(scene.held_object_id.is_empty(), "host pickup toggles drop")
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
		"shapes": ["cube", "sphere"],
		"colors": ["red", "blue"]
	})
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
