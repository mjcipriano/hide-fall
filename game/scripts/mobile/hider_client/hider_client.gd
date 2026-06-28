extends Control

const NetworkMessageValidatorScript := preload("res://scripts/shared/networking/network_message_validator.gd")
const WebSocketLanClientScript := preload("res://scripts/shared/networking/websocket_lan_client.gd")
const ContentDatabaseScript := preload("res://scripts/shared/content/content_database.gd")

var player_id := ""
var player_name := "Hider"
var current_phase := "disconnected"
var danger := "safe"
var move_vector := Vector2.ZERO
var freeze_pressed := false
var client
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
var available_shapes: Array = []
var available_colors: Array = []
var selected_shape_index := 0
var selected_color_index := 0
var pending_shape: Variant = null
var pending_color: Variant = null

var status_label: Label
var joystick: ColorRect
var freeze_button: Button
var color_button: Button
var shape_button: Button
var host_input: LineEdit
var port_input: LineEdit
var room_input: LineEdit
var token_input: LineEdit
var name_input: LineEdit
var connect_button: Button
var ready_button: Button

const MAP_RECT := Rect2(16, 118, 760, 430)


func _ready() -> void:
	content = ContentDatabaseScript.new()
	content.load_default()
	available_shapes = content.get_shape_ids()
	available_colors = content.get_color_ids()
	client = WebSocketLanClientScript.new()
	client.name = "WebSocketLanClient"
	add_child(client)
	client.connected.connect(_on_connected)
	client.disconnected.connect(_on_disconnected)
	client.connection_failed.connect(_on_connection_failed)
	client.message_received.connect(_on_message_received)
	_build_ui()
	_update_status()


func _process(delta: float) -> void:
	if joined and client.is_connected_to_host():
		input_accumulator += delta
		if input_accumulator >= 0.05:
			input_accumulator = 0.0
			client.send_message(build_hider_input())


func build_hider_input() -> Dictionary:
	var message := {
		"type": "hider_input",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"player_id": player_id,
		"move": [move_vector.x, move_vector.y],
		"rotate": 0.0,
		"freeze": freeze_pressed,
		"request_shape": pending_shape,
		"request_color": pending_color,
		"ability": null,
		"client_time": Time.get_ticks_msec() / 1000.0
	}
	pending_shape = null
	pending_color = null
	return message


func apply_snapshot(snapshot: Dictionary) -> void:
	latest_snapshot = snapshot
	current_phase = snapshot.get("phase", current_phase)
	danger = snapshot.get("danger", danger)
	visible_objects = snapshot.get("objects", [])
	cooldowns = snapshot.get("cooldowns", {})
	hider_state = snapshot.get("hider_state", {})
	_update_status()
	queue_redraw()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.05, 0.07, 0.10)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	status_label = Label.new()
	status_label.position = Vector2(16, 12)
	status_label.size = Vector2(1000, 34)
	status_label.add_theme_font_size_override("font_size", 18)
	add_child(status_label)

	host_input = _make_line_edit("127.0.0.1", Vector2(16, 52), Vector2(160, 34))
	port_input = _make_line_edit("29444", Vector2(184, 52), Vector2(86, 34))
	room_input = _make_line_edit("842913", Vector2(278, 52), Vector2(104, 34))
	token_input = _make_line_edit("hidefall", Vector2(390, 52), Vector2(116, 34))
	name_input = _make_line_edit("Hider", Vector2(514, 52), Vector2(120, 34))
	connect_button = _make_button("Join", Vector2(648, 50), Vector2(128, 38))
	connect_button.pressed.connect(_on_join_pressed)
	ready_button = _make_button("Ready", Vector2(830, 50), Vector2(160, 54))
	ready_button.disabled = true
	ready_button.pressed.connect(_on_ready_pressed)

	joystick = ColorRect.new()
	joystick.color = Color(0.2, 0.45, 1.0, 0.7)
	joystick.position = Vector2(70, 540)
	joystick.size = Vector2(120, 120)
	add_child(joystick)

	freeze_button = _make_button("Freeze", Vector2(830, 130), Vector2(160, 72))
	color_button = _make_button("Color", Vector2(830, 230), Vector2(160, 72))
	shape_button = _make_button("Shape", Vector2(830, 330), Vector2(160, 72))
	freeze_button.button_down.connect(func() -> void: freeze_pressed = true)
	freeze_button.button_up.connect(func() -> void: freeze_pressed = false)
	color_button.pressed.connect(_request_next_color)
	shape_button.pressed.connect(_request_next_shape)


func _make_line_edit(text: String, position_value: Vector2, size_value: Vector2) -> LineEdit:
	var line_edit := LineEdit.new()
	line_edit.text = text
	line_edit.position = position_value
	line_edit.size = size_value
	add_child(line_edit)
	return line_edit


func _make_button(text: String, position_value: Vector2, size_value: Vector2 = Vector2(160, 72)) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position_value
	button.size = size_value
	button.add_theme_font_size_override("font_size", 22)
	add_child(button)
	return button


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_update_joystick(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_update_joystick(event.position)
		else:
			move_vector = Vector2.ZERO
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_update_joystick(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		move_vector = Vector2.ZERO


func _update_status() -> void:
	if status_label == null:
		return
	var shape_text: String = hider_state.get("shape", "-")
	var color_text: String = hider_state.get("color", "-")
	var cooldown_text := "shape %.1f / color %.1f" % [float(cooldowns.get("shape", 0.0)), float(cooldowns.get("color", 0.0))]
	status_label.text = "Hidefall Hider | %s | Phase: %s | %s | Danger: %s | %s %s | %s | %s" % [
		connection_status,
		current_phase,
		"SPECTATOR" if spectator else ("READY" if player_ready else "NOT READY"),
		danger,
		shape_text,
		color_text,
		cooldown_text,
		host_message
	]


func _draw() -> void:
	draw_rect(MAP_RECT, Color(0.09, 0.12, 0.18), true)
	draw_rect(MAP_RECT, Color(0.18, 0.27, 0.38), false, 2.0)
	var center := MAP_RECT.position + MAP_RECT.size * 0.5
	var scale := min(MAP_RECT.size.x, MAP_RECT.size.y) / 7.0
	draw_circle(center, 3.0 * scale, Color(0.0, 0.78, 1.0, 0.18))
	draw_arc(center, 3.0 * scale, 0.0, TAU, 96, Color(0.0, 0.78, 1.0, 0.75), 2.0)
	for obj in visible_objects:
		if not obj is Dictionary:
			continue
		var position_array: Array = obj.get("position", [0.0, 0.0, 0.0])
		if position_array.size() < 3:
			continue
		var world := Vector2(float(position_array[0]), float(position_array[2]))
		var screen := center + world * scale
		var radius := 5.0
		if obj.get("object_id", "") == hider_state.get("object_id", ""):
			radius = 10.0
		var color := Color(content.get_color_hex(obj.get("color", "white")))
		if obj.get("is_hider", false):
			draw_circle(screen, radius + 4.0, Color.WHITE)
		draw_circle(screen, radius, color)


func _update_joystick(pointer_position: Vector2) -> void:
	var center := joystick.position + joystick.size * 0.5
	if pointer_position.distance_to(center) < 160.0:
		move_vector = (pointer_position - center).limit_length(60.0) / 60.0


func _on_join_pressed() -> void:
	player_name = name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Hider"
	connection_status = "connecting"
	player_ready = false
	spectator = false
	if ready_button != null:
		ready_button.disabled = true
		ready_button.text = "Ready"
	host_message = ""
	_update_status()
	var error: Error = client.connect_to_host(host_input.text.strip_edges(), int(port_input.text))
	if error != OK:
		connection_status = "connect error %d" % int(error)
		_update_status()


func _on_connected() -> void:
	connection_status = "connected"
	client.send_message({
		"type": "join_request",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"room_id": room_input.text.strip_edges(),
		"token": token_input.text.strip_edges(),
		"player_name": player_name
	})
	_update_status()


func _on_disconnected() -> void:
	joined = false
	player_ready = false
	connection_status = "disconnected"
	current_phase = "disconnected"
	if ready_button != null:
		ready_button.disabled = true
	_update_status()


func _on_connection_failed() -> void:
	joined = false
	player_ready = false
	connection_status = "connection failed"
	if ready_button != null:
		ready_button.disabled = true
	_update_status()


func _on_message_received(message: Dictionary) -> void:
	match message.get("type", ""):
		"join_accepted":
			player_id = message.get("player_id", "")
			spectator = bool(message.get("spectator", false))
			available_shapes = message.get("shapes", available_shapes)
			available_colors = message.get("colors", available_colors)
			joined = true
			player_ready = false
			connection_status = "joined as %s" % player_id
			if ready_button != null:
				ready_button.disabled = spectator
				ready_button.text = "Spectator" if spectator else "Ready"
		"join_rejected":
			joined = false
			host_message = "%s: %s" % [message.get("reason", "rejected"), message.get("detail", "")]
			connection_status = "rejected"
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


func _on_ready_pressed() -> void:
	if not joined or player_id.is_empty() or spectator:
		return
	player_ready = not player_ready
	ready_button.text = "Unready" if player_ready else "Ready"
	client.send_message({
		"type": "ready_state",
		"version": NetworkMessageValidatorScript.PROTOCOL_VERSION,
		"player_id": player_id,
		"ready": player_ready
	})
	_update_status()
