class_name ContentDatabase
extends RefCounted

const SHAPES_PATH := "res://content/objects/shapes.json"
const COLORS_PATH := "res://content/objects/colors.json"
const PATTERNS_PATH := "res://content/objects/patterns.json"

var shapes: Array = []
var colors: Array = []
var patterns: Array = []
var shape_by_id: Dictionary = {}
var color_by_id: Dictionary = {}
var pattern_by_id: Dictionary = {}


func load_default() -> void:
	shapes = _read_json_array(SHAPES_PATH)
	colors = _read_json_array(COLORS_PATH)
	patterns = _read_json_array(PATTERNS_PATH)
	_index()


static func _read_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open JSON file: %s" % path)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		return parsed
	push_error("Expected JSON array: %s" % path)
	return []


func _index() -> void:
	shape_by_id.clear()
	color_by_id.clear()
	pattern_by_id.clear()
	for shape in shapes:
		shape_by_id[shape["id"]] = shape
	for color in colors:
		color_by_id[color["id"]] = color
	for pattern in patterns:
		pattern_by_id[pattern["id"]] = pattern


func get_shape_ids() -> Array[String]:
	var ids: Array[String] = []
	for shape in shapes:
		ids.append(shape["id"])
	return ids


func get_color_ids() -> Array[String]:
	var ids: Array[String] = []
	for color in colors:
		ids.append(color["id"])
	return ids


func get_pattern_ids() -> Array[String]:
	var ids: Array[String] = []
	for pattern in patterns:
		ids.append(pattern["id"])
	return ids


func get_color_hex(color_id: String) -> String:
	return color_by_id.get(color_id, {}).get("hex", "#ffffff")


func get_shape_rest_mode(shape_id: String) -> String:
	return shape_by_id.get(shape_id, {}).get("rest_mode", "face")


func get_shape_display_name(shape_id: String) -> String:
	return shape_by_id.get(shape_id, {}).get("display_name", shape_id.capitalize())


func get_color_display_name(color_id: String) -> String:
	return color_by_id.get(color_id, {}).get("display_name", color_id.capitalize())


func get_pattern_display_name(pattern_id: String) -> String:
	return pattern_by_id.get(pattern_id, {}).get("display_name", pattern_id.capitalize())


func pick_weighted_shape(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for shape in shapes:
		total += float(shape.get("rarity_weight", 1.0))
	var roll := rng.randf() * total
	for shape in shapes:
		roll -= float(shape.get("rarity_weight", 1.0))
		if roll <= 0.0:
			return shape["id"]
	return shapes[0]["id"] if not shapes.is_empty() else "cube"


func pick_color(rng: RandomNumberGenerator) -> String:
	if colors.is_empty():
		return "red"
	return colors[rng.randi_range(0, colors.size() - 1)]["id"]


func pick_weighted_pattern(rng: RandomNumberGenerator) -> String:
	if patterns.is_empty():
		return "solid"
	var total := 0.0
	for pattern in patterns:
		total += float(pattern.get("spawn_weight", 1.0))
	var roll := rng.randf() * total
	for pattern in patterns:
		roll -= float(pattern.get("spawn_weight", 1.0))
		if roll <= 0.0:
			return pattern["id"]
	return patterns[0]["id"]
