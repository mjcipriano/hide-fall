extends Node3D

const GameConfigScript := preload("res://scripts/shared/config/game_config.gd")
const ContentDatabaseScript := preload("res://scripts/shared/content/content_database.gd")
const HidefallSimulationScript := preload("res://scripts/shared/game_state/hidefall_simulation.gd")
const NetworkMessageValidatorScript := preload("res://scripts/shared/networking/network_message_validator.gd")
const QrCodeScript := preload("res://scripts/shared/qr/qr_code.gd")
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
var current_join_payload := ""
var xr_runtime_status := "desktop"
var held_object_id := ""
var trigger_was_pressed := false
var grip_was_pressed := false
var scan_was_pressed := false
var last_scan_text := "scan ready"
var launch_gameplay_logged := false
var held_prev_position := Vector3.ZERO
var held_velocity := Vector3.ZERO
var has_prev_held_pos := false
var held_offset_basis := Basis()
var held_offset_from := Vector3.ZERO
var held_offset_to := Vector3.ZERO
var held_offset_t := 1.0
var sfx_players: Dictionary = {}

var camera: Camera3D
var xr_origin: XROrigin3D
var left_controller: XRController3D
var right_controller: XRController3D
var hud_label: Label
var help_label: Label
var qr_label: Label
var qr_texture_rect: TextureRect
var crosshair: ColorRect
var xr_hud_root: Node3D
var xr_hud_label: Label3D
var xr_help_label: Label3D
var xr_qr_sprite: Sprite3D
var xr_crosshair: MeshInstance3D
var xr_phase_label: Label3D
var xr_blackout_panel: MeshInstance3D
var xr_hand_menu_root: Node3D
var xr_hand_menu_label: Label3D
var world_environment: WorldEnvironment
var arena_root: Node3D
var object_root: Node3D


func _ready() -> void:
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless" or OS.get_environment("HIDEFALL_DISABLE_NETWORK") == "1":
		auto_start_network = false
	_setup_xr_runtime()
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
	_setup_audio()
	if _should_auto_start_solo_round():
		_start_visible_solo_round()
	if auto_start_network:
		_start_network_host()
	_log_visible_gameplay_state()


func _process(delta: float) -> void:
	_handle_input()
	_handle_xr_controller_buttons()
	_update_seeker_pose()
	_update_held_object(delta)
	_update_xr_pointer_dot()
	simulation.advance(delta)
	if _is_xr_active() and not launch_gameplay_logged and simulation.objects.size() > 0:
		_log_visible_gameplay_state()
	_send_periodic_snapshots(delta)
	_update_objects()
	_update_hud()
	if Input.is_action_just_pressed("start_round"):
		_activate_primary_action()


func _exit_tree() -> void:
	if network_host != null:
		network_host.stop()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot"):
		_shoot_at_cursor()
	if event.is_action_pressed("pickup"):
		_begin_grab()
	if event.is_action_released("pickup"):
		_end_grab()
	if event.is_action_pressed("scan_pulse"):
		_use_scan_pulse()


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
	floor_material.albedo_color = Color(0.10, 0.12, 0.16, 0.18 if _is_xr_active() else 1.0)
	floor_material.roughness = 1.0
	if _is_xr_active():
		floor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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

	var title := Label3D.new()
	title.name = "ArenaTitle"
	title.text = "HIDEFALL"
	title.font_size = 72
	title.outline_size = 12
	title.pixel_size = 0.0032
	title.modulate = Color(0.3, 0.95, 1.0, 1.0)
	title.position = Vector3(0.0, 1.35, -2.15)
	arena_root.add_child(title)

	var start_hint := Label3D.new()
	start_hint.name = "ArenaHint"
	start_hint.text = "A starts the hunt. Trigger shoots. Grip picks up props."
	start_hint.font_size = 32
	start_hint.outline_size = 8
	start_hint.pixel_size = 0.0024
	start_hint.modulate = Color(1.0, 1.0, 1.0, 1.0)
	start_hint.position = Vector3(0.0, 0.95, -2.15)
	arena_root.add_child(start_hint)

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

	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = Environment.new()
	add_child(world_environment)
	_configure_xr_passthrough()

	if camera == null:
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

	qr_label = Label.new()
	qr_label.position = Vector2(812, 18)
	qr_label.size = Vector2(260, 28)
	qr_label.add_theme_font_size_override("font_size", 16)
	qr_label.text = "Scan to join"
	canvas.add_child(qr_label)

	qr_texture_rect = TextureRect.new()
	qr_texture_rect.name = "JoinQr"
	qr_texture_rect.position = Vector2(812, 48)
	qr_texture_rect.size = Vector2(228, 228)
	qr_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	canvas.add_child(qr_texture_rect)

	help_label = Label.new()
	help_label.position = Vector2(20, 580)
	help_label.size = Vector2(900, 110)
	help_label.add_theme_font_size_override("font_size", 16)
	help_label.text = "R: start/confirm/rematch  |  Click/trigger: shoot  |  Hold E/grip: grab & turn, release to drop  |  Q/A: scan pulse  |  WASD local hider"
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

	if _is_xr_active():
		canvas.visible = false
		_build_xr_hud()


func _build_xr_hud() -> void:
	xr_hud_root = Node3D.new()
	xr_hud_root.name = "XRWorldHud"
	# Low-centered so it reads like a HUD and stays out of the play space.
	xr_hud_root.position = Vector3(0.0, -0.46, -1.9)
	if camera != null:
		camera.add_child(xr_hud_root)
	else:
		add_child(xr_hud_root)

	var status_panel := MeshInstance3D.new()
	status_panel.name = "StatusPanel"
	var status_panel_mesh := QuadMesh.new()
	status_panel_mesh.size = Vector2(1.5, 0.66)
	status_panel.mesh = status_panel_mesh
	status_panel.position = Vector3(0.0, 0.0, 0.0)
	status_panel.material_override = _hud_panel_material(Color(0.02, 0.03, 0.04, 0.72))
	xr_hud_root.add_child(status_panel)

	xr_phase_label = Label3D.new()
	xr_phase_label.name = "PhaseText"
	xr_phase_label.font_size = 30
	xr_phase_label.outline_size = 8
	xr_phase_label.pixel_size = 0.0019
	xr_phase_label.width = 1500.0
	xr_phase_label.position = Vector3(-0.68, 0.24, 0.01)
	xr_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	xr_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	xr_phase_label.modulate = Color(1.0, 0.92, 0.35, 1.0)
	xr_hud_root.add_child(xr_phase_label)

	xr_hud_label = Label3D.new()
	xr_hud_label.name = "StatusText"
	xr_hud_label.font_size = 22
	xr_hud_label.outline_size = 6
	xr_hud_label.modulate = Color(0.92, 0.98, 1.0, 1.0)
	xr_hud_label.pixel_size = 0.0019
	xr_hud_label.width = 1500.0
	xr_hud_label.position = Vector3(-0.68, 0.0, 0.01)
	xr_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	xr_hud_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	xr_hud_root.add_child(xr_hud_label)

	xr_help_label = Label3D.new()
	xr_help_label.name = "HelpText"
	xr_help_label.font_size = 19
	xr_help_label.outline_size = 6
	xr_help_label.modulate = Color(0.80, 0.88, 1.0, 1.0)
	xr_help_label.pixel_size = 0.0019
	xr_help_label.width = 1500.0
	xr_help_label.position = Vector3(-0.68, -0.23, 0.01)
	xr_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	xr_help_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	xr_help_label.text = "Trigger shoot   Hold grip grab & turn   Release drop   A start / scan"
	xr_hud_root.add_child(xr_help_label)

	var qr_label := Label3D.new()
	qr_label.name = "JoinQrLabel"
	qr_label.font_size = 18
	qr_label.outline_size = 5
	qr_label.pixel_size = 0.0018
	qr_label.position = Vector3(1.06, 0.24, 0.0)
	qr_label.modulate = Color(0.85, 0.95, 1.0, 1.0)
	qr_label.text = "Scan to join"
	xr_hud_root.add_child(qr_label)

	xr_qr_sprite = Sprite3D.new()
	xr_qr_sprite.name = "JoinQr"
	xr_qr_sprite.pixel_size = 0.0016
	xr_qr_sprite.position = Vector3(1.06, 0.0, 0.0)
	xr_hud_root.add_child(xr_qr_sprite)

	xr_blackout_panel = MeshInstance3D.new()
	xr_blackout_panel.name = "BlackoutPanel"
	var blackout_mesh := QuadMesh.new()
	blackout_mesh.size = Vector2(4.0, 2.6)
	xr_blackout_panel.mesh = blackout_mesh
	xr_blackout_panel.position = Vector3(0.0, 0.46, -0.35)
	xr_blackout_panel.visible = false
	xr_blackout_panel.material_override = _hud_panel_material(Color(0.0, 0.0, 0.0, 0.72))
	xr_hud_root.add_child(xr_blackout_panel)

	xr_crosshair = MeshInstance3D.new()
	xr_crosshair.name = "PointerDot"
	var crosshair_mesh := SphereMesh.new()
	crosshair_mesh.radius = 0.012
	crosshair_mesh.height = 0.024
	xr_crosshair.mesh = crosshair_mesh
	var crosshair_material := StandardMaterial3D.new()
	crosshair_material.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	crosshair_material.emission_enabled = true
	crosshair_material.emission = Color(1.0, 1.0, 1.0)
	xr_crosshair.material_override = crosshair_material
	add_child(xr_crosshair)
	_build_hand_menu()


func _build_hand_menu() -> void:
	if left_controller == null:
		return
	xr_hand_menu_root = Node3D.new()
	xr_hand_menu_root.name = "LeftHandMenu"
	xr_hand_menu_root.position = Vector3(0.06, 0.10, -0.12)
	xr_hand_menu_root.rotation_degrees = Vector3(-62.0, 8.0, 0.0)
	left_controller.add_child(xr_hand_menu_root)

	var wrist_panel := MeshInstance3D.new()
	wrist_panel.name = "WristPanel"
	var wrist_mesh := QuadMesh.new()
	wrist_mesh.size = Vector2(0.64, 0.36)
	wrist_panel.mesh = wrist_mesh
	wrist_panel.material_override = _hud_panel_material(Color(0.01, 0.03, 0.05, 0.86))
	xr_hand_menu_root.add_child(wrist_panel)

	xr_hand_menu_label = Label3D.new()
	xr_hand_menu_label.name = "WristText"
	xr_hand_menu_label.font_size = 22
	xr_hand_menu_label.outline_size = 5
	xr_hand_menu_label.pixel_size = 0.0016
	xr_hand_menu_label.width = 360.0
	xr_hand_menu_label.position = Vector3(-0.29, 0.13, 0.004)
	xr_hand_menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	xr_hand_menu_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	xr_hand_menu_label.modulate = Color(0.9, 1.0, 1.0, 1.0)
	xr_hand_menu_root.add_child(xr_hand_menu_label)


func _hud_panel_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material


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
		# The held prop's transform is driven by the hand in _update_held_object.
		if object_id == held_object_id:
			continue
		var obj: Dictionary = simulation.objects[object_id]
		var node: MeshInstance3D = object_nodes[object_id]
		node.position = obj["position"]
		node.quaternion = obj.get("orientation", Quaternion(Vector3.UP, float(obj.get("rotation_y", 0.0))))
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
	var join_payload := get_join_payload_text()
	_update_join_qr(join_payload)
	var status_text := "Hidefall Host Prototype\nPhase: %s  Time: %.1f  Shots: %d  Scans: %d  Live hiders: %d\nRoom: %s  Token: %s  Host: ws://%s:%d  Network: %s  XR: %s\nPlayers: %d  Local hider: %s  Objects: %d  Held: %s  Scan: %s\nScan QR or enter payload: %s\n%s" % [
		snapshot["phase"],
		float(snapshot["time_remaining"]),
		int(snapshot["shots_remaining"]),
		int(snapshot.get("scan_pulses_remaining", 0)),
		_live_hider_count(),
		simulation.room_id,
		simulation.room_token,
		host_ip,
		int(config.get_value("network", "port", 29444)),
		network_status,
		xr_runtime_status,
		simulation.players.size(),
		local_status,
		simulation.objects.size(),
		held_object_id if not held_object_id.is_empty() else "none",
		last_scan_text,
		join_payload,
		_results_text(results)
	]
	if hud_label != null:
		hud_label.text = status_text
	if xr_hud_label != null:
		xr_hud_label.text = "Time %.0fs   Shots %d   Scans %d   Live props %d   In room %d" % [
			float(snapshot["time_remaining"]),
			int(snapshot["shots_remaining"]),
			int(snapshot.get("scan_pulses_remaining", 0)),
			_live_hider_count(),
			simulation.objects.size()
		]
	if xr_phase_label != null:
		xr_phase_label.text = _phase_instruction_text()
	if xr_blackout_panel != null:
		xr_blackout_panel.visible = simulation.phase == HidefallSimulationScript.PHASE_BLACKOUT
	_update_hand_menu()


func _update_hand_menu() -> void:
	if xr_hand_menu_root == null or xr_hand_menu_label == null:
		return
	xr_hand_menu_root.visible = left_controller != null and left_controller.get_is_active()
	xr_hand_menu_label.text = "%s\nTime %.0f  Shots %d\nScans %d  Props %d\nRoom %s" % [
		_phase_instruction_text(),
		float(simulation.get_state_snapshot(local_hider_id)["time_remaining"]),
		simulation.shots_remaining,
		simulation.scan_pulses_remaining,
		simulation.objects.size(),
		simulation.room_id
	]


func get_join_payload_text() -> String:
	return JSON.stringify(simulation.get_join_payload(host_ip, int(config.get_value("network", "port", 29444))))


func _update_join_qr(join_payload: String) -> void:
	if join_payload == current_join_payload:
		return
	current_join_payload = join_payload
	var texture := QrCodeScript.make_texture(join_payload, 5)
	if qr_texture_rect != null:
		qr_texture_rect.texture = texture
	if xr_qr_sprite != null:
		xr_qr_sprite.texture = texture


func _shoot_at_cursor() -> void:
	if not held_object_id.is_empty():
		return
	if simulation.phase != HidefallSimulationScript.PHASE_SEEK:
		return
	if simulation.shots_remaining <= 0:
		_play_sfx("empty")
		_flash_crosshair(Color(0.6, 0.6, 0.6, 1.0))
		return
	var ray := _get_seeker_ray()
	var object_id := _pick_object_from_seeker_ray()
	var endpoint: Vector3 = ray["origin"] + ray["direction"] * 6.0
	var beam_color := Color(1.0, 0.35, 0.2)
	_play_sfx("shoot")
	if not object_id.is_empty():
		endpoint = simulation.objects[object_id]["position"]
		var result = simulation.shoot_object(object_id)
		if result.get("accepted", false):
			if result.get("hit", false):
				beam_color = Color(0.3, 1.0, 0.45)
				_flash_crosshair(Color(0.2, 1.0, 0.4, 1.0))
				_play_sfx("hit")
			else:
				beam_color = Color(1.0, 0.85, 0.25)
				_flash_crosshair(Color(1.0, 0.25, 0.2, 1.0))
				_play_sfx("miss")
	_spawn_laser(ray["origin"], endpoint, beam_color)


func _pick_object_from_seeker_ray(max_distance: float = 8.0, radius: float = 0.22) -> String:
	var ray := _get_seeker_ray()
	var origin: Vector3 = ray["origin"]
	var direction: Vector3 = ray["direction"]
	var best_id := ""
	var best_score := max_distance
	for object_id in simulation.objects:
		var obj: Dictionary = simulation.objects[object_id]
		if not obj.get("alive", true):
			continue
		var to_object: Vector3 = obj["position"] - origin
		var along_ray := to_object.dot(direction)
		if along_ray < 0.0 or along_ray > max_distance:
			continue
		var closest_point := origin + direction * along_ray
		var ray_distance := closest_point.distance_to(obj["position"])
		if ray_distance <= radius and along_ray < best_score:
			best_score = along_ray
			best_id = object_id
	return best_id


func _grab_source() -> Node3D:
	if right_controller != null and right_controller.get_is_active():
		return right_controller
	return camera


func _can_grab_phase() -> bool:
	match simulation.phase:
		HidefallSimulationScript.PHASE_OBJECT_RAIN, HidefallSimulationScript.PHASE_BLACKOUT, HidefallSimulationScript.PHASE_SEEK:
			return true
	return false


func _begin_grab() -> void:
	if not held_object_id.is_empty():
		return
	if not _can_grab_phase():
		_flash_crosshair(Color(0.65, 0.65, 0.65, 1.0))
		return
	var object_id := _pick_object_from_seeker_ray(2.6, 0.35)
	if object_id.is_empty():
		return
	if not simulation.set_object_held(object_id, true):
		return
	held_object_id = object_id
	has_prev_held_pos = false
	held_velocity = Vector3.ZERO
	# Preserve where on the prop the hand grabbed it (edge grab) plus its
	# orientation, so it holds and turns naturally instead of snapping to center.
	var source := _grab_source()
	var node: MeshInstance3D = object_nodes.get(object_id)
	var raw := Transform3D(Basis(), Vector3(0.0, 0.0, -0.25))
	if source != null and node != null:
		raw = source.global_transform.affine_inverse() * node.global_transform
	held_offset_basis = raw.basis
	held_offset_from = raw.origin
	# Distant grabs travel in to a comfortable hold distance; close grabs stay put.
	var hold_distance := minf(raw.origin.length(), 0.28)
	if raw.origin.length() > 0.001:
		held_offset_to = raw.origin.normalized() * hold_distance
	else:
		held_offset_to = Vector3(0.0, 0.0, -hold_distance)
	held_offset_t = 0.0
	_play_sfx("pickup")


func _end_grab() -> void:
	if held_object_id.is_empty():
		return
	simulation.release_object(held_object_id, held_velocity)
	held_object_id = ""
	has_prev_held_pos = false
	_play_sfx("drop")


func _use_scan_pulse() -> void:
	var result: Dictionary = simulation.use_scan_pulse(camera.global_transform.origin)
	if not result.get("accepted", false):
		last_scan_text = String(result.get("reason", "unavailable"))
		_flash_crosshair(Color(0.65, 0.65, 0.65, 1.0))
		return
	var revealed: Array = result.get("revealed", [])
	last_scan_text = "%d suspicious prop%s nearby" % [revealed.size(), "" if revealed.size() == 1 else "s"]
	_flash_crosshair(Color(0.1, 0.8, 1.0, 1.0))


func _update_held_object(delta: float) -> void:
	if held_object_id.is_empty():
		return
	var source := _grab_source()
	var node: MeshInstance3D = object_nodes.get(held_object_id)
	if source == null or node == null:
		return
	# Reproduce the grab pose relative to the hand: preserves the edge offset and
	# lets the prop twist and turn with the controller, easing distant grabs in.
	held_offset_t = minf(1.0, held_offset_t + delta / 0.22)
	var eased := held_offset_t * held_offset_t * (3.0 - 2.0 * held_offset_t)
	var offset := Transform3D(held_offset_basis, held_offset_from.lerp(held_offset_to, eased))
	var target := source.global_transform * offset
	if not simulation.move_held_object(held_object_id, target.origin):
		held_object_id = ""
		has_prev_held_pos = false
		return
	var actual: Vector3 = simulation.objects[held_object_id]["position"]
	var orientation := target.basis.orthonormalized().get_rotation_quaternion()
	node.global_position = actual
	node.quaternion = orientation
	simulation.objects[held_object_id]["orientation"] = orientation
	if has_prev_held_pos and delta > 0.0:
		var instant_velocity: Vector3 = (actual - held_prev_position) / delta
		held_velocity = held_velocity.lerp(instant_velocity, 0.5)
	held_prev_position = actual
	has_prev_held_pos = true


func _update_xr_pointer_dot() -> void:
	if xr_crosshair == null or camera == null:
		return
	var ray := _get_seeker_ray()
	xr_crosshair.global_position = ray["origin"] + ray["direction"] * 1.4


func _get_seeker_ray() -> Dictionary:
	var source: Node3D = camera
	if right_controller != null and right_controller.get_is_active():
		source = right_controller
	return {
		"origin": source.global_transform.origin,
		"direction": (-source.global_transform.basis.z).normalized()
	}


func _setup_xr_runtime() -> void:
	if DisplayServer.get_name() == "headless":
		xr_runtime_status = "headless"
		return
	var openxr = XRServer.find_interface("OpenXR")
	if openxr == null:
		xr_runtime_status = "OpenXR unavailable"
		return
	if not openxr.is_initialized():
		var initialized: bool = openxr.initialize()
		if not initialized:
			xr_runtime_status = "OpenXR init failed"
			return
	get_viewport().use_xr = true
	xr_runtime_status = "OpenXR immersive"
	xr_origin = XROrigin3D.new()
	xr_origin.name = "XROrigin"
	add_child(xr_origin)
	camera = XRCamera3D.new()
	camera.name = "XRCamera"
	camera.current = true
	xr_origin.add_child(camera)
	left_controller = XRController3D.new()
	left_controller.name = "LeftController"
	left_controller.tracker = &"left_hand"
	xr_origin.add_child(left_controller)
	right_controller = XRController3D.new()
	right_controller.name = "RightController"
	right_controller.tracker = &"right_hand"
	xr_origin.add_child(right_controller)


func _configure_xr_passthrough() -> void:
	if not _is_xr_active() or world_environment == null:
		return
	var openxr = XRServer.find_interface("OpenXR")
	if openxr == null:
		return
	if not bool(ProjectSettings.get_setting("xr/openxr/extensions/meta/passthrough", false)):
		get_viewport().transparent_bg = false
		world_environment.environment.background_mode = Environment.BG_SKY
		openxr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		xr_runtime_status += " opaque"
		return
	var supported_modes: Array = openxr.get_supported_environment_blend_modes()
	if supported_modes.has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
		get_viewport().transparent_bg = true
		world_environment.environment.background_mode = Environment.BG_COLOR
		world_environment.environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
		openxr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		xr_runtime_status += " passthrough"
	else:
		get_viewport().transparent_bg = false
		world_environment.environment.background_mode = Environment.BG_SKY
		openxr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		xr_runtime_status += " opaque"


func _update_seeker_pose() -> void:
	if camera == null or simulation == null:
		return
	simulation.seeker_position = camera.global_transform.origin
	simulation.seeker_forward = (-camera.global_transform.basis.z).normalized()


func _handle_xr_controller_buttons() -> void:
	if right_controller == null or not right_controller.get_is_active():
		return
	var trigger_pressed := _xr_button_pressed(right_controller, "trigger_click", "trigger")
	var grip_pressed := _xr_button_pressed(right_controller, "grip_click", "grip")
	var scan_pressed := _xr_button_pressed(right_controller, "ax_button", "primary")
	if trigger_pressed and not trigger_was_pressed:
		_shoot_at_cursor()
	if grip_pressed and not grip_was_pressed:
		_begin_grab()
	if not grip_pressed and grip_was_pressed:
		_end_grab()
	if scan_pressed and not scan_was_pressed:
		_activate_primary_action()
	trigger_was_pressed = trigger_pressed
	grip_was_pressed = grip_pressed
	scan_was_pressed = scan_pressed


func _xr_button_pressed(controller: XRController3D, button_name: String, axis_name: String) -> bool:
	if controller.is_button_pressed(button_name):
		return true
	return controller.get_float(axis_name) > 0.75


func _activate_primary_action() -> void:
	match simulation.phase:
		HidefallSimulationScript.PHASE_LOBBY:
			if simulation.start_round():
				_rebuild_objects()
			else:
				network_status = "waiting for ready players"
		HidefallSimulationScript.PHASE_ROOM_SETUP:
			simulation.confirm_room_setup()
		HidefallSimulationScript.PHASE_SEEK:
			_use_scan_pulse()
		HidefallSimulationScript.PHASE_RESULTS:
			simulation.start_round()
			_rebuild_objects()


func _start_visible_solo_round() -> void:
	if simulation.phase != HidefallSimulationScript.PHASE_LOBBY:
		return
	if simulation.start_round():
		simulation.confirm_room_setup()
		_rebuild_objects()
		network_status = "solo bot round running"
		last_scan_text = "objects raining now"
		_log_visible_gameplay_state()


func _should_auto_start_solo_round() -> bool:
	if not _is_xr_active():
		return false
	if OS.get_environment("HIDEFALL_QUEST_STAY_IN_LOBBY") == "1":
		return false
	if OS.get_environment("HIDEFALL_DISABLE_SOLO_AUTOSTART") == "1":
		return false
	return true


func _is_xr_active() -> bool:
	return xr_origin != null and get_viewport().use_xr


func _phase_instruction_text() -> String:
	match simulation.phase:
		HidefallSimulationScript.PHASE_LOBBY:
			return "READY - press A to start the hunt"
		HidefallSimulationScript.PHASE_ROOM_SETUP:
			return "SETUP - press A to confirm your play space"
		HidefallSimulationScript.PHASE_OBJECT_RAIN:
			return "PROPS FALLING - grab and toss them while they land"
		HidefallSimulationScript.PHASE_BLACKOUT:
			return "BLACKOUT - stand still, hiders are hiding"
		HidefallSimulationScript.PHASE_SEEK:
			return "HUNT - shoot the live props before time runs out"
		HidefallSimulationScript.PHASE_RESULTS:
			return "ROUND OVER - press A to play again"
	return "HIDEFALL"


func _log_visible_gameplay_state() -> void:
	var object_count: int = 0
	if simulation != null:
		object_count = simulation.objects.size()
	var marker := "Hidefall visible gameplay ready" if object_count > 0 else "Hidefall visible world pending"
	print("%s: phase=%s objects=%d object_nodes=%d xr=%s network=%s" % [
		marker,
		simulation.phase if simulation != null else "none",
		object_count,
		object_nodes.size(),
		xr_runtime_status,
		network_status
	])
	if object_count > 0:
		launch_gameplay_logged = true


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


func _setup_audio() -> void:
	for key in ["shoot", "pickup", "drop", "hit", "miss", "empty"]:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx_" + key
		player.stream = _make_sfx(key)
		player.volume_db = -4.0
		add_child(player)
		sfx_players[key] = player


func _play_sfx(sfx_name: String) -> void:
	var player: AudioStreamPlayer = sfx_players.get(sfx_name)
	if player != null:
		player.play()


# Procedurally synthesizes short 16-bit sound effects so the build needs no
# bundled audio assets.
func _make_sfx(kind: String) -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 0.2
	match kind:
		"pickup":
			duration = 0.09
		"drop":
			duration = 0.14
		"shoot":
			duration = 0.22
		"hit":
			duration = 0.3
		"miss":
			duration = 0.22
		"empty":
			duration = 0.08
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / mix_rate
		var progress := t / duration
		var sample := 0.0
		var envelope := 1.0
		match kind:
			"shoot":
				var sweep := lerpf(1500.0, 320.0, progress)
				sample = sin(TAU * sweep * t) + 0.3 * (randf() * 2.0 - 1.0)
				envelope = pow(1.0 - progress, 1.5)
			"pickup":
				var rise := lerpf(520.0, 900.0, progress)
				sample = sin(TAU * rise * t)
				envelope = sin(PI * progress)
			"drop":
				sample = sin(TAU * 140.0 * t) + 0.4 * (randf() * 2.0 - 1.0)
				envelope = pow(1.0 - progress, 2.0)
			"hit":
				var chime := lerpf(660.0, 1180.0, progress)
				sample = sin(TAU * chime * t) + 0.4 * sin(TAU * chime * 2.0 * t)
				envelope = sin(PI * progress)
			"miss":
				sample = (1.0 if sin(TAU * 165.0 * t) >= 0.0 else -1.0) * 0.7
				envelope = pow(1.0 - progress, 1.2)
			"empty":
				# dry double click for an out-of-ammo trigger pull
				sample = (1.0 if fmod(t * 900.0, 1.0) < 0.5 else -1.0) * 0.5
				envelope = pow(1.0 - progress, 4.0)
		var value := int(clampf(sample * envelope * 0.6, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav


# Brief emissive tracer from the controller to the shot point.
func _spawn_laser(from: Vector3, to: Vector3, color: Color) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var beam := MeshInstance3D.new()
	beam.name = "ShotLaser"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.006
	mesh.bottom_radius = 0.006
	mesh.height = length
	mesh.radial_segments = 8
	beam.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 4.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.material_override = material
	add_child(beam)
	var axis_y := (to - from).normalized()
	var axis_x := axis_y.cross(Vector3.UP)
	if axis_x.length() < 0.001:
		axis_x = axis_y.cross(Vector3.RIGHT)
	axis_x = axis_x.normalized()
	var axis_z := axis_x.cross(axis_y).normalized()
	beam.global_transform = Transform3D(Basis(axis_x, axis_y, axis_z), (from + to) * 0.5)
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.18)
	tween.parallel().tween_property(material, "emission_energy_multiplier", 0.0, 0.18)
	tween.tween_callback(beam.queue_free)


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
	if peer_to_player.size() >= int(config.get_value("network", "max_hiders", 8)):
		network_host.send_to_peer(peer_id, _reject_message("room_full", "The room is full."))
		return
	var player_name := String(message.get("player_name", "Hider")).strip_edges()
	if player_name.is_empty():
		player_name = "Hider"
	var late_spectator: bool = simulation.phase != HidefallSimulationScript.PHASE_LOBBY and not bool(config.get_value("network", "allow_late_join", false))
	var player_id: String = simulation.add_spectator(player_name) if late_spectator else simulation.add_hider(player_name, false)
	if not late_spectator:
		simulation.set_player_ready(player_id, false)
	peer_to_player[peer_id] = player_id
	network_host.send_to_peer(peer_id, {
		"type": "join_accepted",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"player_id": player_id,
		"room_id": simulation.room_id,
		"spectator": late_spectator,
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
		"scan_pulses_remaining": simulation.scan_pulses_remaining,
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
