extends Node


func _ready() -> void:
	var target_scene := "res://scenes/quest/host_prototype.tscn"
	if OS.has_feature("mobile_client"):
		target_scene = "res://scenes/mobile/hider_client.tscn"
	get_tree().change_scene_to_file(target_scene)

