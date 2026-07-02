class_name HidefallXrSettingsMenu
extends Node3D

signal action_requested(action)
signal setting_changed(section, key, value)

const PANEL_WIDTH := 0.52
const PANEL_HEIGHT := 0.46
const ROW_WIDTH := 0.45
const ROW_HEIGHT := 0.030
const ROW_START_Y := 0.125
const ROW_STEP := 0.034

var config
var rows: Array[Dictionary] = []
var row_labels: Array[Label3D] = []
var row_panels: Array[MeshInstance3D] = []
var row_value_labels: Array[Label3D] = []
var row_tracks: Array[MeshInstance3D] = []
var row_knobs: Array[MeshInstance3D] = []
var hovered_index := -1

var normal_material: StandardMaterial3D
var hover_material: StandardMaterial3D
var action_material: StandardMaterial3D
var track_material: StandardMaterial3D
var fill_material: StandardMaterial3D
var knob_material: StandardMaterial3D
var toggle_off_material: StandardMaterial3D
var toggle_on_material: StandardMaterial3D
var header_material: StandardMaterial3D


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


func toggle() -> void:
	set_open(not visible)


func is_open() -> bool:
	return visible


func get_row_count() -> int:
	return rows.size()


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
		return false
	var local_origin := global_transform.affine_inverse() * origin
	var local_direction := (global_transform.affine_inverse().basis * direction).normalized()
	if absf(local_direction.z) < 0.0001:
		_set_hovered(-1)
		return false
	var t := -local_origin.z / local_direction.z
	if t < 0.0:
		_set_hovered(-1)
		return false
	var point := local_origin + local_direction * t
	var over_panel := absf(point.x) <= PANEL_WIDTH * 0.5 and absf(point.y) <= PANEL_HEIGHT * 0.5
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


func activate_hovered() -> bool:
	if hovered_index < 0 or hovered_index >= rows.size():
		return false
	var row: Dictionary = rows[hovered_index]
	if row.get("type", "") == "header":
		return false
	if row.get("type", "") == "action":
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
	rows = [
		{"type": "header", "label": "ROUND CONTROL"},
		{"type": "action", "label": "End active round", "action": "end_round"},
		{"type": "setting", "label": "Mode", "section": "round", "key": "mode", "values": ["one_shot", "endless_hiders"], "labels": ["One-shot", "Endless"], "style": "segment", "suffix": ""},
		{"type": "setting", "label": "Timer ends hunt", "section": "round", "key": "end_on_seek_timeout", "values": [false, true], "labels": ["Off", "On"], "style": "toggle", "suffix": ""},
		{"type": "header", "label": "SEEKER"},
		{"type": "setting", "label": "Gun cooldown", "section": "seeker", "key": "shot_cooldown_seconds", "values": [0.5, 1.0, 1.5, 2.5, 3.5, 5.0], "style": "slider", "suffix": "s"},
		{"type": "setting", "label": "Hunt time", "section": "round", "key": "seek_seconds", "values": [60, 90, 120, 180], "style": "slider", "suffix": "s"},
		{"type": "setting", "label": "Scan pulses", "section": "seeker", "key": "scan_pulse_count", "values": [0, 1, 2, 3], "style": "slider", "suffix": ""},
		{"type": "header", "label": "ROOM + HIDERS"},
		{"type": "setting", "label": "Prop count", "section": "objects", "key": "decoy_count", "values": [30, 50, 75, 100, 125], "style": "slider", "suffix": ""},
		{"type": "setting", "label": "Shape shift", "section": "hiders", "key": "shape_change_cooldown", "values": [4, 8, 12, 18], "style": "slider", "suffix": "s"},
		{"type": "setting", "label": "Color shift", "section": "hiders", "key": "color_change_cooldown", "values": [2, 4, 6, 10], "style": "slider", "suffix": "s"},
		{"type": "setting", "label": "Bot hiders", "section": "hiders", "key": "bot_count", "values": [0, 1, 2, 3, 4, 6], "style": "slider", "suffix": ""}
	]
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

	var title := Label3D.new()
	title.name = "Title"
	title.text = "HIDEFALL SETTINGS"
	title.font_size = 13
	title.outline_size = 4
	title.pixel_size = 0.00078
	title.width = 1180.0
	title.position = Vector3(-0.215, 0.190, 0.006)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.modulate = Color(0.25, 0.92, 1.0, 1.0)
	add_child(title)

	var shortcut := Label3D.new()
	shortcut.name = "ShortcutHint"
	shortcut.text = "A / R starts, confirms, and rematches"
	shortcut.font_size = 8
	shortcut.outline_size = 2
	shortcut.pixel_size = 0.00066
	shortcut.width = 900.0
	shortcut.position = Vector3(-0.215, 0.166, 0.006)
	shortcut.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	shortcut.modulate = Color(0.78, 0.90, 1.0, 1.0)
	add_child(shortcut)

	for index in rows.size():
		var y := ROW_START_Y - float(index) * ROW_STEP
		var row_type := String(rows[index].get("type", ""))
		var row_panel := MeshInstance3D.new()
		row_panel.name = "Row%dPanel" % index
		var row_mesh := QuadMesh.new()
		row_mesh.size = Vector2(ROW_WIDTH, ROW_HEIGHT * 0.52 if row_type == "header" else ROW_HEIGHT)
		row_panel.mesh = row_mesh
		row_panel.position = Vector3(0.0, y, 0.004)
		if row_type == "header":
			row_panel.material_override = header_material
		elif row_type == "action":
			row_panel.material_override = action_material
		else:
			row_panel.material_override = normal_material
		add_child(row_panel)
		row_panels.append(row_panel)

		var label := Label3D.new()
		label.name = "Row%dLabel" % index
		label.font_size = 8 if row_type == "header" else 10
		label.outline_size = 2
		label.pixel_size = 0.00066 if row_type == "header" else 0.00070
		label.width = 900.0
		label.position = Vector3(-0.210, y + (0.005 if row_type == "header" else 0.007), 0.01)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.modulate = Color(0.35, 0.95, 1.0, 1.0) if row_type == "header" else Color(0.93, 0.98, 1.0, 1.0)
		add_child(label)
		row_labels.append(label)

		var value_label := Label3D.new()
		value_label.name = "Row%dValue" % index
		value_label.font_size = 9
		value_label.outline_size = 2
		value_label.pixel_size = 0.00066
		value_label.width = 520.0
		value_label.position = Vector3(0.076, y + 0.007, 0.011)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value_label.modulate = Color(0.95, 1.0, 1.0, 1.0)
		value_label.visible = row_type == "setting"
		add_child(value_label)
		row_value_labels.append(value_label)

		var track := MeshInstance3D.new()
		track.name = "Row%dTrack" % index
		var track_mesh := QuadMesh.new()
		track_mesh.size = Vector2(0.145, 0.006)
		track.mesh = track_mesh
		track.position = Vector3(0.132, y - 0.008, 0.012)
		track.material_override = track_material
		track.visible = row_type == "setting"
		add_child(track)
		row_tracks.append(track)

		var knob := MeshInstance3D.new()
		knob.name = "Row%dKnob" % index
		var knob_mesh := QuadMesh.new()
		knob_mesh.size = Vector2(0.017, 0.017)
		knob.mesh = knob_mesh
		knob.position = Vector3(0.060, y - 0.008, 0.014)
		knob.material_override = knob_material
		knob.visible = row_type == "setting"
		add_child(knob)
		row_knobs.append(knob)

	var help := Label3D.new()
	help.name = "Help"
	help.text = "Y/M menu   Right pointer + trigger edits settings\nClosed: trigger shoots, grip grabs, A scans or starts"
	help.font_size = 7
	help.outline_size = 2
	help.pixel_size = 0.00062
	help.width = 900.0
	help.position = Vector3(-0.215, -0.205, 0.006)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	help.modulate = Color(0.72, 0.82, 0.95, 1.0)
	add_child(help)

	_update_labels()


func _update_labels() -> void:
	for index in row_labels.size():
		var row: Dictionary = rows[index]
		var row_type := String(row.get("type", ""))
		if row_type == "header":
			row_labels[index].text = "  %s" % String(row.get("label", ""))
			row_value_labels[index].visible = false
			row_tracks[index].visible = false
			row_knobs[index].visible = false
		elif row_type == "action":
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
			if row_type == "header":
				row_panels[row_index].material_override = header_material
			elif row_type == "action":
				row_panels[row_index].material_override = action_material
			else:
				row_panels[row_index].material_override = normal_material


func _update_setting_control(index: int, row: Dictionary, value_index: int) -> void:
	var values: Array = row["values"]
	var denom: int = maxi(1, values.size() - 1)
	var t := float(value_index) / float(denom)
	var style := String(row.get("style", "slider"))
	var y := ROW_START_Y - float(index) * ROW_STEP
	row_knobs[index].position.x = lerpf(0.060, 0.204, t)
	row_tracks[index].position = Vector3(0.132, y - 0.008, 0.012)
	if style == "toggle":
		row_tracks[index].scale = Vector3(0.58, 1.35, 1.0)
		row_tracks[index].material_override = toggle_on_material if bool(values[value_index]) else toggle_off_material
		row_knobs[index].position.x = 0.190 if bool(values[value_index]) else 0.074
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


func _make_materials() -> void:
	normal_material = _make_panel_material(Color(0.025, 0.055, 0.085, 0.90))
	hover_material = _make_panel_material(Color(0.08, 0.42, 0.62, 0.97))
	action_material = _make_panel_material(Color(0.12, 0.11, 0.18, 0.94))
	header_material = _make_panel_material(Color(0.03, 0.16, 0.20, 0.72))
	track_material = _make_panel_material(Color(0.10, 0.17, 0.24, 0.96))
	fill_material = _make_panel_material(Color(0.04, 0.38, 0.50, 0.98))
	knob_material = _make_panel_material(Color(0.72, 1.0, 1.0, 1.0))
	toggle_off_material = _make_panel_material(Color(0.18, 0.20, 0.24, 0.98))
	toggle_on_material = _make_panel_material(Color(0.0, 0.75, 0.62, 0.98))


func _make_panel_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material
