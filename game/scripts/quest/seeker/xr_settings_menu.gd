class_name HidefallXrSettingsMenu
extends Node3D

signal action_requested(action)
signal setting_changed(section, key, value)

const PANEL_WIDTH := 0.24
const PANEL_HEIGHT := 0.26
const ROW_WIDTH := 0.205
const ROW_HEIGHT := 0.026
const ROW_START_Y := 0.062
const ROW_STEP := 0.030
const QUEST3_REFERENCE_VIEW_DISTANCE_M := 0.50
const QUEST3_MAX_REFERENCE_WIDTH_DEGREES := 28.0
const QUEST3_MAX_REFERENCE_HEIGHT_DEGREES := 30.0

var config
var rows: Array[Dictionary] = []
var page_index := 0
var row_labels: Array[Label3D] = []
var row_panels: Array[MeshInstance3D] = []
var row_value_labels: Array[Label3D] = []
var row_tracks: Array[MeshInstance3D] = []
var row_knobs: Array[MeshInstance3D] = []
var hovered_index := -1

# Where the seeker's aim ray meets the panel, surfaced so the host can draw a
# laser to it and the on-panel dot shows exactly where a press will land.
var pointer_dot: MeshInstance3D
var pointer_material: StandardMaterial3D
var pointer_world_point := Vector3.ZERO
var pointer_active := false

var normal_material: StandardMaterial3D
var hover_material: StandardMaterial3D
var action_material: StandardMaterial3D
var track_material: StandardMaterial3D
var fill_material: StandardMaterial3D
var knob_material: StandardMaterial3D
var toggle_off_material: StandardMaterial3D
var toggle_on_material: StandardMaterial3D


func setup(p_config) -> void:
	config = p_config
	_make_materials()
	_build_rows()
	_rebuild_visuals()
	set_open(false)


func set_open(open: bool) -> void:
	visible = open
	if not open:
		_set_hovered(-1)
		_set_pointer(Vector3.ZERO, false)


func toggle() -> void:
	set_open(not visible)


func is_open() -> bool:
	return visible


func get_row_count() -> int:
	return rows.size()


func get_current_page_title() -> String:
	return _page_title(page_index)


func get_panel_size() -> Vector2:
	return Vector2(PANEL_WIDTH, PANEL_HEIGHT)


func get_quest3_reference_angular_size() -> Vector2:
	return Vector2(
		_angular_degrees(PANEL_WIDTH, QUEST3_REFERENCE_VIEW_DISTANCE_M),
		_angular_degrees(PANEL_HEIGHT, QUEST3_REFERENCE_VIEW_DISTANCE_M)
	)


func get_quest3_reference_max_angular_size() -> Vector2:
	return Vector2(QUEST3_MAX_REFERENCE_WIDTH_DEGREES, QUEST3_MAX_REFERENCE_HEIGHT_DEGREES)


func get_row_label(index: int) -> String:
	if index < 0 or index >= row_labels.size():
		return ""
	return row_labels[index].text


func get_row_value_label(index: int) -> String:
	if index < 0 or index >= row_value_labels.size():
		return ""
	return row_value_labels[index].text


func force_hover(index: int) -> void:
	_set_hovered(index)


func update_pointer(origin: Vector3, direction: Vector3) -> bool:
	if not visible:
		_set_hovered(-1)
		_set_pointer(Vector3.ZERO, false)
		return false
	var local_origin := global_transform.affine_inverse() * origin
	var local_direction := (global_transform.affine_inverse().basis * direction).normalized()
	if absf(local_direction.z) < 0.0001:
		_set_hovered(-1)
		_set_pointer(Vector3.ZERO, false)
		return false
	var t := -local_origin.z / local_direction.z
	if t < 0.0:
		_set_hovered(-1)
		_set_pointer(Vector3.ZERO, false)
		return false
	var point := local_origin + local_direction * t
	var over_panel := absf(point.x) <= PANEL_WIDTH * 0.5 and absf(point.y) <= PANEL_HEIGHT * 0.5
	_set_pointer(point, over_panel)
	if not over_panel:
		_set_hovered(-1)
		return false
	for index in rows.size():
		var y := ROW_START_Y - float(index) * ROW_STEP
		if absf(point.x) <= ROW_WIDTH * 0.5 and point.y >= y - ROW_HEIGHT * 0.5 and point.y <= y + ROW_HEIGHT * 0.5:
			_set_hovered(index)
			return true
	_set_hovered(-1)
	return true


# Positions the on-panel dot and caches the world-space hit point for the host
# laser. A local point on the panel plane (z=0) is nudged slightly forward so
# the dot renders in front of the row quads.
func _set_pointer(local_point: Vector3, active: bool) -> void:
	pointer_active = active
	if pointer_dot != null:
		pointer_dot.visible = active
	if not active:
		return
	var surface := Vector3(local_point.x, local_point.y, 0.014)
	if pointer_dot != null:
		pointer_dot.position = surface
	pointer_world_point = global_transform * surface


func is_pointer_active() -> bool:
	return pointer_active


func get_pointer_world_point() -> Vector3:
	return pointer_world_point


func activate_hovered() -> bool:
	if hovered_index < 0 or hovered_index >= rows.size():
		return false
	var row: Dictionary = rows[hovered_index]
	if row.get("type", "") == "action":
		var action := String(row.get("action", ""))
		if action == "next_page":
			_set_page(posmod(page_index + 1, _page_count()))
			return true
		if action == "previous_page":
			_set_page(posmod(page_index - 1, _page_count()))
			return true
		action_requested.emit(String(row.get("action", "")))
		return true
	_cycle_setting(hovered_index)
	return true


func refresh_values() -> void:
	if config == null:
		return
	for index in rows.size():
		var row: Dictionary = rows[index]
		if row.get("type", "") != "setting":
			continue
		var current = config.get_value(String(row["section"]), String(row["key"]), row["values"][0])
		row["value_index"] = _nearest_value_index(row["values"], current)
		rows[index] = row
	_update_labels()


func _build_rows() -> void:
	rows = _rows_for_page(page_index)
	if config != null:
		for index in rows.size():
			var row: Dictionary = rows[index]
			if row.get("type", "") == "setting":
				var current = config.get_value(String(row["section"]), String(row["key"]), row["values"][0])
				row["value_index"] = _nearest_value_index(row["values"], current)
				rows[index] = row


func _rebuild_visuals() -> void:
	for child in get_children():
		child.queue_free()
	row_labels.clear()
	row_panels.clear()
	row_value_labels.clear()
	row_tracks.clear()
	row_knobs.clear()

	var panel := MeshInstance3D.new()
	panel.name = "SettingsPanel"
	var panel_mesh := QuadMesh.new()
	panel_mesh.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	panel.mesh = panel_mesh
	panel.material_override = _make_panel_material(Color(0.01, 0.025, 0.04, 0.93))
	add_child(panel)

	# Bright dot that rides the aim ray across the panel so the seeker sees
	# exactly where a press will land.
	pointer_dot = MeshInstance3D.new()
	pointer_dot.name = "PointerDot"
	var dot_mesh := QuadMesh.new()
	dot_mesh.size = Vector2(0.011, 0.011)
	pointer_dot.mesh = dot_mesh
	pointer_dot.material_override = pointer_material
	pointer_dot.visible = false
	add_child(pointer_dot)

	var title := Label3D.new()
	title.name = "Title"
	title.text = "%s CONTROL" % _page_title(page_index)
	title.font_size = 28
	title.outline_size = 3
	title.pixel_size = 0.00019
	title.width = 1070.0
	title.position = Vector3(-0.102, 0.108, 0.006)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.modulate = Color(0.25, 0.92, 1.0, 1.0)
	add_child(title)

	var shortcut := Label3D.new()
	shortcut.name = "ShortcutHint"
	shortcut.text = "A START"
	shortcut.font_size = 24
	shortcut.outline_size = 3
	shortcut.pixel_size = 0.00015
	shortcut.width = 615.0
	shortcut.position = Vector3(0.010, 0.107, 0.006)
	shortcut.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shortcut.modulate = Color(0.78, 0.90, 1.0, 1.0)
	add_child(shortcut)

	for index in rows.size():
		var y := ROW_START_Y - float(index) * ROW_STEP
		var row_type := String(rows[index].get("type", ""))
		var row_panel := MeshInstance3D.new()
		row_panel.name = "Row%dPanel" % index
		var row_mesh := QuadMesh.new()
		row_mesh.size = Vector2(ROW_WIDTH, ROW_HEIGHT)
		row_panel.mesh = row_mesh
		row_panel.position = Vector3(0.0, y, 0.004)
		if row_type == "action":
			row_panel.material_override = action_material
		else:
			row_panel.material_override = normal_material
		add_child(row_panel)
		row_panels.append(row_panel)

		var label := Label3D.new()
		label.name = "Row%dLabel" % index
		label.font_size = 28
		label.outline_size = 3
		label.pixel_size = 0.000186
		label.width = 806.0
		label.position = Vector3(-0.097, y + 0.005, 0.01)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.modulate = Color(0.93, 0.98, 1.0, 1.0)
		add_child(label)
		row_labels.append(label)

		var value_label := Label3D.new()
		value_label.name = "Row%dValue" % index
		value_label.font_size = 24
		value_label.outline_size = 3
		value_label.pixel_size = 0.0001875
		value_label.width = 507.0
		value_label.position = Vector3(-0.006, y + 0.005, 0.011)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value_label.modulate = Color(0.95, 1.0, 1.0, 1.0)
		value_label.visible = row_type == "setting"
		add_child(value_label)
		row_value_labels.append(value_label)

		var track := MeshInstance3D.new()
		track.name = "Row%dTrack" % index
		var track_mesh := QuadMesh.new()
		track_mesh.size = Vector2(0.068, 0.005)
		track.mesh = track_mesh
		track.position = Vector3(0.063, y - 0.007, 0.012)
		track.material_override = track_material
		track.visible = row_type == "setting"
		add_child(track)
		row_tracks.append(track)

		var knob := MeshInstance3D.new()
		knob.name = "Row%dKnob" % index
		var knob_mesh := QuadMesh.new()
		knob_mesh.size = Vector2(0.011, 0.011)
		knob.mesh = knob_mesh
		knob.position = Vector3(0.029, y - 0.007, 0.014)
		knob.material_override = knob_material
		knob.visible = row_type == "setting"
		add_child(knob)
		row_knobs.append(knob)

	_update_labels()


func _update_labels() -> void:
	for index in row_labels.size():
		var row: Dictionary = rows[index]
		var row_type := String(row.get("type", ""))
		if row_type == "action":
			row_labels[index].text = "  %s" % String(row.get("label", ""))
			row_value_labels[index].visible = false
			row_tracks[index].visible = false
			row_knobs[index].visible = false
		else:
			var value_index := int(row.get("value_index", 0))
			var value_text: String
			if row.has("labels"):
				value_text = String(row["labels"][value_index])
			else:
				value_text = _format_value(row["values"][value_index])
			var suffix := String(row.get("suffix", ""))
			row_labels[index].text = "  %s" % String(row.get("label", ""))
			row_value_labels[index].text = "%s%s" % [value_text, suffix]
			row_value_labels[index].visible = true
			row_tracks[index].visible = true
			row_knobs[index].visible = true
			_update_setting_control(index, row, value_index)


func _cycle_setting(index: int) -> void:
	var row: Dictionary = rows[index]
	var values: Array = row["values"]
	var next_index := posmod(int(row.get("value_index", 0)) + 1, values.size())
	row["value_index"] = next_index
	rows[index] = row
	var value = values[next_index]
	if config != null:
		config.set_value(String(row["section"]), String(row["key"]), value)
	setting_changed.emit(String(row["section"]), String(row["key"]), value)
	_update_labels()


func _set_hovered(index: int) -> void:
	if hovered_index == index:
		return
	hovered_index = index
	for row_index in row_panels.size():
		if row_index == hovered_index:
			row_panels[row_index].material_override = hover_material
		else:
			var row_type := String(rows[row_index].get("type", ""))
			if row_type == "action":
				row_panels[row_index].material_override = action_material
			else:
				row_panels[row_index].material_override = normal_material


func _update_setting_control(index: int, row: Dictionary, value_index: int) -> void:
	var values: Array = row["values"]
	var denom: int = maxi(1, values.size() - 1)
	var t := float(value_index) / float(denom)
	var style := String(row.get("style", "slider"))
	var y := ROW_START_Y - float(index) * ROW_STEP
	row_knobs[index].position.x = lerpf(0.029, 0.097, t)
	row_tracks[index].position = Vector3(0.063, y - 0.007, 0.012)
	if style == "toggle":
		row_tracks[index].scale = Vector3(0.58, 1.35, 1.0)
		row_tracks[index].material_override = toggle_on_material if bool(values[value_index]) else toggle_off_material
		row_knobs[index].position.x = 0.090 if bool(values[value_index]) else 0.036
	elif style == "segment":
		row_tracks[index].scale = Vector3(1.0, 1.65, 1.0)
		row_tracks[index].material_override = fill_material
	else:
		row_tracks[index].scale = Vector3(1.0, 1.0, 1.0)
		row_tracks[index].material_override = track_material
	row_knobs[index].material_override = knob_material


func _nearest_value_index(values: Array, current: Variant) -> int:
	if current is String:
		return maxi(0, values.find(current))
	var best_index := 0
	var best_distance := INF
	for index in values.size():
		var distance := absf(float(values[index]) - float(current))
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


func _format_value(value: Variant) -> String:
	var number := float(value)
	if absf(number - roundf(number)) < 0.001:
		return str(int(roundf(number)))
	return "%.1f" % number


func _set_page(next_page: int) -> void:
	page_index = clampi(next_page, 0, _page_count() - 1)
	_build_rows()
	_rebuild_visuals()


func _page_count() -> int:
	return 2


func _page_title(index: int) -> String:
	return "ROOM" if index == 1 else "ROUND"


func _rows_for_page(index: int) -> Array[Dictionary]:
	if index == 1:
		return [
			{"type": "setting", "label": "Props", "section": "objects", "key": "decoy_count", "values": [30, 50, 75, 100, 125], "style": "slider", "suffix": ""},
			{"type": "setting", "label": "Bots", "section": "hiders", "key": "bot_count", "values": [0, 1, 2, 3, 4, 6], "style": "slider", "suffix": ""},
			{"type": "setting", "label": "Shape", "section": "hiders", "key": "shape_change_cooldown", "values": [0, 4, 8, 12, 18], "style": "slider", "suffix": "s"},
			{"type": "setting", "label": "Color", "section": "hiders", "key": "color_change_cooldown", "values": [0, 2, 4, 6, 10], "style": "slider", "suffix": "s"},
			{"type": "action", "label": "< Round", "action": "previous_page"}
		]
	return [
		{"type": "action", "label": "End round", "action": "end_round"},
		{"type": "setting", "label": "Mode", "section": "round", "key": "mode", "values": ["one_shot", "endless_hiders"], "labels": ["One-shot", "Endless"], "style": "segment", "suffix": ""},
		{"type": "setting", "label": "Timer", "section": "round", "key": "end_on_seek_timeout", "values": [false, true], "labels": ["Off", "On"], "style": "toggle", "suffix": ""},
		{"type": "setting", "label": "Hunt", "section": "round", "key": "seek_seconds", "values": [60, 90, 120, 180], "style": "slider", "suffix": "s"},
		{"type": "setting", "label": "Gun", "section": "seeker", "key": "shot_cooldown_seconds", "values": [0.5, 1.0, 1.5, 2.5, 3.5, 5.0], "style": "slider", "suffix": "s"},
		{"type": "setting", "label": "Scans", "section": "seeker", "key": "scan_pulse_count", "values": [0, 1, 2, 3], "style": "slider", "suffix": ""},
		{"type": "action", "label": "Room >", "action": "next_page"}
	]


static func _angular_degrees(size_m: float, distance_m: float) -> float:
	return rad_to_deg(2.0 * atan((size_m * 0.5) / distance_m))


func _make_materials() -> void:
	normal_material = _make_panel_material(Color(0.025, 0.055, 0.085, 0.90))
	hover_material = _make_panel_material(Color(0.08, 0.42, 0.62, 0.97))
	action_material = _make_panel_material(Color(0.12, 0.11, 0.18, 0.94))
	track_material = _make_panel_material(Color(0.10, 0.17, 0.24, 0.96))
	fill_material = _make_panel_material(Color(0.04, 0.38, 0.50, 0.98))
	knob_material = _make_panel_material(Color(0.72, 1.0, 1.0, 1.0))
	toggle_off_material = _make_panel_material(Color(0.18, 0.20, 0.24, 0.98))
	toggle_on_material = _make_panel_material(Color(0.0, 0.75, 0.62, 0.98))
	pointer_material = _make_panel_material(Color(1.0, 0.95, 0.35, 1.0))
	pointer_material.emission_enabled = true
	pointer_material.emission = Color(1.0, 0.9, 0.3, 1.0)
	pointer_material.emission_energy_multiplier = 3.0


func _make_panel_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material
