extends Control

# Phone hider client: a lobby where players pick their disguise and find games
# on the local network, then an in-round view of the same 3D room the Quest
# seeker plays in (no AR - the shared virtual space rendered from a follow cam).

const NetworkMessageValidatorScript := preload("res://scripts/shared/networking/network_message_validator.gd")
const WebSocketLanClientScript := preload("res://scripts/shared/networking/websocket_lan_client.gd")
const LanGameBrowserScript := preload("res://scripts/shared/networking/lan_game_browser.gd")
const ContentDatabaseScript := preload("res://scripts/shared/content/content_database.gd")
const GameConfigScript := preload("res://scripts/shared/config/game_config.gd")
const PropFactoryScript := preload("res://scripts/shared/props/prop_factory.gd")
const MinigamesScript := preload("res://scripts/shared/game_state/minigames.gd")

const ACCENT := Color(0.18, 0.78, 0.92)
const PANEL_BG := Color(0.07, 0.09, 0.13, 0.94)
const DANGER_COLORS := {
	"safe": Color(0.25, 0.78, 0.42),
	"suspicious": Color(0.95, 0.78, 0.20),
	"watched": Color(0.98, 0.55, 0.16),
	"critical": Color(0.94, 0.25, 0.22),
	"found": Color(0.55, 0.55, 0.58)
}

var player_id := ""
var player_name := "Hider"
var current_phase := "disconnected"
var danger := "safe"
var move_vector := Vector2.ZERO
var client
var browser
var content
var joined := false
var player_ready := false
var spectator := false
var connection_status := "offline"
var host_message := ""
var input_accumulator := 0.0
var latest_snapshot: Dictionary = {}
var visible_objects: Array = []
var cooldowns: Dictionary = {}
var hider_state: Dictionary = {}
var seeker_info: Dictionary = {}
var available_shapes: Array = []
var available_colors: Array = []
var available_patterns: Array = []
var selected_shape_index := 0
var selected_color_index := 0
var selected_pattern_index := 0
var pending_shape: Variant = null
var pending_color: Variant = null
var pending_ability: Variant = null
# Inspection minigame engine. The minigame RUNS LOCALLY on the phone (instant
# input via real Buttons), shows instructions during an intro, then reports the
# result to the host. See MINIGAMES.md.
var minigame_panel: Control
var mg_title_label: Label
var mg_instructions_label: Label
var mg_countdown_label: Label
var mg_button_a: Button
var mg_button_b: Button
var mg_bar_area: Control
var mg_prompt_label: Label
var mg_choice_buttons: Array[Button] = []
var mg_rng := RandomNumberGenerator.new()
var minigame_flash_label: Label
var minigame_flash_time := 0.0
var mg_running := false
var mg_awaiting_clear := false
var mg_id := ""
var mg_difficulty := 0
var mg_params: Dictionary = {}
var mg_phase := "intro"
var mg_time := 0.0
var mg_state: Dictionary = {}
var mg_holding := false
var mg_drag_x := 0.0
var mg_tap_pending := 0
var mg_result_sent := false
var practice_mode := false
var practice_index := 0
var practice_next_in := 0.0
var practice_exit_button: Button
var discovered_games: Array = []
var selected_game_index := -1
var cam_yaw := 0.6
var cam_drag_index := -1
var joystick_drag_index := -1
var joystick_center := Vector2.ZERO
var world_props: Dictionary = {}
var world_prop_looks: Dictionary = {}
var world_prop_targets: Dictionary = {}

# Menu widgets
var menu_panel: Control
var name_input: LineEdit
var shape_value_label: Label
var color_value_label: Label
var color_swatch: ColorRect
var pattern_value_label: Label
var games_list: ItemList
var join_button: Button
var manual_toggle: Button
var manual_row: Control
var host_input: LineEdit
var port_input: LineEdit
var room_input: LineEdit
var token_input: LineEdit
var menu_status_label: Label
var preview_viewport: SubViewport
var preview_prop: Node3D

# Game widgets
var game_panel: Control
var world_container: SubViewportContainer
var world_viewport: SubViewport
var world_root: Node3D
var world_camera: Camera3D
var props_root: Node3D
var seeker_avatar: Node3D
var own_marker: MeshInstance3D
var top_bar: PanelContainer
var phase_label: Label
var danger_badge: Label
var info_label: Label
var joystick_area: Control
var dash_button: Button
var mimic_button: Button
var quake_button: Button
var ping_button: Button
var last_body_object_id := ""
var color_button: Button
var shape_button: Button
var ready_button: Button
var leave_button: Button
var overlay_label: Label
var game_status_label: Label


func _ready() -> void:
	_configure_mobile_window()
	content = ContentDatabaseScript.new()
	content.load_default()
	available_shapes = content.get_shape_ids()
	available_colors = content.get_color_ids()
	available_patterns = content.get_pattern_ids()
	selected_color_index = randi() % max(1, available_colors.size())
	client = WebSocketLanClientScript.new()
	client.name = "WebSocketLanClient"
	add_child(client)
	client.connected.connect(_on_connected)
	client.disconnected.connect(_on_disconnected)
	client.connection_failed.connect(_on_connection_failed)
	client.message_received.connect(_on_message_received)
	_build_world()
	_build_menu()
	_build_game_ui()
	_show_menu()
	_start_discovery()
	_update_status()


func _process(delta: float) -> void:
	if joined and client.is_connected_to_host():
		input_accumulator += delta
		if input_accumulator >= 0.05:
			input_accumulator = 0.0
			client.send_message(build_hider_input())
	_animate_preview(delta)
	_animate_world(delta)
	if mg_running:
		_minigame_process(delta)
	elif practice_mode and practice_next_in > 0.0:
		practice_next_in -= delta
		if practice_next_in <= 0.0:
			_practice_next()
	if minigame_flash_time > 0.0:
		minigame_flash_time -= delta
		if minigame_flash_time <= 0.0 and minigame_flash_label != null:
			minigame_flash_label.visible = false


func _exit_tree() -> void:
	if browser != null:
		browser.stop()


# --- networking -------------------------------------------------------------


func _start_discovery() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("HIDEFALL_DISABLE_NETWORK") == "1":
		return
	var config = GameConfigScript.new()
	config.load_default()
	browser = LanGameBrowserScript.new()
	browser.name = "LanGameBrowser"
	add_child(browser)
	browser.games_updated.connect(_on_games_updated)
	browser.start(int(config.get_value("network", "discovery_port", 29445)))


func build_hider_input() -> Dictionary:
	var world_move := _camera_relative_move(move_vector)
	var message := {
		"type": "hider_input",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"player_id": player_id,
		"move": [world_move.x, world_move.y],
		"rotate": 0.0,
		"freeze": false,
		"request_shape": pending_shape,
		"request_color": pending_color,
		"ability": pending_ability,
		"client_time": Time.get_ticks_msec() / 1000.0
	}
	pending_shape = null
	pending_color = null
	pending_ability = null
	return message


func build_join_request() -> Dictionary:
	return {
		"type": "join_request",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"room_id": room_input.text.strip_edges(),
		"token": token_input.text.strip_edges(),
		"player_name": player_name,
		"preferred_shape": _selected_shape(),
		"preferred_color": _selected_color(),
		"preferred_pattern": _selected_pattern()
	}


# Joystick input is relative to what the player sees; convert to world axes.
func _camera_relative_move(joy: Vector2) -> Vector2:
	if joy.is_zero_approx():
		return Vector2.ZERO
	var forward := Vector2(-sin(cam_yaw), -cos(cam_yaw))
	var right := Vector2(cos(cam_yaw), -sin(cam_yaw))
	var world := right * joy.x + forward * (-joy.y)
	return world.limit_length(1.0)


func _configure_mobile_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	DisplayServer.screen_set_keep_on(true)


func apply_snapshot(snapshot: Dictionary) -> void:
	latest_snapshot = snapshot
	current_phase = snapshot.get("phase", current_phase)
	danger = snapshot.get("danger", danger)
	visible_objects = snapshot.get("objects", [])
	cooldowns = snapshot.get("cooldowns", {})
	hider_state = snapshot.get("hider_state", {})
	seeker_info = snapshot.get("seeker", {})
	# Endless mode: our body changed during the hunt, so we were found and rehomed.
	var body_id := String(hider_state.get("object_id", ""))
	if joined and bool(hider_state.get("alive", false)) and current_phase == "seek":
		if not last_body_object_id.is_empty() and not body_id.is_empty() and body_id != last_body_object_id:
			host_message = "FOUND! New body: %s" % String(hider_state.get("shape", "?"))
	last_body_object_id = body_id
	_sync_world_props()
	_update_status()


func _on_games_updated(games: Array) -> void:
	discovered_games = games
	if games_list == null:
		return
	games_list.clear()
	for game in games:
		var label := "%s   (%d in room, %s)" % [
			String(game.get("host_name", "Hidefall Room")),
			int(game.get("players", 0)),
			String(game.get("phase", "lobby"))
		]
		games_list.add_item(label)
	if selected_game_index >= games.size():
		selected_game_index = -1
	_update_status()


func _on_join_pressed() -> void:
	player_name = name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Hider"
	if selected_game_index >= 0 and selected_game_index < discovered_games.size():
		var game: Dictionary = discovered_games[selected_game_index]
		host_input.text = String(game.get("host_ip", host_input.text))
		port_input.text = str(int(game.get("port", 29444)))
		room_input.text = String(game.get("room_id", room_input.text))
		token_input.text = String(game.get("token", token_input.text))
	connection_status = "connecting"
	player_ready = false
	spectator = false
	host_message = ""
	_update_status()
	var error: Error = client.connect_to_host(host_input.text.strip_edges(), int(port_input.text))
	if error != OK:
		connection_status = "connect error %d" % int(error)
		_update_status()


func _on_connected() -> void:
	connection_status = "connected"
	client.send_message(build_join_request())
	_update_status()


func _on_disconnected() -> void:
	joined = false
	player_ready = false
	connection_status = "disconnected"
	current_phase = "disconnected"
	_show_menu()
	_update_status()


func _on_connection_failed() -> void:
	joined = false
	player_ready = false
	connection_status = "connection failed"
	_show_menu()
	_update_status()


func _on_message_received(message: Dictionary) -> void:
	match message.get("type", ""):
		"join_accepted":
			player_id = message.get("player_id", "")
			spectator = bool(message.get("spectator", false))
			var chosen_shape := _selected_shape()
			var chosen_color := _selected_color()
			var chosen_pattern := _selected_pattern()
			available_shapes = message.get("shapes", available_shapes)
			available_colors = message.get("colors", available_colors)
			available_patterns = message.get("patterns", available_patterns)
			selected_shape_index = maxi(0, available_shapes.find(chosen_shape))
			selected_color_index = maxi(0, available_colors.find(chosen_color))
			selected_pattern_index = maxi(0, available_patterns.find(chosen_pattern))
			joined = true
			player_ready = false
			connection_status = "joined as %s" % player_id
			_show_game()
		"join_rejected":
			joined = false
			host_message = "%s: %s" % [message.get("reason", "rejected"), message.get("detail", "")]
			connection_status = "rejected"
			_show_menu()
		"state_snapshot":
			apply_snapshot(message)
		"round_results":
			host_message = "Round results received"
		"pong":
			host_message = "pong %.2f" % float(message.get("server_time", 0.0))
	_update_status()


func _request_next_color() -> void:
	if available_colors.is_empty():
		return
	selected_color_index = (selected_color_index + 1) % available_colors.size()
	pending_color = available_colors[selected_color_index]


func _request_next_shape() -> void:
	if available_shapes.is_empty():
		return
	selected_shape_index = (selected_shape_index + 1) % available_shapes.size()
	pending_shape = available_shapes[selected_shape_index]


func _request_dash() -> void:
	pending_ability = "dash"
	_send_immediate_input()


func _request_mimic() -> void:
	pending_ability = "mimic"
	_send_immediate_input()


func _request_quake() -> void:
	pending_ability = "earthquake"
	_send_immediate_input()


func _request_ping() -> void:
	pending_ability = "ping"
	_send_immediate_input()


func _send_immediate_input() -> void:
	if joined and client.is_connected_to_host():
		client.send_message(build_hider_input())


func _on_ready_pressed() -> void:
	if not joined or player_id.is_empty() or spectator:
		return
	player_ready = not player_ready
	if ready_button != null:
		ready_button.text = "UNREADY" if player_ready else "READY"
	client.send_message({
		"type": "ready_state",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"player_id": player_id,
		"ready": player_ready
	})
	_update_status()


func _on_leave_pressed() -> void:
	client.close()
	joined = false
	player_ready = false
	connection_status = "left game"
	_show_menu()
	_update_status()


# --- selection helpers --------------------------------------------------------


func _selected_shape() -> String:
	if available_shapes.is_empty():
		return "cube"
	return available_shapes[selected_shape_index % available_shapes.size()]


func _selected_color() -> String:
	if available_colors.is_empty():
		return "red"
	return available_colors[selected_color_index % available_colors.size()]


func _selected_pattern() -> String:
	if available_patterns.is_empty():
		return "solid"
	return available_patterns[selected_pattern_index % available_patterns.size()]


func _cycle_selection(kind: String, direction: int) -> void:
	match kind:
		"shape":
			if not available_shapes.is_empty():
				selected_shape_index = posmod(selected_shape_index + direction, available_shapes.size())
		"color":
			if not available_colors.is_empty():
				selected_color_index = posmod(selected_color_index + direction, available_colors.size())
		"pattern":
			if not available_patterns.is_empty():
				selected_pattern_index = posmod(selected_pattern_index + direction, available_patterns.size())
	_refresh_selection_ui()


func _refresh_selection_ui() -> void:
	if shape_value_label != null:
		shape_value_label.text = content.get_shape_display_name(_selected_shape())
	if color_value_label != null:
		color_value_label.text = content.get_color_display_name(_selected_color())
	if color_swatch != null:
		color_swatch.color = Color(content.get_color_hex(_selected_color()))
	if pattern_value_label != null:
		pattern_value_label.text = content.get_pattern_display_name(_selected_pattern())
	_rebuild_preview_prop()


# --- 3D world ----------------------------------------------------------------


func _build_world() -> void:
	world_container = SubViewportContainer.new()
	world_container.name = "WorldView"
	world_container.stretch = true
	world_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	world_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world_container)
	world_viewport = SubViewport.new()
	world_viewport.own_world_3d = true
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_container.add_child(world_viewport)

	world_root = Node3D.new()
	world_root.name = "World"
	world_viewport.add_child(world_root)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.045, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.7
	environment.environment = env
	world_root.add_child(environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, 30.0, 0.0)
	light.light_energy = 1.6
	world_root.add_child(light)

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.4, 7.4)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.10, 0.13, 0.18)
	floor_material.albedo_texture = PropFactoryScript.pattern_texture("checker")
	floor_material.uv1_scale = Vector3(9.0, 9.0, 9.0)
	floor_material.roughness = 0.95
	floor_mesh.material_override = floor_material
	world_root.add_child(floor_mesh)

	var boundary := MeshInstance3D.new()
	boundary.name = "Boundary"
	var torus := TorusMesh.new()
	torus.inner_radius = 2.95
	torus.outer_radius = 3.02
	torus.ring_segments = 96
	boundary.mesh = torus
	var boundary_material := StandardMaterial3D.new()
	boundary_material.albedo_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.8)
	boundary_material.emission_enabled = true
	boundary_material.emission = ACCENT
	boundary_material.emission_energy_multiplier = 0.8
	boundary.material_override = boundary_material
	world_root.add_child(boundary)

	props_root = Node3D.new()
	props_root.name = "Props"
	world_root.add_child(props_root)

	seeker_avatar = _make_seeker_avatar()
	seeker_avatar.visible = false
	world_root.add_child(seeker_avatar)

	own_marker = MeshInstance3D.new()
	own_marker.name = "OwnMarker"
	var marker_mesh := TorusMesh.new()
	marker_mesh.inner_radius = 0.20
	marker_mesh.outer_radius = 0.25
	own_marker.mesh = marker_mesh
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85)
	marker_material.emission_enabled = true
	marker_material.emission = ACCENT
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	own_marker.material_override = marker_material
	own_marker.visible = false
	world_root.add_child(own_marker)

	world_camera = Camera3D.new()
	world_camera.name = "FollowCamera"
	world_camera.position = Vector3(0.0, 2.6, 4.4)
	world_camera.fov = 65.0
	world_root.add_child(world_camera)
	world_camera.look_at_from_position(world_camera.position, Vector3.ZERO)


# The Quest player's stand-in: a headset-ish head with a translucent view cone.
func _make_seeker_avatar() -> Node3D:
	var avatar := Node3D.new()
	avatar.name = "Seeker"
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.24, 0.20, 0.22)
	head.mesh = head_mesh
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = Color(0.92, 0.94, 0.98)
	head.material_override = head_material
	avatar.add_child(head)
	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.20, 0.09, 0.04)
	visor.mesh = visor_mesh
	visor.position = Vector3(0.0, 0.02, -0.12)
	var visor_material := StandardMaterial3D.new()
	visor_material.albedo_color = Color(0.08, 0.08, 0.1)
	visor.material_override = visor_material
	avatar.add_child(visor)
	var cone := MeshInstance3D.new()
	cone.name = "ViewCone"
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.02
	cone_mesh.bottom_radius = 0.55
	cone_mesh.height = 1.6
	cone.mesh = cone_mesh
	cone.rotation_degrees.x = 90.0
	cone.position = Vector3(0.0, 0.0, -0.8)
	var cone_material := StandardMaterial3D.new()
	cone_material.albedo_color = Color(0.95, 0.35, 0.25, 0.14)
	cone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone.material_override = cone_material
	avatar.add_child(cone)
	return avatar


# Mirrors snapshot objects into 3D prop nodes, creating/rebuilding on demand.
func _sync_world_props() -> void:
	if props_root == null:
		return
	var seen: Dictionary = {}
	for obj in visible_objects:
		if not obj is Dictionary:
			continue
		var object_id := String(obj.get("object_id", ""))
		if object_id.is_empty():
			continue
		seen[object_id] = true
		var look := "%s|%s|%s|%s" % [
			String(obj.get("shape", "cube")),
			String(obj.get("color", "white")),
			String(obj.get("pattern", "solid")),
			str(bool(obj.get("alive", true)))
		]
		if not world_props.has(object_id) or String(world_prop_looks.get(object_id, "")).split("|")[0] != String(obj.get("shape", "cube")):
			if world_props.has(object_id):
				world_props[object_id].queue_free()
			var prop: Node3D = PropFactoryScript.make_prop(String(obj.get("shape", "cube")))
			props_root.add_child(prop)
			world_props[object_id] = prop
			world_prop_looks[object_id] = ""
		if world_prop_looks.get(object_id, "") != look:
			world_prop_looks[object_id] = look
			var color := Color(content.get_color_hex(String(obj.get("color", "white"))))
			if not bool(obj.get("alive", true)):
				color = color.darkened(0.6)
			PropFactoryScript.apply_material(world_props[object_id], PropFactoryScript.make_material(color, String(obj.get("pattern", "solid"))))
		var position_array: Array = obj.get("position", [0.0, 0.15, 0.0])
		var orientation_array: Array = obj.get("orientation", [0.0, 0.0, 0.0, 1.0])
		if position_array.size() >= 3 and orientation_array.size() >= 4:
			world_prop_targets[object_id] = {
				"position": Vector3(float(position_array[0]), float(position_array[1]), float(position_array[2])),
				"orientation": Quaternion(float(orientation_array[0]), float(orientation_array[1]), float(orientation_array[2]), float(orientation_array[3])).normalized()
			}
	for object_id in world_props.keys():
		if not seen.has(object_id):
			world_props[object_id].queue_free()
			world_props.erase(object_id)
			world_prop_looks.erase(object_id)
			world_prop_targets.erase(object_id)
	# Seeker avatar from the shared snapshot.
	var seeker_position: Array = seeker_info.get("position", [])
	var seeker_forward: Array = seeker_info.get("forward", [])
	if seeker_avatar != null and seeker_position.size() >= 3:
		seeker_avatar.visible = joined and current_phase != "lobby"
		var head_pos := Vector3(float(seeker_position[0]), float(seeker_position[1]), float(seeker_position[2]))
		seeker_avatar.position = head_pos
		if seeker_forward.size() >= 3:
			var forward := Vector3(float(seeker_forward[0]), 0.0, float(seeker_forward[2]))
			if forward.length() > 0.01:
				seeker_avatar.rotation.y = atan2(-forward.x, -forward.z)


# Smoothly slides props toward their latest snapshot pose and drives the camera.
# The player's own prop blends fastest so their joystick feels snappy.
func _animate_world(delta: float) -> void:
	if world_camera == null:
		return
	var blend := clampf(delta * 14.0, 0.0, 1.0)
	var own_blend := clampf(delta * 22.0, 0.0, 1.0)
	var own_id := String(hider_state.get("object_id", ""))
	for object_id in world_prop_targets:
		if not world_props.has(object_id):
			continue
		var node: Node3D = world_props[object_id]
		var target: Dictionary = world_prop_targets[object_id]
		var prop_blend := own_blend if object_id == own_id else blend
		node.position = node.position.lerp(target["position"], prop_blend)
		node.quaternion = node.quaternion.slerp(target["orientation"], prop_blend)
	var focus := Vector3.ZERO
	if world_props.has(own_id):
		focus = world_props[own_id].position
		if own_marker != null:
			own_marker.visible = true
			own_marker.position = Vector3(focus.x, 0.03, focus.z)
	elif own_marker != null:
		own_marker.visible = false
	if not joined:
		cam_yaw += delta * 0.15
	var cam_distance := 2.6 if joined and not own_id.is_empty() else 5.2
	var cam_height := 1.5 if joined and not own_id.is_empty() else 3.2
	var cam_target := focus + Vector3(sin(cam_yaw) * cam_distance, cam_height, cos(cam_yaw) * cam_distance)
	world_camera.position = world_camera.position.lerp(cam_target, clampf(delta * 9.0, 0.0, 1.0))
	world_camera.look_at(focus + Vector3(0.0, 0.2, 0.0))


# --- menu UI -------------------------------------------------------------------


func _build_menu() -> void:
	menu_panel = Control.new()
	menu_panel.name = "MenuPanel"
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu_panel)

	var center := CenterContainer.new()
	center.name = "MenuCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_panel.add_child(center)

	var card := PanelContainer.new()
	card.name = "MenuCard"
	card.custom_minimum_size = Vector2(1000, 660)
	card.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	card.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)

	var title := Label.new()
	title.text = "HIDEFALL"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", ACCENT)
	rows.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Hide as a prop in the seeker's real room"
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	rows.add_child(subtitle)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	rows.add_child(body)

	# Left column: disguise picker + live preview.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(430, 0)
	body.add_child(left)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	left.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name"
	name_label.add_theme_font_size_override("font_size", 18)
	name_row.add_child(name_label)
	name_input = LineEdit.new()
	name_input.text = "Hider%03d" % (randi() % 1000)
	name_input.custom_minimum_size = Vector2(220, 40)
	name_row.add_child(name_input)

	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 16)
	left.add_child(preview_row)

	var preview_container := SubViewportContainer.new()
	preview_container.stretch = true
	preview_container.custom_minimum_size = Vector2(190, 190)
	preview_row.add_child(preview_container)
	preview_viewport = SubViewport.new()
	preview_viewport.own_world_3d = true
	preview_viewport.transparent_bg = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_container.add_child(preview_viewport)
	var preview_light := DirectionalLight3D.new()
	preview_light.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	preview_viewport.add_child(preview_light)
	var preview_camera := Camera3D.new()
	preview_camera.position = Vector3(0.0, 0.22, 0.62)
	preview_camera.fov = 45.0
	preview_viewport.add_child(preview_camera)
	preview_camera.look_at_from_position(preview_camera.position, Vector3(0.0, 0.0, 0.0))

	var pickers := VBoxContainer.new()
	pickers.add_theme_constant_override("separation", 8)
	preview_row.add_child(pickers)
	shape_value_label = _add_picker_row(pickers, "Shape", "shape")
	color_value_label = _add_picker_row(pickers, "Color", "color")
	pattern_value_label = _add_picker_row(pickers, "Pattern", "pattern")

	# Right column: discovered games + join.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	var games_label := Label.new()
	games_label.text = "Games on your Wi-Fi"
	games_label.add_theme_font_size_override("font_size", 18)
	right.add_child(games_label)

	games_list = ItemList.new()
	games_list.custom_minimum_size = Vector2(0, 170)
	games_list.add_theme_font_size_override("font_size", 18)
	games_list.item_selected.connect(func(index: int) -> void: selected_game_index = index)
	right.add_child(games_list)

	join_button = _make_button("JOIN GAME", 26, true)
	join_button.custom_minimum_size = Vector2(0, 60)
	join_button.pressed.connect(_on_join_pressed)
	right.add_child(join_button)

	var practice_button := _make_button("PRACTICE MINIGAMES", 20, false)
	practice_button.custom_minimum_size = Vector2(0, 48)
	practice_button.pressed.connect(_start_practice)
	right.add_child(practice_button)

	manual_toggle = _make_button("Manual join...", 16, false)
	manual_toggle.custom_minimum_size = Vector2(0, 36)
	right.add_child(manual_toggle)

	manual_row = HBoxContainer.new()
	manual_row.add_theme_constant_override("separation", 8)
	manual_row.visible = false
	right.add_child(manual_row)
	host_input = _make_line_edit(manual_row, "127.0.0.1", "Host IP", 170)
	port_input = _make_line_edit(manual_row, "29444", "Port", 90)
	room_input = _make_line_edit(manual_row, "842913", "Room", 110)
	token_input = _make_line_edit(manual_row, "hidefall", "Code", 120)
	manual_toggle.pressed.connect(func() -> void: manual_row.visible = not manual_row.visible)

	menu_status_label = Label.new()
	menu_status_label.add_theme_font_size_override("font_size", 15)
	menu_status_label.add_theme_color_override("font_color", Color(0.8, 0.86, 0.94))
	rows.add_child(menu_status_label)

	_refresh_selection_ui()


func _add_picker_row(parent: Control, title: String, kind: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var caption := Label.new()
	caption.text = title
	caption.custom_minimum_size = Vector2(72, 0)
	caption.add_theme_font_size_override("font_size", 17)
	row.add_child(caption)
	var previous := _make_button("<", 20, false)
	previous.custom_minimum_size = Vector2(46, 44)
	previous.pressed.connect(func() -> void: _cycle_selection(kind, -1))
	row.add_child(previous)
	if kind == "color":
		color_swatch = ColorRect.new()
		color_swatch.custom_minimum_size = Vector2(28, 28)
		color_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(color_swatch)
	var value := Label.new()
	value.custom_minimum_size = Vector2(96, 0)
	value.add_theme_font_size_override("font_size", 17)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	var next := _make_button(">", 20, false)
	next.custom_minimum_size = Vector2(46, 44)
	next.pressed.connect(func() -> void: _cycle_selection(kind, 1))
	row.add_child(next)
	return value


func _rebuild_preview_prop() -> void:
	if preview_viewport == null:
		return
	if preview_prop != null:
		preview_prop.queue_free()
	preview_prop = PropFactoryScript.make_prop(_selected_shape())
	var color := Color(content.get_color_hex(_selected_color()))
	PropFactoryScript.apply_material(preview_prop, PropFactoryScript.make_material(color, _selected_pattern()))
	preview_viewport.add_child(preview_prop)


func _animate_preview(delta: float) -> void:
	if preview_prop != null and menu_panel != null and menu_panel.visible:
		preview_prop.rotation.y += delta * 1.2


# --- game UI -------------------------------------------------------------------


func _build_game_ui() -> void:
	game_panel = Control.new()
	game_panel.name = "GamePanel"
	game_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(game_panel)

	top_bar = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 16.0
	top_bar.offset_top = 12.0
	top_bar.offset_right = -16.0
	top_bar.offset_bottom = 68.0
	top_bar.custom_minimum_size = Vector2(0, 56)
	top_bar.add_theme_stylebox_override("panel", _panel_style(10))
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_panel.add_child(top_bar)

	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 22)
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(bar_row)

	phase_label = Label.new()
	phase_label.add_theme_font_size_override("font_size", 22)
	phase_label.add_theme_color_override("font_color", ACCENT)
	bar_row.add_child(phase_label)

	danger_badge = Label.new()
	danger_badge.add_theme_font_size_override("font_size", 22)
	bar_row.add_child(danger_badge)

	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 18)
	info_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.96))
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(info_label)

	leave_button = _make_button("LEAVE", 16, false)
	leave_button.custom_minimum_size = Vector2(90, 40)
	leave_button.pressed.connect(_on_leave_pressed)
	bar_row.add_child(leave_button)

	_build_minigame_ui()

	joystick_area = Control.new()
	joystick_area.name = "Joystick"
	joystick_area.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joystick_area.offset_left = 40.0
	joystick_area.offset_top = -300.0
	joystick_area.offset_right = 300.0
	joystick_area.offset_bottom = -40.0
	joystick_area.mouse_filter = Control.MOUSE_FILTER_STOP
	joystick_area.draw.connect(_draw_joystick)
	joystick_area.gui_input.connect(_on_joystick_input)
	game_panel.add_child(joystick_area)

	var buttons := VBoxContainer.new()
	buttons.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	buttons.offset_left = -246.0
	buttons.offset_top = -300.0
	buttons.offset_right = -32.0
	buttons.offset_bottom = -30.0
	buttons.add_theme_constant_override("separation", 10)
	game_panel.add_child(buttons)

	ready_button = _make_button("READY", 22, true)
	ready_button.custom_minimum_size = Vector2(214, 56)
	ready_button.pressed.connect(_on_ready_pressed)
	buttons.add_child(ready_button)

	var ability_grid := GridContainer.new()
	ability_grid.columns = 2
	ability_grid.add_theme_constant_override("h_separation", 10)
	ability_grid.add_theme_constant_override("v_separation", 10)
	buttons.add_child(ability_grid)

	dash_button = _make_button("DASH", 18, true)
	mimic_button = _make_button("MIMIC", 18, false)
	quake_button = _make_button("QUAKE", 18, false)
	ping_button = _make_button("PING", 18, false)
	color_button = _make_button("COLOR", 18, false)
	shape_button = _make_button("SHAPE", 18, false)
	dash_button.pressed.connect(_request_dash)
	mimic_button.pressed.connect(_request_mimic)
	quake_button.pressed.connect(_request_quake)
	ping_button.pressed.connect(_request_ping)
	color_button.pressed.connect(_request_next_color)
	shape_button.pressed.connect(_request_next_shape)
	for ability_button in [dash_button, mimic_button, quake_button, ping_button, color_button, shape_button]:
		ability_button.custom_minimum_size = Vector2(102, 56)
		ability_grid.add_child(ability_button)

	overlay_label = Label.new()
	overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_label.add_theme_font_size_override("font_size", 64)
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_label.visible = false
	game_panel.add_child(overlay_label)

	game_status_label = Label.new()
	game_status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	game_status_label.offset_left = 340.0
	game_status_label.offset_top = -40.0
	game_status_label.offset_right = -340.0
	game_status_label.offset_bottom = -10.0
	game_status_label.add_theme_font_size_override("font_size", 15)
	game_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_panel.add_child(game_status_label)


func _draw_joystick() -> void:
	if joystick_area == null:
		return
	var center := joystick_area.size * 0.5
	var base_radius := 92.0
	joystick_area.draw_circle(center, base_radius, Color(0.5, 0.6, 0.75, 0.18))
	joystick_area.draw_arc(center, base_radius, 0.0, TAU, 48, Color(0.65, 0.78, 0.9, 0.55), 3.0)
	var knob := center + move_vector * (base_radius - 26.0)
	joystick_area.draw_circle(knob, 30.0, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85))


# --- inspection minigame engine (runs locally on the phone) --------------------


func _build_minigame_ui() -> void:
	minigame_panel = Control.new()
	minigame_panel.name = "MinigamePanel"
	minigame_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	minigame_panel.offset_top = 58.0
	minigame_panel.offset_bottom = -14.0
	minigame_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	minigame_panel.visible = false
	minigame_panel.draw.connect(_draw_minigame)
	game_panel.add_child(minigame_panel)

	mg_title_label = _mg_make_label(44, ACCENT, Control.PRESET_TOP_WIDE, 4.0)
	mg_instructions_label = _mg_make_label(26, Color(0.9, 0.94, 1.0), Control.PRESET_TOP_WIDE, 60.0)
	mg_countdown_label = _mg_make_label(72, Color(1, 1, 1), Control.PRESET_CENTER, 0.0)

	mg_bar_area = Control.new()
	mg_bar_area.name = "MgBar"
	mg_bar_area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mg_bar_area.mouse_filter = Control.MOUSE_FILTER_STOP
	mg_bar_area.gui_input.connect(_on_mg_bar_input)
	minigame_panel.add_child(mg_bar_area)

	mg_button_a = Button.new()
	mg_button_a.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mg_button_a.add_theme_font_size_override("font_size", 34)
	mg_button_a.button_down.connect(_on_mg_a_down)
	mg_button_a.button_up.connect(_on_mg_a_up)
	minigame_panel.add_child(mg_button_a)

	mg_button_b = Button.new()
	mg_button_b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mg_button_b.add_theme_font_size_override("font_size", 34)
	mg_button_b.button_down.connect(_on_mg_b_down)
	minigame_panel.add_child(mg_button_b)

	mg_prompt_label = Label.new()
	mg_prompt_label.name = "MgPrompt"
	mg_prompt_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	mg_prompt_label.offset_top = 120.0
	mg_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mg_prompt_label.add_theme_font_size_override("font_size", 54)
	mg_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mg_prompt_label.visible = false
	minigame_panel.add_child(mg_prompt_label)

	for i in 6:
		var cb := Button.new()
		cb.name = "MgChoice%d" % i
		cb.set_anchors_preset(Control.PRESET_TOP_LEFT)
		cb.add_theme_font_size_override("font_size", 30)
		cb.visible = false
		cb.pressed.connect(_on_mg_choice.bind(i))
		minigame_panel.add_child(cb)
		mg_choice_buttons.append(cb)

	practice_exit_button = Button.new()
	practice_exit_button.name = "PracticeExit"
	practice_exit_button.text = "EXIT"
	practice_exit_button.add_theme_font_size_override("font_size", 22)
	practice_exit_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	practice_exit_button.position = Vector2(16, 8)
	practice_exit_button.size = Vector2(128, 54)
	practice_exit_button.visible = false
	practice_exit_button.pressed.connect(_exit_practice)
	minigame_panel.add_child(practice_exit_button)

	minigame_flash_label = Label.new()
	minigame_flash_label.name = "MgFlash"
	minigame_flash_label.set_anchors_preset(Control.PRESET_CENTER)
	minigame_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	minigame_flash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	minigame_flash_label.add_theme_font_size_override("font_size", 48)
	minigame_flash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minigame_flash_label.visible = false
	game_panel.add_child(minigame_flash_label)


func _mg_make_label(font_size: int, color: Color, preset: int, top: float) -> Label:
	var label := Label.new()
	label.set_anchors_preset(preset)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.offset_top = top
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if minigame_panel != null:
		minigame_panel.add_child(label)
	return label


func _minigame_start(minigame_id: String, difficulty: int) -> void:
	if minigame_panel == null or not MinigamesScript.exists(minigame_id):
		return
	mg_id = minigame_id
	mg_difficulty = difficulty
	mg_params = MinigamesScript.params_for(minigame_id, difficulty)
	mg_running = true
	mg_result_sent = false
	mg_phase = "intro"
	mg_time = 0.0
	mg_holding = false
	mg_drag_x = 0.0
	mg_tap_pending = 0
	mg_rng.randomize()
	mg_state = {"presses": [], "released": false}
	_minigame_init_state()
	mg_title_label.text = String(mg_params.get("label", ""))
	mg_instructions_label.text = String(mg_params.get("instructions", ""))
	mg_countdown_label.text = "GET READY"
	mg_countdown_label.visible = true
	# Cover the whole screen in practice; leave the status bar visible in a round.
	minigame_panel.offset_top = 0.0 if practice_mode else 58.0
	minigame_panel.visible = true
	_mg_configure_widgets()
	_mg_layout()
	minigame_panel.queue_redraw()


func _minigame_teardown() -> void:
	mg_running = false
	if minigame_panel != null:
		minigame_panel.visible = false
	if mg_button_a != null:
		mg_button_a.visible = false
	if mg_button_b != null:
		mg_button_b.visible = false


func _minigame_finish(passed: bool) -> void:
	if mg_result_sent:
		return
	mg_result_sent = true
	mg_running = false
	if mg_button_a != null:
		mg_button_a.visible = false
	if mg_button_b != null:
		mg_button_b.visible = false
	if practice_mode:
		# Practice: no host to tell; just show the result and queue the next game.
		_flash_minigame("NICE - HELD STILL!" if passed else "CAUGHT! TRY AGAIN", DANGER_COLORS["safe"] if passed else DANGER_COLORS["critical"])
		practice_next_in = 1.6
		return
	if joined and client != null and client.is_connected_to_host():
		client.send_message({
			"type": "minigame_result",
			"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
			"player_id": player_id,
			"passed": passed
		})
	if passed:
		_flash_minigame("STAYED STILL!", DANGER_COLORS["safe"])
	else:
		_flash_minigame("CAUGHT! DROPPED", DANGER_COLORS["critical"])
	mg_awaiting_clear = true
	_minigame_teardown()


# Practice mode: play every minigame back-to-back, no host needed, from the
# startup screen. Handy for learning the games and for tuning.
func _start_practice() -> void:
	practice_mode = true
	practice_index = -1
	if menu_panel != null:
		menu_panel.visible = false
	if game_panel != null:
		game_panel.visible = true
	if practice_exit_button != null:
		practice_exit_button.visible = true
	_practice_next()


func _practice_next() -> void:
	if not practice_mode:
		return
	var all_ids: Array = MinigamesScript.ids()
	practice_index = (practice_index + 1) % all_ids.size()
	# Difficulty creeps up as you get further into the set.
	_minigame_start(String(all_ids[practice_index]), practice_index / 5)
	if practice_exit_button != null:
		practice_exit_button.visible = true


func _exit_practice() -> void:
	practice_mode = false
	practice_next_in = 0.0
	if practice_exit_button != null:
		practice_exit_button.visible = false
	_minigame_teardown()
	_show_menu()


func _minigame_process(delta: float) -> void:
	mg_time += delta
	if mg_phase == "intro":
		var remaining := float(mg_params.get("intro", 1.5)) - mg_time
		mg_countdown_label.text = "GET READY  %.0f" % maxf(1.0, ceil(remaining))
		if mg_time >= float(mg_params.get("intro", 1.5)):
			mg_phase = "play"
			mg_time = 0.0
			mg_countdown_label.visible = false
			mg_tap_pending = 0
			mg_state["released"] = false
		minigame_panel.queue_redraw()
		return
	_mg_layout()
	_minigame_tick(delta)
	mg_tap_pending = 0
	mg_state["released"] = false
	mg_state["presses"] = []
	if minigame_panel != null:
		minigame_panel.queue_redraw()


func _minigame_init_state() -> void:
	if String(mg_params.get("archetype", "")) == "choice":
		_mg_init_choice()
		return
	match mg_id:
		"bullseye":
			mg_state["goods"] = 0
		"metronome":
			mg_state["hits"] = 0
			mg_state["last_beat"] = -1
		"reflex":
			mg_state["green"] = false
			mg_state["hits"] = 0
			mg_state["next_at"] = randf_range(float(mg_params.get("min_wait", 0.6)), float(mg_params.get("max_wait", 2.0)))
		"charge_up":
			mg_state["level"] = 0.0
			mg_state["done"] = false
		"pulse_hold":
			mg_state["err"] = 0.0
		"trace_wave":
			mg_state["dot"] = 0.0
			mg_state["out"] = 0.0
			mg_state["zone_center"] = 0.0
		"hot_cold":
			mg_state["dot"] = 0.0
			mg_state["target"] = randf_range(-0.7, 0.7)
			mg_state["near_t"] = 0.0
		"keep_center", "tightrope", "shadow", "hot_zone":
			mg_state["dot"] = 0.0
			mg_state["out"] = 0.0
			mg_state["zone_center"] = 0.0
			mg_state["jump_t"] = 0.0
		"copy_cat":
			var length := int(mg_params.get("length", 3))
			var seq: Array = []
			for _i in length:
				seq.append("L" if randf() < 0.5 else "R")
			mg_state["seq"] = seq
			mg_state["idx"] = 0
		"whack":
			mg_state["hits"] = 0
			mg_state["hop_t"] = 999.0
			mg_state["target"] = Vector2(0.5, 0.5)
		"green_light", "beat_tap":
			mg_state["goods"] = 0
		"mash_meter", "hold_still":
			mg_state["fill"] = 0.0
		"tap_count":
			mg_state["count"] = 0
		"twitchy":
			mg_state["survived"] = 0
			mg_state["flash"] = false
		"deep_breath":
			mg_state["err"] = 0.0
		"perfect_stop", "let_go":
			mg_state["done"] = false


func _mg_init_choice() -> void:
	mg_state["rounds_won"] = 0
	mg_state["rounds_needed"] = int(mg_params.get("rounds_needed", 3))
	mg_state["lives"] = 1
	mg_state["show_left"] = float(mg_params.get("show", 0.0))
	mg_state["round"] = MinigamesScript.make_round(mg_id, mg_difficulty, mg_rng)
	if mg_id == "simon_say":
		mg_state["seq"] = (mg_state["round"] as Dictionary).get("sequence", [])
		mg_state["input_idx"] = 0
		mg_state["show_left"] = 0.55 * float((mg_state["seq"] as Array).size()) + 0.5


func _mg_configure_widgets() -> void:
	var archetype := String(mg_params.get("archetype", "tap"))
	mg_button_b.visible = false
	mg_bar_area.visible = false
	mg_button_a.visible = true
	if mg_prompt_label != null:
		mg_prompt_label.visible = false
	for cb in mg_choice_buttons:
		cb.visible = false
	match archetype:
		"drag":
			mg_button_a.visible = false
			mg_bar_area.visible = true
		"hold":
			mg_button_a.text = "HOLD"
		"choice":
			mg_button_a.visible = false
			var options: Array = (mg_state.get("round", {}) as Dictionary).get("options", [])
			for i in mg_choice_buttons.size():
				if i < options.size():
					mg_choice_buttons[i].text = String(options[i])
		"tap":
			if mg_id == "copy_cat":
				mg_button_a.text = "◀ L"
				mg_button_b.text = "R ▶"
				mg_button_b.visible = true
			elif mg_id == "hold_still":
				mg_button_a.text = "HOLD"
			elif mg_id == "bullseye":
				mg_button_a.text = "TAP!"
			elif mg_id == "reflex" or mg_id == "metronome":
				mg_button_a.text = "TAP"
			else:
				mg_button_a.text = "TAP"


# --- choice (word/quiz) engine ---
func _mg_choice_tick(delta: float) -> void:
	var duration := float(mg_params.get("duration", 6.0))
	var round: Dictionary = mg_state.get("round", {})
	if float(mg_state.get("show_left", 0.0)) > 0.0:
		mg_state["show_left"] = float(mg_state["show_left"]) - delta
		_mg_show_choice_prompt(round, true)
		_mg_set_choices_visible(false)
		if float(mg_state["show_left"]) <= 0.0:
			_mg_set_choices_visible(true)
		return
	_mg_show_choice_prompt(round, false)
	_mg_set_choices_visible(true)
	if mg_time >= duration:
		_minigame_finish(int(mg_state.get("rounds_won", 0)) >= int(mg_state.get("rounds_needed", 1)))


func _mg_show_choice_prompt(round: Dictionary, memorizing: bool) -> void:
	if mg_prompt_label == null:
		return
	var text := String(round.get("prompt", ""))
	var color := Color(0.95, 0.97, 1.0)
	if memorizing:
		if mg_id == "word_recall":
			text = String(round.get("memorize", text))
		elif mg_id == "simon_say":
			var names: Array = []
			for idx in mg_state.get("seq", []):
				var opts: Array = round.get("options", [])
				if int(idx) < opts.size():
					names.append(String(opts[int(idx)]))
			text = " - ".join(names)
	else:
		if mg_id == "word_recall":
			text = "TAP THE WORD"
		elif mg_id == "simon_say":
			text = "REPEAT!"
	if round.has("prompt_color"):
		color = _mg_color_from_name(String(round["prompt_color"]))
	mg_prompt_label.text = text
	mg_prompt_label.add_theme_color_override("font_color", color)
	mg_prompt_label.visible = true


func _mg_set_choices_visible(shown: bool) -> void:
	var n: int = (mg_state.get("round", {}) as Dictionary).get("options", []).size()
	for i in mg_choice_buttons.size():
		mg_choice_buttons[i].visible = shown and i < n


func _mg_next_round() -> void:
	mg_state["round"] = MinigamesScript.make_round(mg_id, mg_difficulty, mg_rng)
	var round: Dictionary = mg_state["round"]
	var options: Array = round.get("options", [])
	for i in mg_choice_buttons.size():
		if i < options.size():
			mg_choice_buttons[i].text = String(options[i])
	_mg_show_choice_prompt(round, false)
	_mg_set_choices_visible(true)
	_mg_layout()


func _on_mg_choice(index: int) -> void:
	if not mg_running or mg_phase != "play" or float(mg_state.get("show_left", 0.0)) > 0.0:
		return
	var round: Dictionary = mg_state.get("round", {})
	if mg_id == "simon_say":
		var seq: Array = mg_state.get("seq", [])
		var ii := int(mg_state.get("input_idx", 0))
		if ii < seq.size() and index == int(seq[ii]):
			mg_state["input_idx"] = ii + 1
			if ii + 1 >= seq.size():
				_minigame_finish(true)
		else:
			_minigame_finish(false)
		return
	if index == int(round.get("correct", -1)):
		mg_state["rounds_won"] = int(mg_state.get("rounds_won", 0)) + 1
		if int(mg_state["rounds_won"]) >= int(mg_state.get("rounds_needed", 1)):
			_minigame_finish(true)
		else:
			_mg_next_round()
	else:
		mg_state["lives"] = int(mg_state.get("lives", 1)) - 1
		if int(mg_state["lives"]) < 0:
			_minigame_finish(false)
		else:
			_mg_next_round()


func _mg_color_from_name(name: String) -> Color:
	match name:
		"RED": return Color(0.94, 0.28, 0.26)
		"BLUE": return Color(0.28, 0.5, 0.95)
		"GREEN": return Color(0.3, 0.8, 0.42)
		"YELLOW": return Color(0.95, 0.85, 0.25)
		"PURPLE": return Color(0.7, 0.4, 0.9)
		"ORANGE": return Color(0.98, 0.6, 0.2)
	return Color(0.9, 0.92, 1.0)


func _mg_layout() -> void:
	if minigame_panel == null:
		return
	var s := minigame_panel.size
	if s.x < 1.0:
		return
	mg_bar_area.position = Vector2(0, s.y * 0.34)
	mg_bar_area.size = Vector2(s.x, s.y * 0.28)
	var bh := 118.0
	var by := s.y - bh - 26.0
	if String(mg_params.get("archetype", "")) == "choice":
		var opts: Array = (mg_state.get("round", {}) as Dictionary).get("options", [])
		var n := opts.size()
		var cbw := (s.x - 70.0) * 0.5
		var cbh := minf(104.0, (s.y * 0.44) / 2.0 - 16.0)
		var startx := 30.0
		var starty := s.y * 0.46
		for i in mg_choice_buttons.size():
			if i < n:
				var col := i % 2
				var row := i / 2
				mg_choice_buttons[i].size = Vector2(cbw, cbh)
				mg_choice_buttons[i].position = Vector2(startx + float(col) * (cbw + 10.0), starty + float(row) * (cbh + 14.0))
		return
	if mg_id == "copy_cat":
		var bw := minf(240.0, s.x * 0.4)
		mg_button_a.size = Vector2(bw, bh)
		mg_button_a.position = Vector2(s.x * 0.5 - bw - 14.0, by)
		mg_button_b.size = Vector2(bw, bh)
		mg_button_b.position = Vector2(s.x * 0.5 + 14.0, by)
	elif mg_id == "whack" and mg_phase == "play":
		var wsz := 132.0
		var target: Vector2 = mg_state.get("target", Vector2(0.5, 0.5))
		mg_button_a.size = Vector2(wsz, wsz)
		mg_button_a.position = Vector2(target.x * (s.x - wsz), s.y * 0.22 + target.y * (s.y * 0.5 - wsz))
	else:
		var bw2 := minf(360.0, s.x * 0.6)
		mg_button_a.size = Vector2(bw2, bh)
		mg_button_a.position = Vector2(s.x * 0.5 - bw2 * 0.5, by)


# Per-game logic. `taps` is presses of button A this frame; `holding` is whether
# A is held; `mg_drag_x` (-1..1) is the drag position. Calls _minigame_finish.
func _minigame_tick(delta: float) -> void:
	if String(mg_params.get("archetype", "")) == "choice":
		_mg_choice_tick(delta)
		return
	var taps := mg_tap_pending
	var holding := mg_holding
	var duration := float(mg_params.get("duration", 4.0))
	match mg_id:
		"bullseye":
			var r := absf(sin(mg_time * float(mg_params.get("speed", 1.0)) * PI))
			if taps > 0 and r <= float(mg_params.get("window", 0.15)):
				mg_state["goods"] = int(mg_state.get("goods", 0)) + 1
			if int(mg_state.get("goods", 0)) >= int(mg_params.get("needed", 1)):
				_minigame_finish(true)
			elif mg_time >= duration:
				_minigame_finish(false)
		"metronome":
			var period := float(mg_params.get("period", 0.7))
			if taps > 0:
				var phase := fmod(mg_time, period)
				if phase < float(mg_params.get("window", 0.18)) or phase > period - float(mg_params.get("window", 0.18)):
					var beat_idx := int(round(mg_time / period))
					if beat_idx != int(mg_state.get("last_beat", -1)):
						mg_state["hits"] = int(mg_state.get("hits", 0)) + 1
						mg_state["last_beat"] = beat_idx
			if int(mg_state.get("hits", 0)) >= int(mg_params.get("beats", 4)):
				_minigame_finish(true)
			elif mg_time >= duration:
				_minigame_finish(false)
		"reflex":
			if not bool(mg_state.get("green", false)):
				if mg_time >= float(mg_state.get("next_at", 1.0)):
					mg_state["green"] = true
				elif taps > 0:
					_minigame_finish(false)
					return
			elif taps > 0:
				mg_state["hits"] = int(mg_state.get("hits", 0)) + 1
				mg_state["green"] = false
				mg_state["next_at"] = mg_time + randf_range(float(mg_params.get("min_wait", 0.6)), float(mg_params.get("max_wait", 2.0)))
				if int(mg_state["hits"]) >= int(mg_params.get("needed", 2)):
					_minigame_finish(true)
			if mg_time >= duration and mg_running:
				_minigame_finish(int(mg_state.get("hits", 0)) >= int(mg_params.get("needed", 2)))
		"charge_up":
			var level := float(mg_state.get("level", 0.0))
			level += (float(mg_params.get("rise", 0.5)) if holding else -0.3) * delta
			level = clampf(level, 0.0, 1.2)
			mg_state["level"] = level
			if bool(mg_state.get("released", false)) and not bool(mg_state.get("done", false)) and level > 0.1:
				mg_state["done"] = true
				_minigame_finish(absf(level - float(mg_params.get("target", 0.75))) <= float(mg_params.get("window", 0.12)))
			elif mg_time >= duration:
				_minigame_finish(false)
		"pulse_hold":
			var pperiod := float(mg_params.get("period", 1.2))
			var green_frac := float(mg_params.get("green_frac", 0.5))
			var is_green := fmod(mg_time, pperiod) < pperiod * green_frac
			var phase2 := fmod(mg_time, pperiod)
			var near := phase2 < 0.16 or absf(phase2 - pperiod * green_frac) < 0.16 or phase2 > pperiod - 0.16
			if holding != is_green and not near:
				mg_state["err"] = float(mg_state.get("err", 0.0)) + delta
			else:
				mg_state["err"] = maxf(0.0, float(mg_state.get("err", 0.0)) - delta)
			if float(mg_state.get("err", 0.0)) >= 0.7:
				_minigame_finish(false)
			elif mg_time >= float(mg_params.get("cycles", 2)) * pperiod:
				_minigame_finish(true)
		"trace_wave":
			var twtarget := sin(mg_time * float(mg_params.get("target_speed", 0.6)) * PI)
			mg_state["dot"] = mg_drag_x
			mg_state["zone_center"] = twtarget
			_mg_zone_check(absf(mg_drag_x - twtarget) <= float(mg_params.get("zone", 0.35)), delta, duration)
		"hot_cold":
			mg_state["dot"] = mg_drag_x
			var dist := absf(mg_drag_x - float(mg_state.get("target", 0.0)))
			if dist <= float(mg_params.get("tolerance", 0.1)):
				mg_state["near_t"] = float(mg_state.get("near_t", 0.0)) + delta
			else:
				mg_state["near_t"] = 0.0
			if float(mg_state.get("near_t", 0.0)) >= float(mg_params.get("hold_time", 0.5)):
				_minigame_finish(true)
			elif mg_time >= duration:
				_minigame_finish(false)
		"mash_meter":
			var target_taps := float(mg_params.get("target_taps", 12))
			var fill := float(mg_state["fill"]) + float(taps) / target_taps
			fill -= float(mg_params.get("drain_per_sec", 3.5)) / target_taps * delta
			mg_state["fill"] = clampf(fill, 0.0, 1.0)
			if fill >= 1.0:
				_minigame_finish(true)
			elif mg_time >= duration:
				_minigame_finish(false)
		"tap_count":
			var target := int(mg_params.get("target_taps", 6))
			mg_state["count"] = int(mg_state["count"]) + taps
			if int(mg_state["count"]) >= target:
				_minigame_finish(int(mg_state["count"]) == target)
			elif mg_time >= duration:
				_minigame_finish(false)
		"beat_tap":
			var needle := sin(mg_time * float(mg_params.get("sweep_speed", 1.0)) * PI)
			if taps > 0:
				if absf(needle) <= float(mg_params.get("window", 0.2)):
					mg_state["goods"] = int(mg_state["goods"]) + 1
			if int(mg_state["goods"]) >= int(mg_params.get("needed", 3)):
				_minigame_finish(true)
			elif mg_time >= duration:
				_minigame_finish(false)
		"green_light":
			var cycle := float(mg_params.get("cycle", 1.0))
			var is_green := fmod(mg_time, cycle) < cycle * float(mg_params.get("green_frac", 0.5))
			if taps > 0:
				if is_green:
					mg_state["goods"] = int(mg_state["goods"]) + 1
				else:
					_minigame_finish(false)
					return
			if int(mg_state["goods"]) >= int(mg_params.get("needed", 3)):
				_minigame_finish(true)
			elif mg_time >= duration:
				_minigame_finish(false)
		"copy_cat":
			var seq: Array = mg_state.get("seq", [])
			for press in mg_state.get("presses", []):
				var idx := int(mg_state["idx"])
				if idx < seq.size() and String(press) == String(seq[idx]):
					mg_state["idx"] = idx + 1
				else:
					_minigame_finish(false)
					return
			if int(mg_state["idx"]) >= seq.size():
				_minigame_finish(true)
			elif mg_time >= duration:
				_minigame_finish(false)
		"whack":
			mg_state["hop_t"] = float(mg_state["hop_t"]) + delta
			if taps > 0:
				mg_state["hits"] = int(mg_state["hits"]) + 1
				mg_state["hop_t"] = 999.0
			if float(mg_state["hop_t"]) >= float(mg_params.get("hop", 0.8)):
				mg_state["hop_t"] = 0.0
				mg_state["target"] = Vector2(randf(), randf())
			if int(mg_state["hits"]) >= int(mg_params.get("needed", 4)):
				_minigame_finish(true)
			elif mg_time >= duration:
				_minigame_finish(false)
		"perfect_stop":
			if taps > 0 and not bool(mg_state["done"]):
				mg_state["done"] = true
				var marker := sin(mg_time * float(mg_params.get("speed", 1.0)) * PI)
				_minigame_finish(absf(marker) <= float(mg_params.get("window", 0.2)))
			elif mg_time >= duration:
				_minigame_finish(false)
		"hold_still":
			if holding:
				mg_state["fill"] = float(mg_state["fill"]) + delta
			if float(mg_state["fill"]) >= duration:
				_minigame_finish(true)
			elif mg_time >= duration + 2.0:
				_minigame_finish(false)
		"let_go":
			var level := fmod(mg_time * float(mg_params.get("rise", 0.6)), 1.0)
			if bool(mg_state["released"]) and not bool(mg_state["done"]):
				mg_state["done"] = true
				_minigame_finish(absf(level - 0.75) <= float(mg_params.get("window", 0.15)))
			elif mg_time >= duration:
				_minigame_finish(false)
		"twitchy":
			var flashes := int(mg_params.get("flashes", 3))
			var seg := duration / float(flashes + 1)
			var react := float(mg_params.get("react", 0.6))
			var idx := int(mg_time / seg)
			var in_flash := idx >= 1 and (mg_time - float(idx) * seg) < react
			mg_state["flash"] = in_flash
			if in_flash and holding and (mg_time - float(idx) * seg) > react * 0.9:
				_minigame_finish(false)
				return
			if mg_time >= duration:
				_minigame_finish(true)
		"deep_breath":
			var period := float(mg_params.get("period", 1.5))
			var want_hold := fmod(mg_time, period) < period * 0.5
			var near_edge := absf(fmod(mg_time, period * 0.5)) < 0.18 or absf(fmod(mg_time, period * 0.5) - period * 0.5) < 0.18
			if holding != want_hold and not near_edge:
				mg_state["err"] = float(mg_state["err"]) + delta
			else:
				mg_state["err"] = maxf(0.0, float(mg_state["err"]) - delta)
			if float(mg_state["err"]) >= 0.8:
				_minigame_finish(false)
			elif mg_time >= float(mg_params.get("cycles", 2)) * period:
				_minigame_finish(true)
		"keep_center", "tightrope":
			var flip := float(mg_params.get("flip", 1.0))
			var drift_dir := 1.0 if sin(mg_time * flip) >= 0.0 else -1.0
			var dot := float(mg_state["dot"])
			dot += ((mg_drag_x - dot) * 6.0 + drift_dir * float(mg_params.get("drift", 0.6))) * delta
			mg_state["dot"] = clampf(dot, -1.0, 1.0)
			_mg_zone_check(absf(float(mg_state["dot"])) <= float(mg_params.get("zone", 0.4)), delta, duration)
		"shadow":
			var target := sin(mg_time * float(mg_params.get("target_speed", 0.5)) * PI)
			mg_state["dot"] = mg_drag_x
			mg_state["zone_center"] = target
			_mg_zone_check(absf(mg_drag_x - target) <= float(mg_params.get("zone", 0.35)), delta, duration)
		"hot_zone":
			mg_state["jump_t"] = float(mg_state["jump_t"]) + delta
			if float(mg_state["jump_t"]) >= float(mg_params.get("jump_every", 1.2)):
				mg_state["jump_t"] = 0.0
				mg_state["zone_center"] = randf_range(-0.6, 0.6)
			mg_state["dot"] = mg_drag_x
			_mg_zone_check(absf(mg_drag_x - float(mg_state["zone_center"])) <= float(mg_params.get("zone", 0.35)), delta, duration)


func _mg_zone_check(in_zone: bool, delta: float, duration: float) -> void:
	if in_zone:
		mg_state["out"] = maxf(0.0, float(mg_state["out"]) - delta)
	else:
		mg_state["out"] = float(mg_state["out"]) + delta
	if float(mg_state["out"]) >= float(mg_params.get("fail_at", 1.2)):
		_minigame_finish(false)
	elif mg_time >= duration:
		_minigame_finish(true)


func _draw_minigame() -> void:
	if minigame_panel == null or not mg_running:
		return
	var s := minigame_panel.size
	minigame_panel.draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.06, 0.11, 0.96), true)
	if mg_phase != "play":
		return
	var mid_y := s.y * 0.48
	var left := s.x * 0.1
	var right := s.x * 0.9
	var span := right - left
	var midx := (left + right) * 0.5
	var archetype := String(mg_params.get("archetype", "tap"))
	if archetype == "choice":
		_mg_draw_progress(int(mg_state.get("rounds_won", 0)), int(mg_state.get("rounds_needed", 1)), s)
		return
	if mg_id == "hot_cold":
		var hdot := float(mg_state.get("dot", 0.0))
		var hdist := absf(hdot - float(mg_state.get("target", 0.0)))
		var warm := clampf(1.0 - hdist / 1.2, 0.0, 1.0)
		minigame_panel.draw_line(Vector2(left, mid_y), Vector2(right, mid_y), Color(0.4, 0.5, 0.65, 0.7), 6.0)
		minigame_panel.draw_circle(Vector2(midx + hdot * span * 0.5, mid_y), 30.0, Color(0.2 + 0.75 * warm, 0.4 + 0.25 * warm, 1.0 - 0.7 * warm))
		return
	if mg_id == "bullseye":
		var r := absf(sin(mg_time * float(mg_params.get("speed", 1.0)) * PI))
		minigame_panel.draw_arc(Vector2(midx, mid_y), span * 0.28 * (0.12 + r), 0.0, TAU, 40, ACCENT, 6.0)
		minigame_panel.draw_circle(Vector2(midx, mid_y), 9.0, DANGER_COLORS["safe"])
		_mg_draw_progress(int(mg_state.get("goods", 0)), int(mg_params.get("needed", 1)), s)
		return
	if mg_id == "reflex":
		minigame_panel.draw_rect(Rect2(Vector2(left, mid_y - 70), Vector2(span, 140)), DANGER_COLORS["safe"] if bool(mg_state.get("green", false)) else DANGER_COLORS["critical"], true)
		_mg_draw_progress(int(mg_state.get("hits", 0)), int(mg_params.get("needed", 2)), s)
		return
	if mg_id == "metronome":
		var mphase := fmod(mg_time, float(mg_params.get("period", 0.7))) / float(mg_params.get("period", 0.7))
		minigame_panel.draw_circle(Vector2(midx, mid_y), 20.0 + 44.0 * clampf(1.0 - mphase * 3.0, 0.0, 1.0), ACCENT)
		_mg_draw_progress(int(mg_state.get("hits", 0)), int(mg_params.get("beats", 4)), s)
		return
	if mg_id == "charge_up":
		var level := float(mg_state.get("level", 0.0))
		var ctarget := float(mg_params.get("target", 0.75))
		var cwindow := float(mg_params.get("window", 0.12))
		minigame_panel.draw_rect(Rect2(Vector2(left, mid_y - 18), Vector2(span, 36)), Color(0.2, 0.25, 0.34, 0.7), true)
		minigame_panel.draw_rect(Rect2(Vector2(left + span * (ctarget - cwindow), mid_y - 26), Vector2(span * cwindow * 2.0, 52)), Color(0.25, 0.78, 0.42, 0.35), true)
		minigame_panel.draw_rect(Rect2(Vector2(left, mid_y - 18), Vector2(span * clampf(level, 0.0, 1.0), 36)), ACCENT, true)
		return
	if mg_id == "pulse_hold":
		var phg := fmod(mg_time, float(mg_params.get("period", 1.2))) < float(mg_params.get("period", 1.2)) * float(mg_params.get("green_frac", 0.5))
		minigame_panel.draw_rect(Rect2(Vector2(left, mid_y - 70), Vector2(span, 140)), DANGER_COLORS["safe"] if phg else DANGER_COLORS["critical"], true)
		return
	if archetype == "drag":
		var zone := float(mg_params.get("zone", 0.4))
		var center := float(mg_state.get("zone_center", 0.0))
		minigame_panel.draw_line(Vector2(left, mid_y), Vector2(right, mid_y), Color(0.4, 0.5, 0.65, 0.7), 6.0)
		minigame_panel.draw_rect(Rect2(Vector2(midx + (center - zone) * span * 0.5, mid_y - 40), Vector2(zone * span, 80)), Color(0.25, 0.78, 0.42, 0.30), true)
		var dot := float(mg_state.get("dot", 0.0))
		var in_zone := absf(dot - center) <= zone
		minigame_panel.draw_circle(Vector2(midx + dot * span * 0.5, mid_y), 28.0, DANGER_COLORS["safe"] if in_zone else DANGER_COLORS["critical"])
	elif mg_id == "beat_tap" or mg_id == "perfect_stop":
		var speed := float(mg_params.get("sweep_speed", mg_params.get("speed", 1.0)))
		var needle := sin(mg_time * speed * PI)
		var window := float(mg_params.get("window", 0.2))
		minigame_panel.draw_line(Vector2(left, mid_y), Vector2(right, mid_y), Color(0.4, 0.5, 0.65, 0.7), 6.0)
		minigame_panel.draw_rect(Rect2(Vector2(midx - window * span * 0.5, mid_y - 40), Vector2(window * span, 80)), Color(0.25, 0.78, 0.42, 0.30), true)
		minigame_panel.draw_circle(Vector2(midx + needle * span * 0.5, mid_y), 24.0, ACCENT)
	elif mg_id == "green_light":
		var cycle := float(mg_params.get("cycle", 1.0))
		var is_green := fmod(mg_time, cycle) < cycle * float(mg_params.get("green_frac", 0.5))
		minigame_panel.draw_rect(Rect2(Vector2(left, mid_y - 70), Vector2(span, 140)), DANGER_COLORS["safe"] if is_green else DANGER_COLORS["critical"], true)
		_mg_draw_progress(int(mg_state.get("goods", 0)), int(mg_params.get("needed", 3)), s)
	elif mg_id == "copy_cat":
		var seq: Array = mg_state.get("seq", [])
		var idx := int(mg_state.get("idx", 0))
		for i in seq.size():
			var col: Color = DANGER_COLORS["safe"] if i < idx else Color(0.7, 0.8, 0.95)
			var arrow := "L" if String(seq[i]) == "L" else "R"
			minigame_panel.draw_rect(Rect2(Vector2(left + span * (float(i) / maxf(1.0, float(seq.size()))), mid_y - 26), Vector2(span / float(seq.size()) - 8.0, 52)), Color(col.r, col.g, col.b, 0.3), true)
	elif mg_id == "twitchy":
		if bool(mg_state.get("flash", false)):
			minigame_panel.draw_rect(Rect2(Vector2(left, mid_y - 70), Vector2(span, 140)), DANGER_COLORS["critical"], true)
	else:
		var prog := 0.0
		if mg_id == "mash_meter" or mg_id == "hold_still":
			prog = float(mg_state.get("fill", 0.0)) / (1.0 if mg_id == "mash_meter" else float(mg_params.get("duration", 3.0)))
		minigame_panel.draw_rect(Rect2(Vector2(left, mid_y - 18), Vector2(span, 36)), Color(0.2, 0.25, 0.34, 0.7), true)
		minigame_panel.draw_rect(Rect2(Vector2(left, mid_y - 18), Vector2(span * clampf(prog, 0.0, 1.0), 36)), ACCENT, true)
		if mg_id == "tap_count":
			_mg_draw_progress(int(mg_state.get("count", 0)), int(mg_params.get("target_taps", 6)), s)
		elif mg_id == "whack":
			_mg_draw_progress(int(mg_state.get("hits", 0)), int(mg_params.get("needed", 4)), s)


func _mg_draw_progress(current: int, total: int, s: Vector2) -> void:
	var font := ThemeDB.fallback_font
	minigame_panel.draw_string(font, Vector2(s.x * 0.5 - 40, s.y * 0.66), "%d / %d" % [current, total], HORIZONTAL_ALIGNMENT_CENTER, 120, 40, Color(1, 1, 1))


func _on_mg_a_down() -> void:
	if not mg_running or mg_phase != "play":
		return
	mg_holding = true
	mg_tap_pending += 1
	if mg_id == "copy_cat":
		mg_state["presses"].append("L")


func _on_mg_a_up() -> void:
	mg_holding = false
	mg_state["released"] = true


func _on_mg_b_down() -> void:
	if not mg_running or mg_phase != "play":
		return
	if mg_id == "copy_cat":
		mg_state["presses"].append("R")


func _on_mg_bar_input(event: InputEvent) -> void:
	if not mg_running or mg_bar_area == null:
		return
	var x := -1.0
	if event is InputEventScreenTouch and event.pressed:
		x = event.position.x
	elif event is InputEventScreenDrag:
		x = event.position.x
	elif event is InputEventMouseButton and event.pressed:
		x = event.position.x
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		x = event.position.x
	if x >= 0.0:
		var mid := mg_bar_area.size.x * 0.5
		mg_drag_x = clampf((x - mid) / (mg_bar_area.size.x * 0.42), -1.0, 1.0)


# --- input ---------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if game_panel == null or not game_panel.visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_pointer(event.index, event.position)
		else:
			_end_pointer(event.index)
	elif event is InputEventScreenDrag:
		_drag_pointer(event.index, event.position, event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(-2, event.position)
		else:
			_end_pointer(-2)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_drag_pointer(-2, event.position, event.relative)


func _on_joystick_input(event: InputEvent) -> void:
	if game_panel == null or not game_panel.visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			joystick_drag_index = event.index
			joystick_center = joystick_area.get_global_rect().get_center()
			_update_joystick_from(event.position)
		elif event.index == joystick_drag_index:
			_end_pointer(event.index)
		joystick_area.accept_event()
	elif event is InputEventScreenDrag and event.index == joystick_drag_index:
		_update_joystick_from(event.position)
		joystick_area.accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			joystick_drag_index = -2
			joystick_center = joystick_area.get_global_rect().get_center()
			_update_joystick_from(event.global_position)
		else:
			_end_pointer(-2)
		joystick_area.accept_event()
	elif event is InputEventMouseMotion and joystick_drag_index == -2 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_update_joystick_from(event.global_position)
		joystick_area.accept_event()


func _begin_pointer(index: int, position_value: Vector2) -> void:
	var joystick_rect := joystick_area.get_global_rect().grow(40.0)
	if joystick_rect.has_point(position_value) and joystick_drag_index == -1:
		joystick_drag_index = index
		joystick_center = joystick_area.get_global_rect().get_center()
		_update_joystick_from(position_value)
	elif cam_drag_index == -1:
		cam_drag_index = index


func _drag_pointer(index: int, position_value: Vector2, relative: Vector2) -> void:
	if index == joystick_drag_index:
		_update_joystick_from(position_value)
	elif index == cam_drag_index:
		cam_yaw -= relative.x * 0.006


func _end_pointer(index: int) -> void:
	if index == joystick_drag_index:
		joystick_drag_index = -1
		move_vector = Vector2.ZERO
		joystick_area.queue_redraw()
	elif index == cam_drag_index:
		cam_drag_index = -1


func _update_joystick_from(pointer_position: Vector2) -> void:
	move_vector = ((pointer_position - joystick_center) / 92.0).limit_length(1.0)
	joystick_area.queue_redraw()


# --- screens/status --------------------------------------------------------------


func _show_menu() -> void:
	if menu_panel != null:
		menu_panel.visible = true
	if game_panel != null:
		game_panel.visible = false
	_rebuild_preview_prop()


func _show_game() -> void:
	if menu_panel != null:
		menu_panel.visible = false
	if game_panel != null:
		game_panel.visible = true
	if ready_button != null:
		ready_button.text = "READY"
		ready_button.visible = not spectator


func _update_status() -> void:
	var shape_text := String(hider_state.get("shape", "-"))
	var color_text := String(hider_state.get("color", "-"))
	var cooldown_text := "shape %.0fs  color %.0fs  dash %.0fs  mimic %.0fs" % [
		float(cooldowns.get("shape", 0.0)),
		float(cooldowns.get("color", 0.0)),
		float(cooldowns.get("dash", 0.0)),
		float(cooldowns.get("mimic", 0.0))
	]
	if menu_status_label != null:
		var games_hint := "Searching your Wi-Fi for games..." if discovered_games.is_empty() else "%d game(s) found" % discovered_games.size()
		menu_status_label.text = "%s   |   %s   %s" % [connection_status, games_hint, host_message]
	if phase_label != null:
		phase_label.text = _phase_text()
	if danger_badge != null:
		var alive := bool(hider_state.get("alive", true))
		var badge := danger.to_upper() if alive else "FOUND"
		danger_badge.text = badge
		danger_badge.add_theme_color_override("font_color", DANGER_COLORS.get("found" if not alive else danger, Color.WHITE))
	if info_label != null:
		var gun_note := ""
		if float(latest_snapshot.get("shot_cooldown_remaining", 0.0)) > 0.05:
			gun_note = "   GUN COOLING - RUN!"
		info_label.text = "%s %s   %s%s" % [shape_text, color_text, cooldown_text, gun_note]
	if ready_button != null:
		ready_button.visible = current_phase == "lobby" and not spectator
	if dash_button != null:
		var in_round := current_phase == "seek"
		var quake_uses := int(hider_state.get("earthquake_uses", 0))
		dash_button.disabled = not in_round or spectator or float(cooldowns.get("dash", 0.0)) > 0.05
		mimic_button.disabled = not in_round or spectator or float(cooldowns.get("mimic", 0.0)) > 0.05
		quake_button.disabled = not in_round or spectator or quake_uses <= 0
		ping_button.disabled = not in_round or spectator or float(cooldowns.get("ping", 0.0)) > 0.05
		dash_button.text = "DASH" if float(cooldowns.get("dash", 0.0)) <= 0.05 else "DASH %.0f" % float(cooldowns.get("dash", 0.0))
		mimic_button.text = "MIMIC" if float(cooldowns.get("mimic", 0.0)) <= 0.05 else "MIMIC %.0f" % float(cooldowns.get("mimic", 0.0))
		quake_button.text = "QUAKE x%d" % quake_uses if quake_uses > 0 else "QUAKE"
		ping_button.text = "PING" if float(cooldowns.get("ping", 0.0)) <= 0.05 else "PING %.0f" % float(cooldowns.get("ping", 0.0))
		color_button.disabled = not in_round or spectator
		shape_button.disabled = not in_round or spectator
	if overlay_label != null:
		var alive := bool(hider_state.get("alive", true))
		if joined and not alive:
			overlay_label.visible = true
			overlay_label.text = "FOUND!"
			overlay_label.add_theme_color_override("font_color", DANGER_COLORS["found"])
		elif joined and spectator:
			overlay_label.visible = true
			overlay_label.text = "SPECTATING"
			overlay_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.92))
		elif joined and bool(hider_state.get("held_by_seeker", false)):
			overlay_label.visible = true
			overlay_label.text = "BEING INSPECTED!"
			overlay_label.add_theme_color_override("font_color", DANGER_COLORS["critical"])
		else:
			overlay_label.visible = false
	if game_status_label != null:
		game_status_label.text = "%s   %s" % [connection_status, host_message]
	_update_minigame()


# Detects when an inspection begins (the seeker grabbed us) and launches the
# local minigame; re-arms once the host clears the inspection.
func _update_minigame() -> void:
	if practice_mode:
		return
	var mg: Dictionary = hider_state.get("inspection", {})
	var active := joined and not mg.is_empty() and String(mg.get("status", "")) == "active"
	if active and not mg_running and not mg_awaiting_clear:
		_minigame_start(String(mg.get("minigame", "")), int(mg.get("difficulty", 0)))
	elif not active:
		# Host cleared the inspection (resolved or dropped): stop and re-arm.
		mg_awaiting_clear = false
		if mg_running:
			_minigame_teardown()


func _flash_minigame(text: String, color: Color) -> void:
	if minigame_flash_label == null:
		return
	minigame_flash_label.text = text
	minigame_flash_label.add_theme_color_override("font_color", color)
	minigame_flash_label.visible = true
	minigame_flash_time = 1.4


func _phase_text() -> String:
	var time_remaining := float(latest_snapshot.get("time_remaining", 0.0))
	match current_phase:
		"lobby":
			return "LOBBY - ready up"
		"room_setup":
			return "SEEKER IS SETTING UP"
		"seek":
			# With the default no-timer mode the countdown parks at 0; hide it.
			if time_remaining > 0.5:
				return "SEEKER HUNTING %.0fs" % time_remaining
			return "SEEKER HUNTING"
		"results":
			return "ROUND OVER"
	return current_phase.to_upper()


# --- UI helpers ------------------------------------------------------------------


func _panel_style(radius: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(10)
	style.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35)
	style.set_border_width_all(1)
	return style


func _make_button(text: String, font_size: int, accent: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", font_size)
	var normal := StyleBoxFlat.new()
	normal.bg_color = ACCENT.darkened(0.25) if accent else Color(0.16, 0.2, 0.27)
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(8)
	var pressed := normal.duplicate()
	pressed.bg_color = normal.bg_color.lightened(0.2)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.12, 0.14, 0.18)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", pressed)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.6, 0.66))
	return button


func _make_line_edit(parent: Control, text: String, placeholder: String, width: float) -> LineEdit:
	var line_edit := LineEdit.new()
	line_edit.text = text
	line_edit.placeholder_text = placeholder
	line_edit.custom_minimum_size = Vector2(width, 40)
	parent.add_child(line_edit)
	return line_edit
