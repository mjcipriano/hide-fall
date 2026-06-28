extends Node3D

const GameConfigScript := preload("res://scripts/shared/config/game_config.gd")
const ContentDatabaseScript := preload("res://scripts/shared/content/content_database.gd")
const HidefallSimulationScript := preload("res://scripts/shared/game_state/hidefall_simulation.gd")
const NetworkMessageValidatorScript := preload("res://scripts/shared/networking/network_message_validator.gd")
const WebSocketLanHostScript := preload("res://scripts/shared/networking/websocket_lan_host.gd")

var simulation
var content
var config
var network_host
var object_nodes: Dictionary = {}
var object_materials: Dictionary = {}
var peer_to_player: Dictionary = {}
var local_hider_id := ""
var selected_color_index := 0
var selected_shape_index := 0
var host_ip := "127.0.0.1"
var snapshot_accumulator := 0.0
var network_status := "offline"
var auto_start_network := true

var camera: Camera3D
var hud_label: Label
var help_label: Label
var crosshair: ColorRect
var arena_root: Node3D
var object_root: Node3D


func _ready() -> void:
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless" or OS.get_environment("HIDEFALL_DISABLE_NETWORK") == "1":
		auto_start_network = false
	content = ContentDatabaseScript.new()
	content.load_default()
	config = GameConfigScript.new()
	config.load_default()
	simulation = HidefallSimulationScript.new()
	simulation.setup(config, content, 20260628)
	host_ip = _detect_lan_ip()
	local_hider_id = simulation.add_hider("Local Phone", false)
	simulation.add_bot_hiders(2)
	_build_world()
	_build_hud()
	if auto_start_network:
		_start_network_host()


func _process(delta: float) -> void:
	_handle_input()
	simulation.advance(delta)
	_send_periodic_snapshots(delta)
	_update_objects()
	_update_hud()
	if simulation.phase == HidefallSimulationScript.PHASE_LOBBY and Input.is_action_just_pressed("start_round"):
		simulation.start_round()
		_rebuild_objects()


func _exit_tree() -> void:
	if network_host != null:
		network_host.stop()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot"):
		_shoot_at_cursor()


func _build_world() -> void:
	arena_root = Node3D.new()
	arena_root.name = "Arena"
	add_child(arena_root)
	object_root = Node3D.new()
	object_root.name = "Objects"
	add_child(object_root)

	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	arena_root.add_child(floor_body)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.0, 7.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.10, 0.12, 0.16)
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	floor_body.add_child(floor_mesh)

	var boundary := MeshInstance3D.new()
	boundary.name = "Boundary"
	var torus := TorusMesh.new()
	torus.inner_radius = 2.95
	torus.outer_radius = 3.02
	torus.ring_segments = 96
	boundary.mesh = torus
	boundary.rotation_degrees.x = 90.0
	var boundary_material := StandardMaterial3D.new()
	boundary_material.albedo_color = Color(0.0, 0.78, 1.0, 0.65)
	boundary_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	boundary.material_override = boundary_material
	arena_root.add_child(boundary)

	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	light.light_energy = 2.2
	add_child(light)

	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(0.0, 3.5, 0.0)
	fill.light_energy = 1.0
	fill.omni_range = 8.0
	add_child(fill)

	camera = Camera3D.new()
	camera.name = "SeekerCamera"
	camera.position = Vector3(0.0, 3.4, 6.2)
	camera.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	hud_label = Label.new()
	hud_label.position = Vector2(20, 18)
	hud_label.size = Vector2(760, 160)
	hud_label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(hud_label)

	help_label = Label.new()
	help_label.position = Vector2(20, 580)
	help_label.size = Vector2(900, 110)
	help_label.add_theme_font_size_override("font_size", 16)
	help_label.text = "R: start/rematch  |  Mouse click: shoot nearest prop  |  WASD: local hider move  |  Space: freeze  |  C: color  |  V: shape"
	canvas.add_child(help_label)

	crosshair = ColorRect.new()
	crosshair.name = "Crosshair"
	crosshair.color = Color(1.0, 1.0, 1.0, 0.85)
	crosshair.size = Vector2(8, 8)
	crosshair.anchor_left = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -4
	crosshair.offset_top = -4
	crosshair.offset_right = 4
	crosshair.offset_bottom = 4
	canvas.add_child(crosshair)


func _handle_input() -> void:
	var move := Vector2.ZERO
	move.x = Input.get_action_strength("hider_move_right") - Input.get_action_strength("hider_move_left")
	move.y = Input.get_action_strength("hider_move_back") - Input.get_action_strength("hider_move_forward")
	var request_color: Variant = null
	var request_shape: Variant = null
	if Input.is_action_just_pressed("change_color"):
		var colors = content.get_color_ids()
		selected_color_index = (selected_color_index + 1) % max(1, colors.size())
		request_color = colors[selected_color_index]
	if Input.is_action_just_pressed("change_shape"):
		var shapes = content.get_shape_ids()
		selected_shape_index = (selected_shape_index + 1) % max(1, shapes.size())
		request_shape = shapes[selected_shape_index]
	simulation.apply_hider_input(local_hider_id, {
		"move": [move.x, move.y],
		"freeze": Input.is_action_pressed("freeze_hider"),
		"request_color": request_color,
		"request_shape": request_shape
	})


func _rebuild_objects() -> void:
	for child in object_root.get_children():
		child.queue_free()
	object_nodes.clear()
	object_materials.clear()
	for object_id in simulation.objects:
		var obj: Dictionary = simulation.objects[object_id]
		var node := MeshInstance3D.new()
		node.name = object_id
		node.mesh = _mesh_for_shape(obj["shape"])
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(content.get_color_hex(obj["color"]))
		material.roughness = 0.72
		material.metallic = 0.0
		node.material_override = material
		object_root.add_child(node)
		object_nodes[object_id] = node
		object_materials[object_id] = material
	_update_objects()


func _update_objects() -> void:
	for object_id in simulation.objects:
		if not object_nodes.has(object_id):
			continue
		var obj: Dictionary = simulation.objects[object_id]
		var node: MeshInstance3D = object_nodes[object_id]
		node.position = obj["position"]
		node.rotation.y = float(obj.get("rotation_y", 0.0))
		node.visible = obj.get("alive", true) or not obj.get("is_hider", false)
		var material: StandardMaterial3D = object_materials[object_id]
		material.albedo_color = Color(content.get_color_hex(obj["color"]))
		if obj.get("damaged", false):
			material.albedo_color = material.albedo_color.darkened(0.45)
		node.mesh = _mesh_for_shape(obj["shape"])


func _update_hud() -> void:
	var snapshot = simulation.get_state_snapshot(local_hider_id)
	var results = simulation.get_results() if simulation.phase == HidefallSimulationScript.PHASE_RESULTS else {}
	var local_object_id = simulation.players.get(local_hider_id, {}).get("object_id", "")
	var local_status := "spectating"
	if simulation.objects.has(local_object_id):
		var obj: Dictionary = simulation.objects[local_object_id]
		local_status = "alive" if obj.get("alive", false) else "found"
	var join_payload := JSON.stringify(simulation.get_join_payload(host_ip, int(config.get_value("network", "port", 29444))))
	hud_label.text = "Hidefall Host Prototype\nPhase: %s  Time: %.1f  Shots: %d  Live hiders: %d\nRoom: %s  Token: %s  Host: ws://%s:%d  Network: %s\nPlayers: %d  Local hider: %s  Objects: %d\nJoin payload: %s\n%s" % [
		snapshot["phase"],
		float(snapshot["time_remaining"]),
		int(snapshot["shots_remaining"]),
		_live_hider_count(),
		simulation.room_id,
		simulation.room_token,
		host_ip,
		int(config.get_value("network", "port", 29444)),
		network_status,
		simulation.players.size(),
		local_status,
		simulation.objects.size(),
		join_payload,
		_results_text(results)
	]


func _shoot_at_cursor() -> void:
	var object_id := _pick_object_near_screen_center()
	if object_id.is_empty():
		return
	var result = simulation.shoot_object(object_id)
	if result.get("accepted", false):
		if result.get("hit", false):
			_flash_crosshair(Color(0.2, 1.0, 0.4, 1.0))
		else:
			_flash_crosshair(Color(1.0, 0.25, 0.2, 1.0))


func _pick_object_near_screen_center() -> String:
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	var best_id := ""
	var best_score := 72.0
	for object_id in simulation.objects:
		var obj: Dictionary = simulation.objects[object_id]
		if not obj.get("alive", true):
			continue
		var screen_position := camera.unproject_position(obj["position"])
		var distance := screen_position.distance_to(center)
		if distance < best_score:
			best_score = distance
			best_id = object_id
	return best_id


func _mesh_for_shape(shape_id: String) -> Mesh:
	match shape_id:
		"sphere", "duck":
			var mesh := SphereMesh.new()
			mesh.radius = 0.16
			mesh.height = 0.32
			return mesh
		"cylinder", "can", "mug":
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.14
			mesh.bottom_radius = 0.14
			mesh.height = 0.32
			mesh.radial_segments = 24
			return mesh
		"cone":
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.02
			mesh.bottom_radius = 0.18
			mesh.height = 0.34
			mesh.radial_segments = 24
			return mesh
		"capsule":
			var mesh := CapsuleMesh.new()
			mesh.radius = 0.13
			mesh.height = 0.36
			return mesh
		"pyramid", "star":
			var mesh := PrismMesh.new()
			mesh.size = Vector3(0.34, 0.28, 0.34)
			return mesh
		"ring":
			var mesh := TorusMesh.new()
			mesh.inner_radius = 0.10
			mesh.outer_radius = 0.17
			mesh.ring_segments = 24
			return mesh
		_:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.28, 0.28, 0.28)
			return mesh


func _live_hider_count() -> int:
	var count := 0
	for object_id in simulation.objects:
		var obj: Dictionary = simulation.objects[object_id]
		if obj.get("is_hider", false) and obj.get("alive", false):
			count += 1
	return count


func _results_text(results: Dictionary) -> String:
	if results.is_empty():
		return "Find the live props before time runs out."
	return "Results: seeker score %d, hider scores %s. Press R for rematch." % [
		int(results.get("seeker_score", 0)),
		str(results.get("hiders", {}))
	]


func _flash_crosshair(color: Color) -> void:
	crosshair.color = color
	var tween := create_tween()
	tween.tween_property(crosshair, "color", Color(1.0, 1.0, 1.0, 0.85), 0.25)


func _start_network_host() -> void:
	network_host = WebSocketLanHostScript.new()
	network_host.name = "WebSocketLanHost"
	add_child(network_host)
	network_host.client_connected.connect(_on_network_client_connected)
	network_host.client_disconnected.connect(_on_network_client_disconnected)
	network_host.client_message.connect(_on_network_client_message)
	var port := int(config.get_value("network", "port", 29444))
	var error: Error = network_host.start(port)
	network_status = "listening" if error == OK else "error %d" % int(error)


func _on_network_client_connected(peer_id: int) -> void:
	network_status = "client connected"
	network_host.send_to_peer(peer_id, _build_lobby_snapshot())


func _on_network_client_disconnected(peer_id: int) -> void:
	if peer_to_player.has(peer_id):
		var player_id: String = peer_to_player[peer_id]
		simulation.remove_player(player_id, true)
		peer_to_player.erase(peer_id)
	network_status = "client disconnected"


func _on_network_client_message(peer_id: int, message: Dictionary) -> void:
	var errors := NetworkMessageValidatorScript.validate_client_message(message)
	if not errors.is_empty():
		network_host.send_to_peer(peer_id, _reject_message("invalid_message", ", ".join(errors)))
		return
	match message.get("type", ""):
		"join_request":
			_handle_join_request(peer_id, message)
		"ready_state":
			if peer_to_player.has(peer_id):
				simulation.set_player_ready(peer_to_player[peer_id], bool(message.get("ready", true)))
				network_host.send_to_peer(peer_id, _build_lobby_snapshot())
		"hider_input":
			if peer_to_player.has(peer_id):
				var player_id: String = peer_to_player[peer_id]
				if message.get("player_id", "") == player_id:
					simulation.apply_hider_input(player_id, message)
		"ping":
			network_host.send_to_peer(peer_id, {"type": "pong", "version": NetworkMessageValidatorScript.PROTOCOL_VERSION, "server_time": Time.get_ticks_msec() / 1000.0})


func _handle_join_request(peer_id: int, message: Dictionary) -> void:
	if message.get("room_id", "") != simulation.room_id or message.get("token", "") != simulation.room_token:
		network_host.send_to_peer(peer_id, _reject_message("room_mismatch", "Room ID or token did not match."))
		return
	if peer_to_player.has(peer_id):
		network_host.send_to_peer(peer_id, _reject_message("already_joined", "This peer is already joined."))
		return
	if simulation.phase != HidefallSimulationScript.PHASE_LOBBY and not bool(config.get_value("network", "allow_late_join", false)):
		network_host.send_to_peer(peer_id, _reject_message("round_in_progress", "Late join is disabled until the next lobby."))
		return
	if peer_to_player.size() >= int(config.get_value("network", "max_hiders", 8)):
		network_host.send_to_peer(peer_id, _reject_message("room_full", "The room is full."))
		return
	var player_name := String(message.get("player_name", "Hider")).strip_edges()
	if player_name.is_empty():
		player_name = "Hider"
	var player_id: String = simulation.add_hider(player_name, false)
	peer_to_player[peer_id] = player_id
	network_host.send_to_peer(peer_id, {
		"type": "join_accepted",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"player_id": player_id,
		"room_id": simulation.room_id,
		"settings": config.duplicate_data(),
		"shapes": content.get_shape_ids(),
		"colors": content.get_color_ids()
	})
	network_host.send_to_peer(peer_id, simulation.get_state_snapshot(player_id))


func _send_periodic_snapshots(delta: float) -> void:
	if network_host == null:
		return
	snapshot_accumulator += delta
	if snapshot_accumulator < 0.1:
		return
	snapshot_accumulator = 0.0
	for peer_id in peer_to_player:
		var player_id: String = peer_to_player[peer_id]
		network_host.send_to_peer(peer_id, simulation.get_state_snapshot(player_id))


func _build_lobby_snapshot() -> Dictionary:
	return {
		"type": "state_snapshot",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"server_tick": simulation.server_tick,
		"phase": simulation.phase,
		"time_remaining": 0.0,
		"shots_remaining": simulation.shots_remaining,
		"players": simulation.players.values(),
		"objects": [],
		"danger": "safe",
		"cooldowns": {}
	}


func _reject_message(reason: String, detail: String) -> Dictionary:
	return {
		"type": "join_rejected",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"reason": reason,
		"detail": detail
	}


func _detect_lan_ip() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172.16.") or address.begins_with("172.17.") or address.begins_with("172.18.") or address.begins_with("172.19.") or address.begins_with("172.2") or address.begins_with("172.3"):
			return address
	return "127.0.0.1"
