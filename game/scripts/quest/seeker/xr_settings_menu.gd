class_name HidefallXrSettingsMenu
extends Node3D

signal action_requested(action)
signal setting_changed(section, key, value)

const PANEL_WIDTH := 1.38
const PANEL_HEIGHT := 1.16
const ROW_WIDTH := 1.18
const ROW_HEIGHT := 0.074
const ROW_START_Y := 0.39
const ROW_STEP := 0.082

var config
var rows: Array[Dictionary] = []
var row_labels: Array[Label3D] = []
var row_panels: Array[MeshInstance3D] = []
var hovered_index := -1

var normal_material: StandardMaterial3D
var hover_material: StandardMaterial3D
var action_material: StandardMaterial3D


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
		{"type": "action", "label": "Restart round", "action": "restart_round"},
		{"type": "action", "label": "End round", "action": "end_round"},
		{"type": "setting", "label": "Gun cooldown", "section": "seeker", "key": "shot_cooldown_seconds", "values": [0.5, 1.0, 1.5, 2.5, 3.5, 5.0], "suffix": "s"},
		{"type": "setting", "label": "Prop count", "section": "objects", "key": "decoy_count", "values": [30, 50, 75, 100, 125], "suffix": ""},
		{"type": "setting", "label": "Hunt time", "section": "round", "key": "seek_seconds", "values": [60, 90, 120, 180], "suffix": "s"},
		{"type": "setting", "label": "Blackout", "section": "round", "key": "blackout_seconds", "values": [5, 10, 15, 20], "suffix": "s"},
		{"type": "setting", "label": "Shape change", "section": "hiders", "key": "shape_change_cooldown", "values": [4, 8, 12, 18], "suffix": "s"},
		{"type": "setting", "label": "Color change", "section": "hiders", "key": "color_change_cooldown", "values": [2, 4, 6, 10], "suffix": "s"},
		{"type": "setting", "label": "Scan pulses", "section": "seeker", "key": "scan_pulse_count", "values": [0, 1, 2, 3], "suffix": ""},
		{"type": "setting", "label": "Bot hiders", "section": "hiders", "key": "bot_count", "values": [0, 1, 2, 3, 4, 6], "suffix": ""}
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
	title.font_size = 28
	title.outline_size = 7
	title.pixel_size = 0.00155
	title.width = 1180.0
	title.position = Vector3(-0.58, 0.515, 0.006)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.modulate = Color(0.25, 0.92, 1.0, 1.0)
	add_child(title)

	for index in rows.size():
		var y := ROW_START_Y - float(index) * ROW_STEP
		var row_panel := MeshInstance3D.new()
		row_panel.name = "Row%dPanel" % index
		var row_mesh := QuadMesh.new()
		row_mesh.size = Vector2(ROW_WIDTH, ROW_HEIGHT)
		row_panel.mesh = row_mesh
		row_panel.position = Vector3(0.0, y, 0.004)
		row_panel.material_override = action_material if rows[index].get("type", "") == "action" else normal_material
		add_child(row_panel)
		row_panels.append(row_panel)

		var label := Label3D.new()
		label.name = "Row%dLabel" % index
		label.font_size = 19
		label.outline_size = 5
		label.pixel_size = 0.00136
		label.width = 1160.0
		label.position = Vector3(-0.55, y + 0.018, 0.01)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.modulate = Color(0.93, 0.98, 1.0, 1.0)
		add_child(label)
		row_labels.append(label)

	var help := Label3D.new()
	help.name = "Help"
	help.text = "Y/M toggle menu   Right pointer + trigger selects\nTrigger shoots, grip grabs, A starts/scans when this menu is closed"
	help.font_size = 15
	help.outline_size = 5
	help.pixel_size = 0.00128
	help.width = 1180.0
	help.position = Vector3(-0.58, -0.49, 0.006)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	help.modulate = Color(0.72, 0.82, 0.95, 1.0)
	add_child(help)

	_update_labels()


func _update_labels() -> void:
	for index in row_labels.size():
		var row: Dictionary = rows[index]
		if row.get("type", "") == "action":
			row_labels[index].text = "  %s" % String(row.get("label", ""))
		else:
			var value = row["values"][int(row.get("value_index", 0))]
			row_labels[index].text = "  %s: %s%s" % [String(row.get("label", "")), _format_value(value), String(row.get("suffix", ""))]


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
			row_panels[row_index].material_override = action_material if rows[row_index].get("type", "") == "action" else normal_material


func _nearest_value_index(values: Array, current: Variant) -> int:
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
	normal_material = _make_panel_material(Color(0.06, 0.10, 0.15, 0.88))
	hover_material = _make_panel_material(Color(0.12, 0.46, 0.62, 0.96))
	action_material = _make_panel_material(Color(0.10, 0.15, 0.22, 0.92))


func _make_panel_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material
