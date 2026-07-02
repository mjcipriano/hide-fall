extends Node3D

const GameConfigScript := preload("res://scripts/shared/config/game_config.gd")
const ContentDatabaseScript := preload("res://scripts/shared/content/content_database.gd")
const HidefallSimulationScript := preload("res://scripts/shared/game_state/hidefall_simulation.gd")
const NetworkMessageValidatorScript := preload("res://scripts/shared/networking/network_message_validator.gd")
const QrCodeScript := preload("res://scripts/shared/qr/qr_code.gd")
const WebSocketLanHostScript := preload("res://scripts/shared/networking/websocket_lan_host.gd")
const LanGameAnnouncerScript := preload("res://scripts/shared/networking/lan_game_announcer.gd")
const PropFactoryScript := preload("res://scripts/shared/props/prop_factory.gd")
const XrSettingsMenuScript := preload("res://scripts/quest/seeker/xr_settings_menu.gd")

const SETTINGS_PATH := "user://hidefall_settings.json"

var simulation
var content
var config
var network_host
var announcer
var object_nodes: Dictionary = {}
var object_looks: Dictionary = {}
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
var menu_toggle_was_pressed := false
var settings_menu_pointer_hovered := false
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
var ping_streams: Dictionary = {}

var camera: Camera3D
var xr_origin: XROrigin3D
var left_controller: XRController3D
var right_controller: XRController3D
var hud_label: Label
var help_label: Label
var qr_label: Label
var qr_texture_rect: TextureRect
var crosshair: ColorRect
var xr_crosshair: MeshInstance3D
var xr_hand_menu_root: Node3D
var xr_hand_menu_label: Label3D
var settings_menu
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
	if DisplayServer.get_name() != "headless":
		config.apply_overrides(SETTINGS_PATH)
	simulation = HidefallSimulationScript.new()
	simulation.setup(config, content, 20260628)
	host_ip = _detect_lan_ip()
	local_hider_id = simulation.add_hider("Local Phone", false)
	_reconcile_bot_hiders()
	_build_world()
	_build_hud()
	_setup_audio()
	if auto_start_network:
		_start_network_host()
	_log_visible_gameplay_state()


func _process(delta: float) -> void:
	_handle_input()
	_handle_xr_controller_buttons()
	_update_seeker_pose()
	_update_held_object(delta)
	_update_xr_pointer_dot()
	_update_settings_menu_pointer()
	simulation.advance(delta)
	_process_simulation_events()
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
	if announcer != null:
		announcer.stop()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_menu"):
		_toggle_settings_menu()
		get_viewport().set_input_as_handled()
		return
	if _is_settings_menu_open():
		if event.is_action_pressed("shoot") or event.is_action_pressed("scan_pulse"):
			if settings_menu != null:
				settings_menu.activate_hovered()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("pickup") or event.is_action_released("pickup"):
			get_viewport().set_input_as_handled()
			return
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
	start_hint.text = "Open the wrist menu to configure and start a round."
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
	help_label.text = "M: settings menu  |  R: start/confirm/rematch  |  Click: shoot  |  Hold E: grab/drop  |  Q: scan  |  WASD local hider"
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
	else:
		_build_settings_menu()


# The seeker's view stays clear: no head-locked panels. Everything lives on the
# left wrist (compact status or the settings menu); only the aim dot floats.
func _build_xr_hud() -> void:
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
	_build_settings_menu()


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
	wrist_mesh.size = Vector2(0.40, 0.155)
	wrist_panel.mesh = wrist_mesh
	wrist_panel.material_override = _hud_panel_material(Color(0.01, 0.03, 0.05, 0.86))
	xr_hand_menu_root.add_child(wrist_panel)

	xr_hand_menu_label = Label3D.new()
	xr_hand_menu_label.name = "WristText"
	xr_hand_menu_label.font_size = 12
	xr_hand_menu_label.outline_size = 3
	xr_hand_menu_label.pixel_size = 0.00080
	xr_hand_menu_label.width = 470.0
	xr_hand_menu_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	xr_hand_menu_label.position = Vector3(-0.185, 0.062, 0.004)
	xr_hand_menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	xr_hand_menu_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	xr_hand_menu_label.modulate = Color(0.9, 1.0, 1.0, 1.0)
	xr_hand_menu_root.add_child(xr_hand_menu_label)


func _build_settings_menu() -> void:
	if settings_menu != null:
		return
	settings_menu = XrSettingsMenuScript.new()
	settings_menu.name = "XRSettingsMenu"
	settings_menu.setup(config)
	settings_menu.action_requested.connect(_on_settings_action_requested)
	settings_menu.setting_changed.connect(_on_setting_changed)
	if _is_xr_active() and left_controller != null:
		settings_menu.position = Vector3(0.10, 0.20, -0.19)
		settings_menu.rotation_degrees = Vector3(-58.0, 10.0, 0.0)
		left_controller.add_child(settings_menu)
	elif camera != null:
		settings_menu.position = Vector3(0.0, -0.04, -1.25)
		camera.add_child(settings_menu)
	else:
		add_child(settings_menu)


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
	object_looks.clear()
	for object_id in simulation.objects:
		_create_object_node(object_id)
	_update_objects()


func _create_object_node(object_id: String) -> void:
	var obj: Dictionary = simulation.objects[object_id]
	var node: Node3D = PropFactoryScript.make_prop(obj["shape"])
	node.name = object_id
	node.set_meta("shape", String(obj["shape"]))
	object_root.add_child(node)
	object_nodes[object_id] = node
	_apply_object_look(object_id, obj)


# Rebuilds/retints a prop's visual only when its disguise actually changed.
func _apply_object_look(object_id: String, obj: Dictionary) -> void:
	var look := "%s|%s|%s|%s" % [obj["shape"], obj["color"], obj.get("pattern", "solid"), str(obj.get("damaged", false))]
	if object_looks.get(object_id, "") == look:
		return
	object_looks[object_id] = look
	var node: Node3D = object_nodes[object_id]
	var previous_shape: String = String(node.get_meta("shape", ""))
	if previous_shape != String(obj["shape"]):
		var replacement: Node3D = PropFactoryScript.make_prop(obj["shape"])
		replacement.name = object_id
		replacement.transform = node.transform
		object_root.remove_child(node)
		node.queue_free()
		object_root.add_child(replacement)
		object_nodes[object_id] = replacement
		node = replacement
	node.set_meta("shape", String(obj["shape"]))
	var color := Color(content.get_color_hex(obj["color"]))
	if obj.get("damaged", false):
		color = color.darkened(0.45)
	PropFactoryScript.apply_material(node, PropFactoryScript.make_material(color, obj.get("pattern", "solid")))


func _update_objects() -> void:
	for object_id in simulation.objects:
		if not object_nodes.has(object_id):
			continue
		# The held prop's transform is driven by the hand in _update_held_object.
		if object_id == held_object_id:
			continue
		var obj: Dictionary = simulation.objects[object_id]
		_apply_object_look(object_id, obj)
		var node: Node3D = object_nodes[object_id]
		node.position = obj["position"]
		node.quaternion = obj.get("orientation", Quaternion(Vector3.UP, float(obj.get("rotation_y", 0.0))))
		node.visible = obj.get("alive", true) or not obj.get("is_hider", false)


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
	if settings_menu != null:
		settings_menu.refresh_values()
	_update_hand_menu()


# The wrist panel is the seeker's only status readout now that the head-locked
# HUD is gone. Lines stay short so the text never spills out of the small quad.
func _update_hand_menu() -> void:
	if xr_hand_menu_root == null or xr_hand_menu_label == null:
		return
	xr_hand_menu_root.visible = left_controller != null and left_controller.get_is_active() and not _is_settings_menu_open()
	var gun_text := "ready"
	if simulation.shots_remaining <= 0:
		gun_text = "EMPTY"
	elif simulation.shot_cooldown_remaining > 0.0:
		gun_text = "wait %.1f" % simulation.shot_cooldown_remaining
	xr_hand_menu_label.text = "%s\nTime %.0f  Shots %d (%s)\nScans %d  Props %d  Live %d\nPhones join over Wi-Fi\nRoom %s  %s" % [
		_phase_short_text(),
		float(simulation.get_state_snapshot(local_hider_id)["time_remaining"]),
		simulation.shots_remaining,
		gun_text,
		simulation.scan_pulses_remaining,
		simulation.objects.size(),
		_live_hider_count(),
		simulation.room_id,
		host_ip
	]


# Compact phase line for the small wrist panel.
func _phase_short_text() -> String:
	match simulation.phase:
		HidefallSimulationScript.PHASE_LOBBY:
			return "LOBBY - Y menu to start"
		HidefallSimulationScript.PHASE_ROOM_SETUP:
			return "SETUP - A to confirm"
		HidefallSimulationScript.PHASE_OBJECT_RAIN:
			return "PROPS FALLING"
		HidefallSimulationScript.PHASE_SEEK:
			return "HUNT - misses cost ammo"
		HidefallSimulationScript.PHASE_RESULTS:
			return "ROUND OVER - A replays"
	return "HIDEFALL"


func get_join_payload_text() -> String:
	return JSON.stringify(simulation.get_join_payload(host_ip, int(config.get_value("network", "port", 29444))))


func _update_join_qr(join_payload: String) -> void:
	if join_payload == current_join_payload:
		return
	current_join_payload = join_payload
	var texture := QrCodeScript.make_texture(join_payload, 5)
	if qr_texture_rect != null:
		qr_texture_rect.texture = texture


func _shoot_at_cursor() -> void:
	if _is_settings_menu_open():
		return
	if not held_object_id.is_empty():
		return
	if simulation.phase != HidefallSimulationScript.PHASE_SEEK:
		return
	var gate: Dictionary = simulation.can_fire()
	if not gate.get("accepted", false):
		# Out of ammo or the gun is still cooling down: dry click, no beam.
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
	else:
		# A wild shot into the room still heats the gun, so hiders get their
		# escape window even when the seeker misses everything.
		simulation.begin_shot_cooldown()
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
		HidefallSimulationScript.PHASE_OBJECT_RAIN, HidefallSimulationScript.PHASE_SEEK:
			return true
	return false


func _begin_grab() -> void:
	if _is_settings_menu_open():
		return
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
	var node: Node3D = object_nodes.get(object_id)
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
	if _is_settings_menu_open():
		return
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
	var node: Node3D = object_nodes.get(held_object_id)
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


func _update_settings_menu_pointer() -> void:
	if settings_menu == null or not _is_settings_menu_open():
		settings_menu_pointer_hovered = false
		return
	var ray := _get_seeker_ray()
	settings_menu_pointer_hovered = settings_menu.update_pointer(ray["origin"], ray["direction"])


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
	var menu_pressed := left_controller != null and left_controller.get_is_active() and (
		_xr_button_pressed(left_controller, "by_button", "secondary") or left_controller.is_button_pressed("y_button")
	)
	if menu_pressed and not menu_toggle_was_pressed:
		_toggle_settings_menu()
	menu_toggle_was_pressed = menu_pressed
	if right_controller == null or not right_controller.get_is_active():
		return
	var trigger_pressed := _xr_button_pressed(right_controller, "trigger_click", "trigger")
	var grip_pressed := _xr_button_pressed(right_controller, "grip_click", "grip")
	var scan_pressed := _xr_button_pressed(right_controller, "ax_button", "primary")
	if _is_settings_menu_open():
		if (trigger_pressed and not trigger_was_pressed) or (scan_pressed and not scan_was_pressed):
			if settings_menu != null:
				settings_menu.activate_hovered()
		trigger_was_pressed = trigger_pressed
		grip_was_pressed = grip_pressed
		scan_was_pressed = scan_pressed
		return
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
			network_status = "open the wrist menu to start"
		HidefallSimulationScript.PHASE_ROOM_SETUP:
			simulation.confirm_room_setup()
		HidefallSimulationScript.PHASE_SEEK:
			_use_scan_pulse()
		HidefallSimulationScript.PHASE_RESULTS:
			simulation.start_round()
			_rebuild_objects()


func _restart_round_from_settings() -> void:
	if not held_object_id.is_empty():
		_end_grab()
	if simulation.start_round():
		simulation.confirm_room_setup()
		_rebuild_objects()
		network_status = "round restarted"
		last_scan_text = "settings restart"


func _end_round_from_settings() -> void:
	if not held_object_id.is_empty():
		_end_grab()
	if simulation.end_round():
		network_status = "round ended from menu"
	else:
		network_status = "no active round to end"
	_update_hud()


func _toggle_settings_menu() -> void:
	if settings_menu == null:
		_build_settings_menu()
	if settings_menu == null:
		return
	if not _is_xr_active() and camera != null and settings_menu.get_parent() == camera:
		settings_menu.position = Vector3(0.0, -0.04, -1.25)
	settings_menu.toggle()
	if settings_menu.visible:
		settings_menu.refresh_values()


func _is_settings_menu_open() -> bool:
	return settings_menu != null and settings_menu.visible


func _on_settings_action_requested(action: String) -> void:
	match action:
		"restart_round":
			_restart_round_from_settings()
		"end_round":
			_end_round_from_settings()


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if DisplayServer.get_name() != "headless":
		config.save_overrides(SETTINGS_PATH)
	if section == "hiders" and key == "bot_count":
		_reconcile_bot_hiders()
	elif section == "objects" and key == "decoy_count" and simulation.phase == HidefallSimulationScript.PHASE_LOBBY:
		simulation.objects.clear()
		_rebuild_objects()
	_refresh_announcer_info(int(config.get_value("network", "port", 29444)))
	_update_hud()


func _reconcile_bot_hiders() -> void:
	if simulation == null or config == null:
		return
	var desired: int = maxi(0, int(config.get_value("hiders", "bot_count", 2)))
	var bot_ids: Array[String] = []
	for player_id in simulation.players:
		if simulation.players[player_id].get("role", "") == "hider" and simulation.players[player_id].get("is_bot", false):
			bot_ids.append(player_id)
	while bot_ids.size() > desired:
		var bot_id: String = bot_ids.pop_back()
		simulation.remove_player(bot_id, true)
	while bot_ids.size() < desired:
		var added: Array[String] = simulation.add_bot_hiders(1)
		bot_ids.append(added[0])


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
	return false


func _is_xr_active() -> bool:
	return xr_origin != null and get_viewport().use_xr


func _phase_instruction_text() -> String:
	match simulation.phase:
		HidefallSimulationScript.PHASE_LOBBY:
			return "READY - open wrist menu (Y) to start"
		HidefallSimulationScript.PHASE_ROOM_SETUP:
			return "SETUP - press A to confirm your play space"
		HidefallSimulationScript.PHASE_OBJECT_RAIN:
			return "PROPS FALLING - hiders are dropping in too"
		HidefallSimulationScript.PHASE_SEEK:
			return "HUNT - find the live props, misses cost ammo"
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
	for key in ["shoot", "pickup", "drop", "hit", "miss", "empty", "respawn", "earthquake"]:
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


# Turns queued simulation happenings into audio: room-shaking earthquakes,
# per-player spatial taunt pings, and endless-mode respawn chimes.
func _process_simulation_events() -> void:
	for event in simulation.drain_events():
		match String(event.get("type", "")):
			"earthquake":
				_play_sfx("earthquake")
			"hider_respawn":
				_play_sfx("respawn")
			"hider_ping":
				_play_spatial_ping(event)


# The taunt plays from the hider's prop so the seeker can hunt by ear; each
# player gets their own unique jingle.
func _play_spatial_ping(event: Dictionary) -> void:
	var speaker := AudioStreamPlayer3D.new()
	speaker.name = "PingVoice"
	speaker.stream = _player_ping_stream(String(event.get("player_id", "")))
	speaker.unit_size = 3.0
	speaker.max_db = 0.0
	add_child(speaker)
	speaker.global_position = event.get("position", Vector3.ZERO)
	speaker.finished.connect(speaker.queue_free)
	speaker.play()


func _player_ping_stream(player_id: String) -> AudioStreamWAV:
	if ping_streams.has(player_id):
		return ping_streams[player_id]
	var stream := _make_player_ping(player_id)
	ping_streams[player_id] = stream
	return stream


# A distinct sub-second jingle per player: the player id seeds the waveform and
# a three-note pentatonic melody, so "who pinged" is learnable by ear.
func _make_player_ping(player_id: String) -> AudioStreamWAV:
	var seed_value := int(hash(player_id))
	var pentatonic := [0, 2, 4, 7, 9, 12]
	var notes: Array[float] = []
	for note_index in 3:
		var step: int = pentatonic[absi(seed_value >> (note_index * 4)) % pentatonic.size()]
		notes.append(392.0 * pow(2.0, (float(step) + float(absi(seed_value) % 5)) / 12.0))
	var waveform := absi(seed_value) % 3
	var mix_rate := 22050
	var note_seconds := 0.14
	var gap_seconds := 0.04
	var duration := notes.size() * (note_seconds + gap_seconds)
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / mix_rate
		var slot := int(t / (note_seconds + gap_seconds))
		var t_in_slot := t - slot * (note_seconds + gap_seconds)
		var sample := 0.0
		if slot < notes.size() and t_in_slot < note_seconds:
			var frequency: float = notes[slot]
			var note_progress := t_in_slot / note_seconds
			sample = _oscillate(waveform, frequency, t) + 0.25 * _oscillate(waveform, frequency * 2.0, t)
			sample *= sin(PI * note_progress)
		var value := int(clampf(sample * 0.55, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)
	return _wrap_wav(data, mix_rate)


func _oscillate(waveform: int, frequency: float, t: float) -> float:
	var cycle_phase := fmod(frequency * t, 1.0)
	match waveform:
		1:
			# triangle
			return 4.0 * absf(cycle_phase - 0.5) - 1.0
		2:
			# soft square
			return 0.7 if cycle_phase < 0.5 else -0.7
	return sin(TAU * cycle_phase)


# Procedurally synthesizes short 16-bit sound effects so the build needs no
# bundled audio assets. Layered oscillators + noise for a toy-arcade feel.
func _make_sfx(kind: String) -> AudioStreamWAV:
	var mix_rate := 22050
	var duration := 0.2
	match kind:
		"pickup":
			duration = 0.12
		"drop":
			duration = 0.16
		"shoot":
			duration = 0.24
		"hit":
			duration = 0.42
		"miss":
			duration = 0.32
		"empty":
			duration = 0.08
		"respawn":
			duration = 0.42
		"earthquake":
			duration = 1.3
	var sample_count := int(mix_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var rumble := 0.0
	for i in sample_count:
		var t := float(i) / mix_rate
		var progress := t / duration
		var sample := 0.0
		var envelope := 1.0
		match kind:
			"shoot":
				# Bright zap sweep over a sub-bass thump.
				var sweep := 1800.0 * pow(0.12, progress)
				sample = 0.8 * sin(TAU * sweep * t) + 0.35 * sin(TAU * sweep * 1.5 * t)
				sample += 0.5 * sin(TAU * 85.0 * t) * pow(1.0 - progress, 6.0)
				sample += 0.18 * (randf() * 2.0 - 1.0) * pow(1.0 - progress, 2.0)
				envelope = pow(1.0 - progress, 1.4)
			"pickup":
				# Two quick rising blips.
				var blip_frequency := 540.0 if progress < 0.5 else 810.0
				sample = sin(TAU * blip_frequency * t) + 0.3 * sin(TAU * blip_frequency * 2.0 * t)
				envelope = sin(PI * fmod(progress * 2.0, 1.0)) * 0.9
			"drop":
				# Soft thud with a felt-like noise tail.
				sample = sin(TAU * 110.0 * t) + 0.5 * sin(TAU * 66.0 * t)
				sample += 0.3 * (randf() * 2.0 - 1.0) * pow(1.0 - progress, 3.0)
				envelope = pow(1.0 - progress, 2.2)
			"hit":
				# Rising three-note victory arpeggio with sparkle.
				var arpeggio := [660.0, 880.0, 1320.0]
				var slot := mini(int(progress * 3.0), 2)
				var note_progress := fmod(progress * 3.0, 1.0)
				var frequency: float = arpeggio[slot]
				sample = sin(TAU * frequency * t) + 0.45 * sin(TAU * frequency * 2.0 * t) + 0.2 * sin(TAU * frequency * 3.0 * t)
				envelope = sin(PI * note_progress) * (0.7 + 0.3 * progress)
			"miss":
				# Sad descending womp-womp.
				var womp := (250.0 if progress < 0.5 else 180.0) * (1.0 - 0.25 * fmod(progress * 2.0, 1.0))
				sample = sin(TAU * womp * t) + 0.4 * sin(TAU * womp * 0.5 * t)
				envelope = sin(PI * fmod(progress * 2.0, 1.0)) * 0.9
			"empty":
				# dry double click for an out-of-ammo trigger pull
				sample = (1.0 if fmod(t * 900.0, 1.0) < 0.5 else -1.0) * 0.5
				envelope = pow(1.0 - progress, 4.0)
			"respawn":
				# Shimmering upward arpeggio: found, but back in a new body.
				var ladder := [392.0, 494.0, 587.0, 784.0]
				var slot := mini(int(progress * 4.0), 3)
				var note_progress := fmod(progress * 4.0, 1.0)
				var frequency: float = ladder[slot]
				sample = sin(TAU * frequency * t) + 0.35 * sin(TAU * frequency * 2.0 * t)
				sample += 0.15 * sin(TAU * frequency * 4.0 * t + sin(t * 30.0))
				envelope = sin(PI * note_progress)
			"earthquake":
				# Deep integrated-noise rumble with a slow wobble that builds
				# fast and trails off as the props crash back down.
				rumble = clampf(rumble * 0.996 + (randf() * 2.0 - 1.0) * 0.09, -1.0, 1.0)
				sample = rumble * 1.3 + 0.6 * sin(TAU * 42.0 * t + 2.0 * sin(TAU * 5.5 * t))
				sample *= 0.75 + 0.25 * sin(TAU * 6.0 * t)
				envelope = minf(progress * 6.0, 1.0) * pow(1.0 - progress, 0.9)
		var value := int(clampf(sample * envelope * 0.6, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)
	return _wrap_wav(data, mix_rate)


func _wrap_wav(data: PackedByteArray, mix_rate: int) -> AudioStreamWAV:
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
	_start_announcer(port)


# UDP beacon so phones list this game without typing anything.
func _start_announcer(port: int) -> void:
	announcer = LanGameAnnouncerScript.new()
	announcer.name = "LanGameAnnouncer"
	add_child(announcer)
	_refresh_announcer_info(port)
	var error: Error = announcer.start(
		int(config.get_value("network", "discovery_port", 29445)),
		float(config.get_value("network", "discovery_interval_seconds", 1.0))
	)
	print("Hidefall LAN announcer %s on udp/%d" % [
		"broadcasting" if error == OK else "failed (%d)" % error,
		int(config.get_value("network", "discovery_port", 29445))
	])


func _refresh_announcer_info(port: int) -> void:
	if announcer == null:
		return
	var host_name := "Hidefall Quest Room"
	if not OS.get_environment("USER").is_empty():
		host_name = "%s's Quest Room" % OS.get_environment("USER")
	announcer.set_info({
		"host_name": host_name,
		"host_ip": host_ip,
		"port": port,
		"room_id": simulation.room_id,
		"token": simulation.room_token,
		"phase": simulation.phase,
		"players": simulation.players.size(),
		"protocol_version": NetworkMessageValidatorScript.PROTOCOL_VERSION
	})


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
	var preferences := {
		"shape": String(message.get("preferred_shape", "") if message.get("preferred_shape", null) != null else ""),
		"color": String(message.get("preferred_color", "") if message.get("preferred_color", null) != null else ""),
		"pattern": String(message.get("preferred_pattern", "") if message.get("preferred_pattern", null) != null else "")
	}
	var late_join: bool = simulation.phase != HidefallSimulationScript.PHASE_LOBBY
	var late_spectator: bool = late_join and not bool(config.get_value("network", "allow_late_join", false))
	var player_id := ""
	if late_spectator:
		player_id = _take_over_available_body(player_name, preferences)
		if player_id.is_empty():
			player_id = simulation.add_spectator(player_name)
	else:
		player_id = simulation.add_hider(player_name, false)
		simulation.set_player_ready(player_id, false)
		simulation.set_player_preferences(player_id, preferences)
	late_spectator = simulation.players[player_id].get("role", "") == "spectator"
	peer_to_player[peer_id] = player_id
	network_host.send_to_peer(peer_id, {
		"type": "join_accepted",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"player_id": player_id,
		"room_id": simulation.room_id,
		"spectator": late_spectator,
		"settings": config.duplicate_data(),
		"shapes": content.get_shape_ids(),
		"colors": content.get_color_ids(),
		"patterns": content.get_pattern_ids()
	})
	network_host.send_to_peer(peer_id, simulation.get_state_snapshot(player_id))


func _take_over_available_body(player_name: String, preferences: Dictionary) -> String:
	for player_id in simulation.players:
		var player: Dictionary = simulation.players[player_id]
		if player.get("role", "") != "hider" or not player.get("is_bot", false):
			continue
		if not player.get("alive", false):
			continue
		var object_id: String = player.get("object_id", "")
		if object_id.is_empty() or not simulation.objects.has(object_id):
			continue
		player["name"] = player_name
		player["is_bot"] = false
		player["ready"] = true
		simulation.players[player_id] = player
		simulation.set_player_preferences(player_id, preferences)
		_apply_preferences_to_existing_hider(object_id, preferences)
		return player_id
	for object_id in simulation.objects:
		var obj: Dictionary = simulation.objects[object_id]
		if obj.get("is_hider", false) or not obj.get("alive", true):
			continue
		var player_id: String = simulation.add_hider(player_name, false)
		simulation.players[player_id]["ready"] = true
		simulation.players[player_id]["object_id"] = object_id
		simulation.set_player_preferences(player_id, preferences)
		obj["is_hider"] = true
		obj["owner_player_id"] = player_id
		obj["move_input"] = Vector2.ZERO
		obj["freeze"] = false
		obj["alive"] = true
		obj["shape_cooldown"] = 0.0
		obj["color_cooldown"] = 0.0
		obj["dash_cooldown"] = 0.0
		obj["dash_time"] = 0.0
		obj["mimic_cooldown"] = 0.0
		simulation.objects[object_id] = obj
		_apply_preferences_to_existing_hider(object_id, preferences)
		return player_id
	return ""


func _apply_preferences_to_existing_hider(object_id: String, preferences: Dictionary) -> void:
	var obj: Dictionary = simulation.objects[object_id]
	var shape := String(preferences.get("shape", ""))
	if content.get_shape_ids().has(shape):
		obj["shape"] = shape
		obj["rest_mode"] = content.get_shape_rest_mode(shape)
		obj["collision_radius"] = simulation._collision_radius_for_shape(shape)
		obj["half_height"] = simulation._half_height_for_shape(shape)
	var color := String(preferences.get("color", ""))
	if content.get_color_ids().has(color):
		obj["color"] = color
	var pattern := String(preferences.get("pattern", ""))
	if content.get_pattern_ids().has(pattern):
		obj["pattern"] = pattern
	simulation.objects[object_id] = obj


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
	_refresh_announcer_info(int(config.get_value("network", "port", 29444)))


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
