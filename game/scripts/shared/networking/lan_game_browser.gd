class_name LanGameBrowser
extends Node

# Listens for Hidefall UDP beacons on the local network and keeps a live list
# of joinable games, expiring hosts that stop announcing.

signal games_updated(games: Array)

const LanGameAnnouncerScript := preload("res://scripts/shared/networking/lan_game_announcer.gd")
const EXPIRY_SECONDS := 5.0

var udp := PacketPeerUDP.new()
var discovery_port := 29445
var games: Dictionary = {}
var _started := false


func start(p_discovery_port: int = 29445) -> Error:
	discovery_port = p_discovery_port
	var error := udp.bind(discovery_port)
	if error != OK:
		return error
	_started = true
	set_process(true)
	return OK


func stop() -> void:
	_started = false
	set_process(false)
	udp.close()
	games.clear()


func get_games() -> Array:
	var list: Array = []
	for key in games:
		list.append(games[key])
	list.sort_custom(func(a, b): return String(a.get("host_name", "")) < String(b.get("host_name", "")))
	return list


# Validates and normalizes one beacon; empty result means not a Hidefall beacon.
static func parse_beacon(text: String, sender_ip: String = "") -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	if String(parsed.get("game", "")) != LanGameAnnouncerScript.BEACON_GAME:
		return {}
	if not parsed.has("port") or not parsed.has("room_id"):
		return {}
	var info: Dictionary = parsed.duplicate(true)
	if not sender_ip.is_empty():
		info["host_ip"] = sender_ip
	return info


func _process(_delta: float) -> void:
	if not _started:
		return
	var changed := false
	while udp.get_available_packet_count() > 0:
		var text := udp.get_packet().get_string_from_utf8()
		var info := parse_beacon(text, udp.get_packet_ip())
		if info.is_empty():
			continue
		info["last_seen"] = Time.get_ticks_msec() / 1000.0
		games["%s:%s" % [info.get("host_ip", "?"), str(info.get("port", 0))]] = info
		changed = true
	var now := Time.get_ticks_msec() / 1000.0
	for key in games.keys():
		if now - float(games[key].get("last_seen", 0.0)) > EXPIRY_SECONDS:
			games.erase(key)
			changed = true
	if changed:
		games_updated.emit(get_games())
