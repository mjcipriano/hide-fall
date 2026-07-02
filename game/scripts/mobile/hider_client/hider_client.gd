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
		var in_round := current_phase == "object_rain" or current_phase == "seek"
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


func _phase_text() -> String:
	var time_remaining := float(latest_snapshot.get("time_remaining", 0.0))
	match current_phase:
		"lobby":
			return "LOBBY - ready up"
		"room_setup":
			return "SEEKER IS SETTING UP"
		"object_rain":
			return "DROPPING IN - GET READY %.0fs" % time_remaining
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
